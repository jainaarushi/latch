#!/usr/bin/env bash
set -euo pipefail

GPU_INDEX="${GPU_INDEX:-0}"
MIG_PROFILE_ID="${MIG_PROFILE_ID:-14}"   # 2g.10gb on A100-40GB
MIG_INSTANCES="${MIG_INSTANCES:-3}"
NAMESPACE="${NAMESPACE:-kubnamespace}"
AUTO_REBOOT="${AUTO_REBOOT:-true}"

log() { echo "[mig-setup] $*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

mig_current() {
  nvidia-smi -i "$GPU_INDEX" -q | awk '/MIG Mode/{f=1;next} f && /Current/{print $3; exit}'
}

mig_pending() {
  nvidia-smi -i "$GPU_INDEX" -q | awk '/MIG Mode/{f=1;next} f && /Pending/{print $3; exit}'
}

enable_mig_if_needed() {
  local current pending
  current="$(mig_current)"
  pending="$(mig_pending)"

  log "MIG mode current=${current} pending=${pending}"

  if [[ "$current" == "Enabled" ]]; then
    return
  fi

  log "Enabling MIG mode on GPU ${GPU_INDEX}"
  sudo nvidia-smi -i "$GPU_INDEX" -mig 1
  current="$(mig_current)"
  pending="$(mig_pending)"

  if [[ "$current" != "Enabled" && "$pending" == "Enabled" ]]; then
    if [[ "$AUTO_REBOOT" == "true" ]]; then
      log "Reboot required to activate MIG. Rebooting now. Re-run this script after host is back."
      sudo reboot
      exit 0
    fi
    echo "MIG mode pending enabled. Reboot required, then rerun script." >&2
    exit 2
  fi
}

scale_down_gpu_workloads() {
  kubectl -n "$NAMESPACE" scale deploy/ms-inference-scheduling-llm-d-modelservice-decode --replicas=0 >/dev/null 2>&1 || true
  kubectl -n "$NAMESPACE" scale deploy/vllm --replicas=0 >/dev/null 2>&1 || true
}

recreate_mig_layout() {
  log "Clearing existing MIG instances"
  sudo nvidia-smi mig -i "$GPU_INDEX" -dci >/dev/null 2>&1 || true
  sudo nvidia-smi mig -i "$GPU_INDEX" -dgi >/dev/null 2>&1 || true

  local profile_csv
  profile_csv="$(yes "$MIG_PROFILE_ID" | head -n "$MIG_INSTANCES" | paste -sd, -)"

  log "Creating MIG layout profile_id=${MIG_PROFILE_ID} count=${MIG_INSTANCES}"
  sudo nvidia-smi mig -i "$GPU_INDEX" -cgi "$profile_csv" -C
  nvidia-smi -L
}

configure_device_plugin_for_mig() {
  log "Configuring NVIDIA device plugin for MIG"
  kubectl -n kube-system set env ds/nvidia-device-plugin-daemonset MIG_STRATEGY=single FAIL_ON_INIT_ERROR=false >/dev/null
  kubectl -n kube-system patch ds nvidia-device-plugin-daemonset \
    --type='json' \
    -p='[{"op":"replace","path":"/spec/template/spec/containers/0/securityContext","value":{"privileged":true,"allowPrivilegeEscalation":true}}]' >/dev/null

  kubectl -n kube-system rollout restart ds/nvidia-device-plugin-daemonset >/dev/null
  kubectl -n kube-system rollout status ds/nvidia-device-plugin-daemonset --timeout=300s >/dev/null
}

wait_for_allocatable() {
  log "Waiting for nvidia.com/gpu allocatable >= ${MIG_INSTANCES}"
  local i alloc
  for i in $(seq 1 60); do
    alloc="$(kubectl get node -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}' 2>/dev/null || true)"
    if [[ -n "$alloc" && "$alloc" =~ ^[0-9]+$ ]] && (( alloc >= MIG_INSTANCES )); then
      log "Node allocatable nvidia.com/gpu=${alloc}"
      return
    fi
    sleep 2
  done

  echo "Timed out waiting for MIG allocatable resources" >&2
  kubectl -n kube-system logs -l name=nvidia-device-plugin-ds --tail=120 || true
  exit 3
}

main() {
  need_cmd nvidia-smi
  need_cmd kubectl
  need_cmd sudo

  enable_mig_if_needed
  scale_down_gpu_workloads
  recreate_mig_layout
  configure_device_plugin_for_mig
  wait_for_allocatable

  log "Complete. MIG slices are ready."
  kubectl get node -o jsonpath='{.items[0].status.allocatable}'
  echo
}

main "$@"
