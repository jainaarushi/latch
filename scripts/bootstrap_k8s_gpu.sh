#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

MIG_STRATEGY=${MIG_STRATEGY:-single}
INSTALL_K3S=${INSTALL_K3S:-true}
EXPECTED_GPU_RESOURCE_KEY=${EXPECTED_GPU_RESOURCE_KEY:-}
EXPECTED_GPU_RESOURCE_MIN_COUNT=${EXPECTED_GPU_RESOURCE_MIN_COUNT:-3}

log() {
  echo "[bootstrap-k8s-gpu] $*"
}

need_sudo() {
  if ! command -v sudo >/dev/null 2>&1; then
    log "sudo is required"
    exit 1
  fi
}

ensure_kubeconfig_env() {
  if [[ -f /etc/rancher/k3s/k3s.yaml ]]; then
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  fi
}

install_k3s_if_needed() {
  ensure_kubeconfig_env
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
  ensure_kubeconfig_env
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

ensure_standard_cni_paths() {
  # Some fresh k3s environments report CNI not initialized until standard paths exist.
  sudo mkdir -p /etc/cni/net.d /opt/cni/bin
  if [[ -f /var/lib/rancher/k3s/agent/etc/cni/net.d/10-flannel.conflist ]]; then
    sudo cp -f /var/lib/rancher/k3s/agent/etc/cni/net.d/10-flannel.conflist /etc/cni/net.d/10-flannel.conflist
  fi
  for b in bridge bandwidth flannel host-local loopback portmap cni; do
    if [[ -e "/var/lib/rancher/k3s/data/current/bin/${b}" ]]; then
      sudo ln -sf "/var/lib/rancher/k3s/data/current/bin/${b}" "/opt/cni/bin/${b}"
    fi
  done
}

wait_for_node_ready() {
  local node retries=60 sleep_s=5 i
  node=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [[ -z "${node}" ]]; then
    log "No node found while waiting for readiness."
    return 1
  fi

  for i in $(seq 1 "${retries}"); do
    if kubectl get node "${node}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' | grep -q True; then
      return 0
    fi
    sleep "${sleep_s}"
  done

  log "Node ${node} did not become Ready in time."
  return 1
}

label_gpu_present() {
  local node
  node=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [[ -n "${node}" ]]; then
    kubectl label node "${node}" nvidia.com/gpu.present=true --overwrite >/dev/null 2>&1 || true
  fi
}

ensure_prereqs() {
  ./scripts/bootstrap_prereqs.sh
}

install_device_plugin() {
  log "Installing NVIDIA k8s-device-plugin (MIG strategy: ${MIG_STRATEGY})"
  helm repo add nvidia https://nvidia.github.io/k8s-device-plugin >/dev/null 2>&1 || true
  helm repo update >/dev/null

  helm upgrade --install nvdp nvidia/nvidia-device-plugin \
    -n kube-system \
    --set migStrategy="${MIG_STRATEGY}" \
    --set failOnInitError=false \
    --set runtimeClassName=nvidia \
    --set compatWithCPUManager=true \
    --set-json tolerations='[{"operator":"Exists"}]' >/dev/null

  local ds
  ds=$(kubectl -n kube-system get ds -o name | grep -E 'nvidia-device-plugin' | head -n1 || true)
  if [[ -z "${ds}" ]]; then
    log "Failed to find NVIDIA device-plugin DaemonSet after helm install."
    exit 1
  fi
  kubectl -n kube-system rollout status "${ds}" --timeout=5m >/dev/null
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

sum_resource_count() {
  local key="$1"
  kubectl get nodes -o go-template='{{range .items}}{{range $k,$v := .status.allocatable}}{{printf "%s=%s\n" $k $v}}{{end}}{{end}}' \
    | awk -F= -v k="${key}" '$1==k {sum += $2} END {print sum+0}'
}

pick_detected_key() {
  local k
  k=$(kubectl get nodes -o go-template='{{range .items}}{{range $k,$v := .status.allocatable}}{{printf "%s=%s\n" $k $v}}{{end}}{{end}}' \
    | awk -F= '/^nvidia.com\/mig-/ && $2 != "0" {print $1; exit}')
  if [[ -n "${k}" ]]; then
    echo "${k}"
  else
    echo "nvidia.com/gpu"
  fi
}

assert_expected_capacity() {
  local key="${EXPECTED_GPU_RESOURCE_KEY}"
  if [[ -z "${key}" ]]; then
    key=$(pick_detected_key)
  fi

  local count
  count=$(sum_resource_count "${key}")
  log "Capacity check: ${key}=${count} (required >= ${EXPECTED_GPU_RESOURCE_MIN_COUNT})"
  if (( count < EXPECTED_GPU_RESOURCE_MIN_COUNT )); then
    log "Insufficient GPU capacity for target replicas."
    log "Adjust MIG layout or lower EXPECTED_GPU_RESOURCE_MIN_COUNT."
    exit 1
  fi
}

main() {
  need_sudo
  ensure_kubeconfig_env
  ensure_prereqs
  install_k3s_if_needed

  ensure_kubeconfig_env

  if ! kubectl cluster-info >/dev/null 2>&1; then
    log "Cluster is still not reachable after k3s setup."
    exit 1
  fi

  configure_nvidia_runtime
  ensure_standard_cni_paths
  sudo systemctl restart k3s
  wait_for_node_ready
  label_gpu_present
  install_device_plugin
  wait_for_gpu_resources
  assert_expected_capacity
  show_gpu_resources

  log "Done. Kubernetes GPU stack is ready."
}

main "$@"
