#!/usr/bin/env bash
set -euo pipefail

# Deploy llm-d inference scheduling on top of Kubernetes with TinyLlama only.
# Defaults are tuned for a single-node, single-GPU environment.

NAMESPACE="${NAMESPACE:-kubnamespace}"
LLMD_DIR="${LLMD_DIR:-/home/ubuntu/llm-d}"
LLMD_REPO="${LLMD_REPO:-git@github.com:llm-d/llm-d.git}"
MODEL="${MODEL:-TinyLlama/TinyLlama-1.1B-Chat-v1.0}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-512}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.30}"
DECODE_REPLICAS="${DECODE_REPLICAS:-1}"

log() { echo "[llm-d-setup] $*"; }

install_helm() {
  if command -v helm >/dev/null 2>&1; then
    return
  fi
  log "Installing helm"
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
}

install_helmfile() {
  if command -v helmfile >/dev/null 2>&1; then
    return
  fi
  log "Installing helmfile"
  local ver="v1.1.7"
  curl -fsSL -o /tmp/helmfile.tar.gz "https://github.com/helmfile/helmfile/releases/download/${ver}/helmfile_${ver#v}_linux_amd64.tar.gz"
  tar -xzf /tmp/helmfile.tar.gz -C /tmp helmfile
  sudo mv /tmp/helmfile /usr/local/bin/helmfile
  sudo chmod +x /usr/local/bin/helmfile
}

install_helm_diff() {
  if helm plugin list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx diff; then
    return
  fi
  log "Installing helm-diff plugin"
  helm plugin install https://github.com/databus23/helm-diff
}

ensure_llmd_repo() {
  if [[ -d "$LLMD_DIR/.git" ]]; then
    log "Updating existing llm-d repo"
    git -C "$LLMD_DIR" fetch --all --prune
    git -C "$LLMD_DIR" pull --ff-only || true
    return
  fi
  log "Cloning llm-d repo"
  git clone "$LLMD_REPO" "$LLMD_DIR"
}

apply_tiny_values() {
  local guide_dir="$LLMD_DIR/guides/inference-scheduling"

  cat > "$guide_dir/gaie-inference-scheduling/values.yaml" <<'YAML'
inferenceExtension:
  replicas: 1
  flags:
    kv-cache-usage-percentage-metric: "vllm:kv_cache_usage_perc"
  image:
    name: llm-d-inference-scheduler
    hub: ghcr.io/llm-d
    tag: v0.5.0
    pullPolicy: Always
  extProcPort: 9002
  pluginsConfigFile: "default-plugins.yaml"
  monitoring:
    interval: "10s"
    secret:
      name: inference-scheduling-gateway-sa-metrics-reader-secret
    prometheus:
      enabled: false
      auth:
        enabled: false
inferencePool:
  targetPorts:
    - number: 8000
  modelServerType: vllm
  modelServers:
    matchLabels:
      llm-d.ai/inference-serving: "true"
      llm-d.ai/guide: "inference-scheduling"
YAML

  cat > "$guide_dir/ms-inference-scheduling/values.yaml" <<YAML
multinode: false

modelArtifacts:
  uri: "hf://${MODEL}"
  name: "${MODEL}"
  size: 4Gi
  authSecretName: ""
  labels:
    llm-d.ai/inference-serving: "true"
    llm-d.ai/guide: "inference-scheduling"
    llm-d.ai/accelerator-variant: "gpu"
    llm-d.ai/accelerator-vendor: "nvidia"
    llm-d.ai/model: "TinyLlama-1.1B-Chat-v1.0"

routing:
  proxy:
    enabled: false
    targetPort: 8000

accelerator:
  type: nvidia

decode:
  create: true
  parallelism:
    tensor: 1
    data: 1
  replicas: ${DECODE_REPLICAS}
  monitoring:
    podmonitor:
      enabled: false
  containers:
    - name: "vllm"
      image: ghcr.io/llm-d/llm-d-cuda:v0.5.0
      modelCommand: vllmServe
      args:
        - "--disable-uvicorn-access-log"
        - "--gpu-memory-utilization=${GPU_MEMORY_UTILIZATION}"
        - "--max-model-len=${MAX_MODEL_LEN}"
        - "--enforce-eager"
      ports:
        - containerPort: 8000
          name: vllm
          protocol: TCP
      resources:
        limits:
          cpu: '4'
          memory: 16Gi
        requests:
          cpu: '2'
          memory: 8Gi
      mountModelVolume: true
      volumeMounts:
        - name: metrics-volume
          mountPath: /.config
        - name: shm
          mountPath: /dev/shm
        - name: torch-compile-cache
          mountPath: /.cache
      startupProbe:
        httpGet:
          path: /v1/models
          port: vllm
        initialDelaySeconds: 15
        periodSeconds: 30
        timeoutSeconds: 5
        failureThreshold: 60
      livenessProbe:
        httpGet:
          path: /health
          port: vllm
        periodSeconds: 10
        timeoutSeconds: 5
        failureThreshold: 3
      readinessProbe:
        httpGet:
          path: /v1/models
          port: vllm
        periodSeconds: 5
        timeoutSeconds: 2
        failureThreshold: 3
  volumes:
    - name: metrics-volume
      emptyDir: {}
    - name: torch-compile-cache
      emptyDir: {}
    - name: shm
      emptyDir:
        medium: Memory
        sizeLimit: 4Gi

prefill:
  create: false
YAML
}

