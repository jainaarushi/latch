#!/usr/bin/env bash
set -euo pipefail

RUN_APP_SETUP=${RUN_APP_SETUP:-true}
NAMESPACE=${NAMESPACE:-kubnamespace}
RELEASE_POSTFIX=${RELEASE_POSTFIX:-${NAMESPACE}}

log() {
  echo "[bootstrap-from-zero] $*"
}

log "Step 1/4: host GPU bootstrap"
./scripts/bootstrap_gpu_host.sh

log "Step 2/4: Kubernetes GPU bootstrap"
./scripts/bootstrap_k8s_gpu.sh

if [[ "${RUN_APP_SETUP}" == "true" ]]; then
  log "Step 3/4: LATCH stack setup"
  NAMESPACE="${NAMESPACE}" RELEASE_POSTFIX="${RELEASE_POSTFIX}" ./scripts/full_setup.sh

  log "Step 4/4: done"
  log "Try: NAMESPACE=${NAMESPACE} make status"
else
  log "RUN_APP_SETUP=false; skipping LATCH deployment."
fi
