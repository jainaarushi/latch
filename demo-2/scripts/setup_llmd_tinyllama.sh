#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-kubnamespace}"
RELEASE_NAME_POSTFIX="${RELEASE_NAME_POSTFIX:-inference-scheduling}"
MODEL="${MODEL:-TinyLlama/TinyLlama-1.1B-Chat-v1.0}"
MODEL_SIZE="${MODEL_SIZE:-4Gi}"
DECODE_REPLICAS="${DECODE_REPLICAS:-1}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-512}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.30}"
LLMD_DIR="${LLMD_DIR:-$HOME/llm-d}"
DECODE_IMAGE="${DECODE_IMAGE:-}"
DECODE_LD_LIBRARY_PATH="${DECODE_LD_LIBRARY_PATH:-/usr/lib/x86_64-linux-gnu}"
DECODE_LD_PRELOAD="${DECODE_LD_PRELOAD:-/usr/lib/x86_64-linux-gnu/libcuda.so.1}"
ENABLE_GATEWAY_PREREQS="${ENABLE_GATEWAY_PREREQS:-true}"

INFER_GUIDE_DIR="${LLMD_DIR}/guides/inference-scheduling"
GW_PREREQ_DIR="${LLMD_DIR}/guides/prereq/gateway-provider"
MS_VALUES_FILE="${INFER_GUIDE_DIR}/ms-inference-scheduling/values.yaml"
GAIE_VALUES_FILE="${INFER_GUIDE_DIR}/gaie-inference-scheduling/values.yaml"
DECODE_DEPLOY="ms-${RELEASE_NAME_POSTFIX}-llm-d-modelservice-decode"

log() { echo "[llmd-setup] $*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

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
    log "llm-d repo present at $LLMD_DIR"
    return
  fi

  log "Cloning llm-d repo to $LLMD_DIR"
  git clone git@github.com:llm-d/llm-d.git "$LLMD_DIR"
}

prepare_namespace() {
  kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$NAMESPACE" >/dev/null
}

scale_down_direct_vllm() {
  if kubectl -n "$NAMESPACE" get deploy vllm >/dev/null 2>&1; then
    log "Scaling direct vllm deployment to 0 to avoid GPU contention"
    kubectl -n "$NAMESPACE" scale deploy vllm --replicas=0 >/dev/null
  fi
}

install_gateway_prereqs() {
  if [[ "$ENABLE_GATEWAY_PREREQS" != "true" ]]; then
    log "Skipping gateway prereq installation (ENABLE_GATEWAY_PREREQS=false)"
    return
  fi

  log "Installing gateway API/GAIE CRDs and Istio gateway prerequisites"
  (cd "$GW_PREREQ_DIR" && ./install-gateway-provider-dependencies.sh)
  (cd "$GW_PREREQ_DIR" && helmfile apply -f istio.helmfile.yaml)
}

write_values_files() {
  log "Writing TinyLlama values"

  cat > "$MS_VALUES_FILE" <<YAML
multinode: false

modelArtifacts:
  uri: "hf://${MODEL}"
  name: "${MODEL}"
  size: ${MODEL_SIZE}
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
          cpu: "4"
          memory: 16Gi
        requests:
          cpu: "4"
          memory: 16Gi
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

  sed -i 's|enabled: true|enabled: false|g' "$GAIE_VALUES_FILE"
}

deploy_llmd() {
  log "Deploying llm-d inference scheduling stack"
  (cd "$INFER_GUIDE_DIR" && RELEASE_NAME_POSTFIX="$RELEASE_NAME_POSTFIX" helmfile apply -n "$NAMESPACE")
  kubectl apply -f "$INFER_GUIDE_DIR/httproute.yaml" -n "$NAMESPACE" >/dev/null
}

resolve_decode_image() {
  if [[ -n "$DECODE_IMAGE" ]]; then
    return
  fi

  if kubectl -n "$NAMESPACE" get deploy vllm >/dev/null 2>&1; then
    DECODE_IMAGE="$(kubectl -n "$NAMESPACE" get deploy vllm -o jsonpath='{.spec.template.spec.containers[0].image}')"
  else
    DECODE_IMAGE="vllm/vllm-openai:nightly"
  fi
}

patch_decode_runtime() {
  resolve_decode_image

  log "Patching decode deployment for A100 stability"
  kubectl -n "$NAMESPACE" set image "deploy/${DECODE_DEPLOY}" "vllm=${DECODE_IMAGE}" >/dev/null

  kubectl -n "$NAMESPACE" set env "deploy/${DECODE_DEPLOY}" \
    LD_LIBRARY_PATH="${DECODE_LD_LIBRARY_PATH}" \
    LD_PRELOAD="${DECODE_LD_PRELOAD}" \
    VLLM_PORT="8000" >/dev/null

  kubectl -n "$NAMESPACE" patch deploy "${DECODE_DEPLOY}" --type='merge' -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":0,"maxUnavailable":1}},"template":{"spec":{"runtimeClassName":"nvidia","enableServiceLinks":false}}}}' >/dev/null

  kubectl -n "$NAMESPACE" rollout restart "deploy/${DECODE_DEPLOY}" >/dev/null
  kubectl -n "$NAMESPACE" rollout status "deploy/${DECODE_DEPLOY}" --timeout=1800s >/dev/null
}

show_status() {
  log "Current llm-d status"
  kubectl -n "$NAMESPACE" get deploy "${DECODE_DEPLOY}" || true
  kubectl -n "$NAMESPACE" get pods -o wide
  kubectl -n "$NAMESPACE" get svc | grep inference-gateway || true
}

main() {
  need_cmd kubectl
  need_cmd git
  install_helm
  install_helmfile
  install_helm_diff

  ensure_llmd_repo
  prepare_namespace
  scale_down_direct_vllm
  install_gateway_prereqs
  write_values_files
  deploy_llmd
  patch_decode_runtime
  show_status

  log "Complete. Run traffic with: bash scripts/run_llmd_traffic.sh"
}

main "$@"
