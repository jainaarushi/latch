#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-phase1full}
SERVICE=${SERVICE:-latch-metrics}
PORT=${PORT:-8080}
LOCAL_PORT=${LOCAL_PORT:-18090}
INTERVAL_S=${INTERVAL_S:-2}
DURATION_S=${DURATION_S:-60}
OUT_PATH=${OUT_PATH:-/tmp/state_live_${NAMESPACE}_$(date -u +%Y%m%dT%H%M%SZ).jsonl}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[state-live] kubectl is required"
  echo "[state-live] Run: make bootstrap"
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "[state-live] curl is required"
  exit 1
fi
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[state-live] kubectl context/cluster is not reachable"
  echo "[state-live] Configure kubeconfig, then retry."
  exit 1
fi

kubectl -n "${NAMESPACE}" get svc "${SERVICE}" >/dev/null

mkdir -p "$(dirname "${OUT_PATH}")"
: > "${OUT_PATH}"

kubectl -n "${NAMESPACE}" port-forward svc/"${SERVICE}" "${LOCAL_PORT}:${PORT}" >/tmp/pf-state-live.log 2>&1 &
PF_PID=$!
cleanup() {
  kill "${PF_PID}" >/dev/null 2>&1 || true
}
trap cleanup EXIT
sleep 2

echo "[state-live] namespace=${NAMESPACE} service=${SERVICE} duration=${DURATION_S}s interval=${INTERVAL_S}s"
echo "[state-live] writing jsonl to ${OUT_PATH}"

start_ts=$(date +%s)
samples=0
while :; do
  now_ts=$(date +%s)
  elapsed=$((now_ts - start_ts))
  if (( elapsed >= DURATION_S )); then
    break
  fi

  if line=$(curl -fsS "http://127.0.0.1:${LOCAL_PORT}/state" 2>/dev/null); then
    echo "${line}" >> "${OUT_PATH}"
    samples=$((samples + 1))
  else
    echo "[state-live] WARN: failed to fetch /state at t=${elapsed}s" >&2
  fi

  sleep "${INTERVAL_S}"
done

echo "[state-live] done. samples=${samples} out=${OUT_PATH}"
