#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-phase1full}
SERVICE=${SERVICE:-latch-detector}
PORT=${PORT:-8081}
LOCAL_PORT=${LOCAL_PORT:-18091}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[detector] kubectl is required"
  echo "[detector] Run: make bootstrap"
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "[detector] curl is required"
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "[detector] jq is required"
  echo "[detector] Run: make bootstrap"
  exit 1
fi
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[detector] kubectl context/cluster is not reachable"
  echo "[detector] Configure kubeconfig, then retry."
  exit 1
fi

kubectl -n "${NAMESPACE}" get svc "${SERVICE}" >/dev/null

kubectl -n "${NAMESPACE}" port-forward svc/"${SERVICE}" "${LOCAL_PORT}:${PORT}" >/tmp/pf-incidents.log 2>&1 &
PF_PID=$!
cleanup() {
  kill "${PF_PID}" >/dev/null 2>&1 || true
}
trap cleanup EXIT
sleep 2

RESP=$(curl -sS "http://127.0.0.1:${LOCAL_PORT}/incidents")
ACTIVE_COUNT=$(echo "${RESP}" | jq '.active | length')

echo "[detector] Active incidents: ${ACTIVE_COUNT}"

if [[ "${ACTIVE_COUNT}" -gt 0 ]]; then
  echo "${RESP}" | jq -r '.active[] | "- id=\(.id)\n  type=\(.type)\n  severity=\(.severity)\n  started_at=\(.started_at)\n  evidence:\n    qps_skew=\(.evidence.qps_skew)x (threshold=\(.evidence.qps_skew_threshold)x)\n    ttft_p95_increase=+\(.evidence.ttft_p95_increase_pct)% (threshold=+\(.evidence.ttft_p95_increase_pct_threshold)%)\n    ttft_p95_current_ms=\(.evidence.ttft_p95_ms)\n    ttft_p95_baseline_ms=\(.evidence.baseline_ttft_p95_ms)"'
fi
