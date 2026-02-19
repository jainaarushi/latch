#!/usr/bin/env bash
set -euo pipefail

MIG_STRATEGY=${MIG_STRATEGY:-single}
INSTALL_K3S=${INSTALL_K3S:-true}

log() {
  echo "[bootstrap-k8s-gpu] $*"
}

need_sudo() {
  if ! command -v sudo >/dev/null 2>&1; then
    log "sudo is required"
    exit 1
  fi
}

install_k3s_if_needed() {
  if kubectl cluster-info >/dev/null 2>&1; then
    log "Kubernetes context already reachable; skipping k3s install."
    return
  fi

  if [[ "${INSTALL_K3S}" != "true" ]]; then
    log "No reachable cluster and INSTALL_K3S=false."
    exit 1
  fi

  log "Installing k3s"
  curl -sfL https://get.k3s.io | sudo INSTALL_K3S_EXEC='--write-kubeconfig-mode 644' sh -
}

configure_nvidia_runtime() {
  if ! command -v nvidia-ctk >/dev/null 2>&1; then
    log "nvidia-ctk not found. Run ./scripts/bootstrap_gpu_host.sh first."
    exit 1
  fi

  local cfg_tmpl="/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl"
  log "Configuring NVIDIA runtime for containerd"
  sudo nvidia-ctk runtime configure --runtime=containerd --config "${cfg_tmpl}"
  sudo systemctl restart k3s
}

ensure_prereqs() {
  ./scripts/bootstrap_prereqs.sh
}

install_device_plugin() {
  log "Installing NVIDIA k8s-device-plugin (MIG strategy: ${MIG_STRATEGY})"
  helm repo add nvidia https://nvidia.github.io/k8s-device-plugin >/dev/null 2>&1 || true
  helm repo update >/dev/null

  helm upgrade --install nvdp nvidia/k8s-device-plugin \
    -n kube-system \
    --set migStrategy="${MIG_STRATEGY}" \
    --set failOnInitError=false >/dev/null

  kubectl -n kube-system rollout status ds/nvdp-nvidia-device-plugin --timeout=5m >/dev/null
}

wait_for_gpu_resources() {
  local retries=30
  local sleep_s=5
  local i

  for i in $(seq 1 "${retries}"); do
    if kubectl describe nodes | grep -q "nvidia.com/"; then
      log "Detected allocatable NVIDIA resources."
      return 0
    fi
    sleep "${sleep_s}"
  done

  log "No allocatable nvidia.com/* resources detected after ${retries} checks."
  log "Check: nvidia-smi on host, nvidia runtime config, and k8s-device-plugin logs."
  return 1
}

show_gpu_resources() {
  log "Node allocatable NVIDIA resources"
  kubectl describe nodes | grep -n "nvidia.com/" || true
}

main() {
  need_sudo
  ensure_prereqs
  install_k3s_if_needed

  if [[ -f /etc/rancher/k3s/k3s.yaml ]]; then
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  fi

  if ! kubectl cluster-info >/dev/null 2>&1; then
    log "Cluster is still not reachable after k3s setup."
    exit 1
  fi

  configure_nvidia_runtime
  install_device_plugin
  wait_for_gpu_resources
  show_gpu_resources

  log "Done. Kubernetes GPU stack is ready."
}

main "$@"
