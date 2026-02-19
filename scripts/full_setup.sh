#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-kubnamespace}
RELEASE_POSTFIX=${RELEASE_POSTFIX:-${NAMESPACE}}

log() {
  echo "[setup] $*"
}

log "Phase 0: bootstrap prerequisites"
./scripts/bootstrap_prereqs.sh

log "Phase 0: cluster preflight"
./scripts/doctor.sh

log "Phase 1: deploy vLLM"
./scripts/up.sh

log "Phase 1: direct infer smoke test"
./scripts/test_infer.sh

log "Phase 1: deploy llm-d"
./scripts/up_llmd.sh

log "Phase 1: infer smoke test via llm-d"
SERVICE=${SERVICE:-infra-${RELEASE_POSTFIX}-inference-gateway-istio} PORT=${PORT:-80} ./scripts/test_infer.sh

log "Complete. Namespace=${NAMESPACE}"
