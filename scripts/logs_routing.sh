#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-kubnamespace}
RELEASE_POSTFIX=${RELEASE_POSTFIX:-hello}
FOLLOW=${FOLLOW:-false}
TAIL=${TAIL:-120}

GW_DEPLOY="infra-${RELEASE_POSTFIX}-inference-gateway-istio"
SCHED_DEPLOY="gaie-${RELEASE_POSTFIX}-epp"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required"
  exit 1
fi

if [[ "${FOLLOW}" == "true" ]]; then
  kubectl -n "${NAMESPACE}" logs -f deploy/"${GW_DEPLOY}" --tail="${TAIL}" &
  PID1=$!
  kubectl -n "${NAMESPACE}" logs -f deploy/"${SCHED_DEPLOY}" --tail="${TAIL}" &
  PID2=$!
  kubectl -n "${NAMESPACE}" logs -f -l app.kubernetes.io/name=vllm --tail="${TAIL}" &
  PID3=$!
  wait "${PID1}" "${PID2}" "${PID3}"
else
  echo "== gateway: ${GW_DEPLOY} =="
  kubectl -n "${NAMESPACE}" logs deploy/"${GW_DEPLOY}" --tail="${TAIL}" || true
  echo ""
  echo "== scheduler: ${SCHED_DEPLOY} =="
  kubectl -n "${NAMESPACE}" logs deploy/"${SCHED_DEPLOY}" --tail="${TAIL}" || true
  echo ""
  echo "== vllm pods =="
  kubectl -n "${NAMESPACE}" logs -l app.kubernetes.io/name=vllm --tail="${TAIL}" || true
fi