main() {
  install_helm
  install_helmfile
  install_helm_diff
  ensure_llmd_repo

  # Free GPU for llm-d decode pod.
  kubectl -n "$NAMESPACE" scale deploy/vllm --replicas=0 >/dev/null 2>&1 || true
  pkill -f '/home/ubuntu/vllm-venv/bin/vllm serve' || true

  local gw_dir="$LLMD_DIR/guides/prereq/gateway-provider"
  local sched_dir="$LLMD_DIR/guides/inference-scheduling"

  log "Installing gateway provider dependencies"
  (cd "$gw_dir" && ./install-gateway-provider-dependencies.sh)

  log "Installing Istio gateway provider"
  (cd "$gw_dir" && helmfile apply -f istio.helmfile.yaml)

  log "Applying TinyLlama llm-d values"
  apply_tiny_values

  log "Deploying llm-d inference scheduling stack"
  (cd "$sched_dir" && helmfile apply -n "$NAMESPACE")

  log "Applying HTTPRoute"
  (cd "$sched_dir" && kubectl apply -f httproute.yaml -n "$NAMESPACE")

  log "Patching decode deployment for k3s+nvidia runtime and env safety"
  kubectl -n "$NAMESPACE" patch deploy ms-inference-scheduling-llm-d-modelservice-decode \
    --type='merge' -p '{"spec":{"template":{"spec":{"runtimeClassName":"nvidia","enableServiceLinks":false}}}}' >/dev/null
  kubectl -n "$NAMESPACE" set env deploy/ms-inference-scheduling-llm-d-modelservice-decode VLLM_PORT=8000 >/dev/null

  # Single-GPU cleanup: avoid surge pods staying pending.
  kubectl -n "$NAMESPACE" scale deploy/ms-inference-scheduling-llm-d-modelservice-decode --replicas=0 >/dev/null
  kubectl -n "$NAMESPACE" rollout status deploy/ms-inference-scheduling-llm-d-modelservice-decode --timeout=300s
  kubectl -n "$NAMESPACE" scale deploy/ms-inference-scheduling-llm-d-modelservice-decode --replicas="$DECODE_REPLICAS" >/dev/null

  log "Waiting for core llm-d components"
  kubectl -n "$NAMESPACE" rollout status deploy/infra-inference-scheduling-inference-gateway-istio --timeout=600s
  kubectl -n "$NAMESPACE" rollout status deploy/gaie-inference-scheduling-epp --timeout=600s
  kubectl -n "$NAMESPACE" rollout status deploy/ms-inference-scheduling-llm-d-modelservice-decode --timeout=1200s

  log "Done. Current status:"
  kubectl -n "$NAMESPACE" get deploy
  kubectl -n "$NAMESPACE" get pods -o wide

  log "Gateway URI: http://infra-inference-scheduling-inference-gateway-istio.${NAMESPACE}.svc.cluster.local"
}

main "$@"
