#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-kubnamespace}"
MODEL="${MODEL:-TinyLlama/TinyLlama-1.1B-Chat-v1.0}"
REPLICAS="${REPLICAS:-1}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-512}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.20}"
K3S_CHANNEL="${K3S_CHANNEL:-stable}"
KILL_LOCAL_VLLM="${KILL_LOCAL_VLLM:-false}"
LOCAL_VLLM_KILL_PATTERN="${LOCAL_VLLM_KILL_PATTERN:-vllm serve}"
VLLM_IMAGE="${VLLM_IMAGE:-vllm/vllm-openai:nightly}"
VLLM_LD_LIBRARY_PATH="${VLLM_LD_LIBRARY_PATH:-/lib/x86_64-linux-gnu}"
VLLM_LD_PRELOAD="${VLLM_LD_PRELOAD:-/lib/x86_64-linux-gnu/libcuda.so.1}"

log() { echo "[setup] $*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

install_kubectl() {
  if command -v kubectl >/dev/null 2>&1; then
    log "kubectl already installed"
    return
  fi

  log "Installing kubectl via snap"
  if ! command -v snap >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y snapd
  fi
  sudo snap install kubectl --classic
}

ensure_nvidia_driver() {
  if nvidia-smi >/dev/null 2>&1; then
    log "NVIDIA driver already working"
    return
  fi

  log "Installing NVIDIA driver via ubuntu-drivers"
  sudo apt-get update
  sudo apt-get install -y ubuntu-drivers-common
  sudo ubuntu-drivers autoinstall

  if ! nvidia-smi >/dev/null 2>&1; then
    echo "nvidia-smi still unavailable. Reboot required after driver install. Run: sudo reboot" >&2
    exit 2
  fi
}

install_k3s() {
  if command -v k3s >/dev/null 2>&1 && systemctl is-active --quiet k3s; then
    log "k3s already installed and active"
  else
    log "Installing k3s"
    curl -sfL https://get.k3s.io | sudo INSTALL_K3S_CHANNEL="$K3S_CHANNEL" sh -
  fi

  mkdir -p "$HOME/.kube"
  sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
  sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
  sudo chmod 600 "$HOME/.kube/config"

  local server_ip
  server_ip="$(hostname -I | awk '{print $1}')"
  sed -i "s/127.0.0.1/${server_ip}/" "$HOME/.kube/config"
}

install_nvidia_container_toolkit() {
  if command -v nvidia-ctk >/dev/null 2>&1; then
    log "nvidia-container-toolkit already installed"
  else
    log "Installing nvidia-container-toolkit"
    sudo apt-get update
    sudo apt-get install -y curl ca-certificates gnupg
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
      | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
      | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
      | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
    sudo apt-get update
    sudo apt-get install -y nvidia-container-toolkit
  fi

  log "Configuring nvidia-container-toolkit for containerd"
  if [[ -f /var/lib/rancher/k3s/agent/etc/containerd/config.toml ]]; then
    sudo nvidia-ctk runtime configure --runtime=containerd --config=/var/lib/rancher/k3s/agent/etc/containerd/config.toml
  else
    sudo nvidia-ctk runtime configure --runtime=containerd
  fi

  log "Restarting k3s"
  sudo systemctl restart k3s
}

install_device_plugin() {
  log "Applying NVIDIA device plugin"
  kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.17.4/deployments/static/nvidia-device-plugin.yml >/dev/null

  kubectl -n kube-system patch ds nvidia-device-plugin-daemonset \
    --type='json' \
    -p='[{"op":"add","path":"/spec/template/spec/runtimeClassName","value":"nvidia"}]' >/dev/null || true

  kubectl -n kube-system rollout status ds/nvidia-device-plugin-daemonset --timeout=180s >/dev/null

  log "Waiting for nvidia.com/gpu to appear on node allocatable"
  local i
  for i in $(seq 1 45); do
    if kubectl get node -o json | grep -q '"nvidia.com/gpu"'; then
      log "GPU resource registered"
      return
    fi
    sleep 2
  done

  echo "Timed out waiting for nvidia.com/gpu resource registration" >&2
  kubectl -n kube-system logs ds/nvidia-device-plugin-daemonset --tail=100 || true
  exit 3
}

cleanup_old_vllm() {
  if [[ "$KILL_LOCAL_VLLM" != "true" ]]; then
    log "Skipping local vLLM process cleanup (KILL_LOCAL_VLLM=false)"
    return
  fi

  log "Stopping local vLLM process(es) matching pattern: $LOCAL_VLLM_KILL_PATTERN"
  pkill -f "$LOCAL_VLLM_KILL_PATTERN" || true
}

deploy_vllm() {
  log "Deploying vLLM to namespace: $NAMESPACE"
  cat >/tmp/vllm-kubnamespace.yaml <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm
  namespace: ${NAMESPACE}
spec:
  replicas: ${REPLICAS}
  selector:
    matchLabels:
      app: vllm
  template:
    metadata:
      labels:
        app: vllm
    spec:
      enableServiceLinks: false
      runtimeClassName: nvidia
      containers:
      - name: vllm
        image: ${VLLM_IMAGE}
        imagePullPolicy: IfNotPresent
        args:
        - --model
        - ${MODEL}
        - --host
        - 0.0.0.0
        - --port
        - "8000"
        - --dtype
        - float16
        - --max-model-len
        - "${MAX_MODEL_LEN}"
        - --gpu-memory-utilization
        - "${GPU_MEMORY_UTILIZATION}"
        - --enforce-eager
        env:
        - name: HF_HOME
          value: /cache/hf
        - name: VLLM_LOGGING_LEVEL
          value: INFO
        - name: VLLM_PORT
          value: "8000"
        - name: LD_LIBRARY_PATH
          value: "${VLLM_LD_LIBRARY_PATH}"
        - name: LD_PRELOAD
          value: "${VLLM_LD_PRELOAD}"
        ports:
        - containerPort: 8000
          name: http
        readinessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 20
          periodSeconds: 10
          timeoutSeconds: 5
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 60
          periodSeconds: 20
          timeoutSeconds: 5
        resources:
          requests:
            cpu: "2"
            memory: "6Gi"
            nvidia.com/gpu: "1"
          limits:
            cpu: "4"
            memory: "10Gi"
            nvidia.com/gpu: "1"
        volumeMounts:
        - name: hf-cache
          mountPath: /cache/hf
        - name: dshm
          mountPath: /dev/shm
      volumes:
      - name: hf-cache
        hostPath:
          path: /var/lib/rancher/vllm-cache
          type: DirectoryOrCreate
      - name: dshm
        emptyDir:
          medium: Memory
          sizeLimit: 1Gi
---
apiVersion: v1
kind: Service
metadata:
  name: vllm
  namespace: ${NAMESPACE}
spec:
  selector:
    app: vllm
  ports:
  - name: http
    port: 8000
    targetPort: 8000
YAML

  kubectl apply -f /tmp/vllm-kubnamespace.yaml >/dev/null

  log "Waiting for vLLM rollout"
  kubectl -n "$NAMESPACE" rollout status deploy/vllm --timeout=900s

  log "Deployment status"
  kubectl -n "$NAMESPACE" get deploy vllm
  kubectl -n "$NAMESPACE" get pods -o wide
  kubectl -n "$NAMESPACE" get endpoints vllm
}

main() {
  need_cmd curl
  need_cmd sudo
  install_kubectl
  ensure_nvidia_driver
  install_k3s
  install_nvidia_container_toolkit
  install_device_plugin
  cleanup_old_vllm
  deploy_vllm

  log "Complete. Namespace in use: $NAMESPACE"
}

main "$@"
