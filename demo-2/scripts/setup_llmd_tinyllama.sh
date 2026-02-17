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
DECODE_IMAGE="${DECODE_IMAGE:-vllm/vllm-openai:nightly}"
DECODE_LD_LIBRARY_PATH="${DECODE_LD_LIBRARY_PATH:-/lib/x86_64-linux-gnu}"
DECODE_LD_PRELOAD="${DECODE_LD_PRELOAD:-/lib/x86_64-linux-gnu/libcuda.so.1}"

VALUES_FILE="${LLMD_DIR}/guides/inference-scheduling/ms-inference-scheduling/values.yaml"
INFER_GUIDE_DIR="${LLMD_DIR}/guides/inference-scheduling"
DECODE_DEPLOY="ms-${RELEASE_NAME_POSTFIX}-llm-d-modelservice-decode"

log() { echo "[llmd-setup] $*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
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

configure_values() {
  log "Configuring llm-d inference-scheduling values for TinyLlama"
  sed -i "s|^  uri: .*|  uri: \"hf://${MODEL}\"|" "$VALUES_FILE"
  sed -i "s|^  name: .*|  name: \"${MODEL}\"|" "$VALUES_FILE"
  sed -i "s|^  size: .*|  size: ${MODEL_SIZE}|" "$VALUES_FILE"
  sed -i "s|^  replicas: .*|  replicas: ${DECODE_REPLICAS}|" "$VALUES_FILE"
  sed -i "s|--max-model-len=.*|--max-model-len=${MAX_MODEL_LEN}|" "$VALUES_FILE"
  sed -i "s|--gpu-memory-utilization=.*|--gpu-memory-utilization=${GPU_MEMORY_UTILIZATION}|" "$VALUES_FILE"
}

deploy_llmd() {
  log "Deploying llm-d inference scheduling stack"
  cd "$INFER_GUIDE_DIR"
  RELEASE_NAME_POSTFIX="$RELEASE_NAME_POSTFIX" helmfile apply -n "$NAMESPACE"
  kubectl apply -f httproute.yaml -n "$NAMESPACE" >/dev/null
}

patch_decode_runtime() {
  log "Patching decode deployment image/env for A100 CUDA compatibility"
  kubectl -n "$NAMESPACE" set image "deploy/${DECODE_DEPLOY}" "vllm=${DECODE_IMAGE}" >/dev/null
  kubectl -n "$NAMESPACE" set env "deploy/${DECODE_DEPLOY}" \
    LD_LIBRARY_PATH="${DECODE_LD_LIBRARY_PATH}" \
    LD_PRELOAD="${DECODE_LD_PRELOAD}" >/dev/null

  kubectl -n "$NAMESPACE" rollout restart "deploy/${DECODE_DEPLOY}" >/dev/null
  kubectl -n "$NAMESPACE" rollout status "deploy/${DECODE_DEPLOY}" --timeout=1200s >/dev/null
}

show_status() {
  log "Current llm-d status"
  kubectl -n "$NAMESPACE" get deploy "${DECODE_DEPLOY}" || true
  kubectl -n "$NAMESPACE" get pods -o wide
  kubectl -n "$NAMESPACE" get svc | grep inference-gateway || true
}

main() {
  need_cmd kubectl
  need_cmd helmfile
  need_cmd git

  ensure_llmd_repo
  prepare_namespace
  scale_down_direct_vllm
  configure_values
  deploy_llmd
  patch_decode_runtime
  show_status

  log "Complete. Run traffic with: bash scripts/run_llmd_traffic.sh"
}

main "$@"
