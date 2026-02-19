#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-phase1full}
SERVICE=${SERVICE:-infra-${NAMESPACE}-inference-gateway-istio}
PORT=${PORT:-80}
LOCAL_PORT=${LOCAL_PORT:-18083}
MODEL=${MODEL:-tinyllama}
MODE=${MODE:-steady}
DURATION_S=${DURATION_S:-60}
CONCURRENCY=${CONCURRENCY:-16}
STEADY_RPS=${STEADY_RPS:-8}
BURST_RPS=${BURST_RPS:-40}
BURST_AFTER_S=${BURST_AFTER_S:-10}
BURST_FOR_S=${BURST_FOR_S:-10}
LONG_PROMPT_RATIO=${LONG_PROMPT_RATIO:-0.3}
SHORT_USER_TOKENS=${SHORT_USER_TOKENS:-24}
LONG_USER_TOKENS=${LONG_USER_TOKENS:-400}
MAX_TOKENS=${MAX_TOKENS:-32}
TIMEOUT_S=${TIMEOUT_S:-120}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[loadgen] kubectl is required"
  echo "[loadgen] Run: make bootstrap"
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "[loadgen] python3 is required"
  exit 1
fi
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[loadgen] kubectl context/cluster is not reachable"
  echo "[loadgen] Configure kubeconfig, then retry."
  exit 1
fi

kubectl -n "${NAMESPACE}" get svc "${SERVICE}" >/dev/null

echo "[loadgen] Port-forwarding svc/${SERVICE} (${NAMESPACE})..."
kubectl -n "${NAMESPACE}" port-forward svc/"${SERVICE}" "${LOCAL_PORT}:${PORT}" >/tmp/pf-loadgen.log 2>&1 &
PF_PID=$!
cleanup() {
  kill "${PF_PID}" >/dev/null 2>&1 || true
}
trap cleanup EXIT
sleep 2

echo "[loadgen] Running mode=${MODE} duration=${DURATION_S}s concurrency=${CONCURRENCY}"
python3 tools/loadgen/loadgen.py \
  --endpoint "http://127.0.0.1:${LOCAL_PORT}" \
  --model "${MODEL}" \
  --mode "${MODE}" \
  --duration-s "${DURATION_S}" \
  --concurrency "${CONCURRENCY}" \
  --steady-rps "${STEADY_RPS}" \
  --burst-rps "${BURST_RPS}" \
  --burst-after-s "${BURST_AFTER_S}" \
  --burst-for-s "${BURST_FOR_S}" \
  --long-prompt-ratio "${LONG_PROMPT_RATIO}" \
  --short-user-tokens "${SHORT_USER_TOKENS}" \
  --long-user-tokens "${LONG_USER_TOKENS}" \
  --max-tokens "${MAX_TOKENS}" \
  --timeout-s "${TIMEOUT_S}"
