#!/usr/bin/env bash
set -euo pipefail

RUN_APP_SETUP=${RUN_APP_SETUP:-true}
NAMESPACE=${NAMESPACE:-kubnamespace}
RELEASE_POSTFIX=${RELEASE_POSTFIX:-${NAMESPACE}}
REPLICAS=${REPLICAS:-3}
ENABLE_MIG_LAYOUT=${ENABLE_MIG_LAYOUT:-true}

log() {
  echo "[bootstrap-from-zero] $*"
}

log "Step 1/4: host GPU bootstrap"
./scripts/bootstrap_gpu_host.sh

if [[ "${ENABLE_MIG_LAYOUT}" == "true" ]]; then
  log "Step 2/5: apply MIG layout"
  ./scripts/bootstrap_mig_layout.sh
else
  log "Step 2/5: skipping MIG layout (ENABLE_MIG_LAYOUT=false)"
fi

log "Step 3/5: Kubernetes GPU bootstrap"
EXPECTED_GPU_RESOURCE_MIN_COUNT="${REPLICAS}" ./scripts/bootstrap_k8s_gpu.sh

if [[ "${RUN_APP_SETUP}" == "true" ]]; then
  log "Step 4/5: LATCH stack setup"
  NAMESPACE="${NAMESPACE}" RELEASE_POSTFIX="${RELEASE_POSTFIX}" REPLICAS="${REPLICAS}" ./scripts/full_setup.sh

  log "Step 5/5: done"
  log "Try: NAMESPACE=${NAMESPACE} make status"
else
  log "RUN_APP_SETUP=false; skipping LATCH deployment."
fi
