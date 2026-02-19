#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-phase1full}
INC=${INC:-}
SERVICE=${SERVICE:-latch-diagnoser}
PORT=${PORT:-8082}
LOCAL_PORT=${LOCAL_PORT:-18092}

if [[ -z "${INC}" ]]; then
  echo "[diagnosis] INC is required"
  echo "[diagnosis] Example: NAMESPACE=${NAMESPACE} make diagnose INC=inc_0241"
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[diagnosis] kubectl is required"
  echo "[diagnosis] Run: make bootstrap"
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "[diagnosis] curl is required"
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "[diagnosis] jq is required"
  echo "[diagnosis] Run: make bootstrap"
  exit 1
fi
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[diagnosis] kubectl context/cluster is not reachable"
  echo "[diagnosis] Configure kubeconfig, then retry."
  exit 1
fi

kubectl -n "${NAMESPACE}" get svc "${SERVICE}" >/dev/null

kubectl -n "${NAMESPACE}" port-forward svc/"${SERVICE}" "${LOCAL_PORT}:${PORT}" >/tmp/pf-diagnose.log 2>&1 &
PF_PID=$!
cleanup() {
  kill "${PF_PID}" >/dev/null 2>&1 || true
}
trap cleanup EXIT
sleep 2

RESP=$(curl -fsS "http://127.0.0.1:${LOCAL_PORT}/incidents/${INC}/diagnosis")

echo "[diagnosis] Incident $(echo "${RESP}" | jq -r '.incident_id')"
echo "Diagnosis mode: $(echo "${RESP}" | jq -r '.diagnosis_mode // \"deterministic\"')"
echo "Narrative mode: $(echo "${RESP}" | jq -r '.narrative_mode // \"deterministic\"')"
echo "Root cause: $(echo "${RESP}" | jq -r '.root_cause')"
echo "Confidence: $(echo "${RESP}" | jq -r '.confidence')"
echo

echo "Evidence:"
echo "${RESP}" | jq -r '.evidence[] | "- " + .'
echo

echo "Recommendation:"
echo "- $(echo "${RESP}" | jq -r '.recommendation')"
echo "Risk: $(echo "${RESP}" | jq -r '.risk')"
echo "Rollback: $(echo "${RESP}" | jq -r '.rollback')"
echo

echo "Next checks:"
echo "${RESP}" | jq -r '.next_checks[]? | "- " + .'
echo

echo "Sources:"
echo "${RESP}" | jq -r '.sources[]? | "- " + .'
