#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-kubnamespace}
SERVICE=${SERVICE:-vllm}
PORT=${PORT:-8000}
LOCAL_PORT=${LOCAL_PORT:-18080}
SERVED_MODEL_NAME=${SERVED_MODEL_NAME:-tinyllama}
MODEL=${MODEL:-${SERVED_MODEL_NAME}}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required"
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required"
  exit 1
fi

kubectl -n "${NAMESPACE}" get svc "${SERVICE}" >/dev/null

kubectl -n "${NAMESPACE}" port-forward svc/"${SERVICE}" "${LOCAL_PORT}:${PORT}" >/tmp/port-forward-${SERVICE}.log 2>&1 &
PF_PID=$!
cleanup() {
  kill "${PF_PID}" >/dev/null 2>&1 || true
}
trap cleanup EXIT
sleep 3

MODELS=$(curl -sS "http://127.0.0.1:${LOCAL_PORT}/v1/models")
if ! echo "${MODELS}" | rg -q "\"${MODEL}\""; then
  echo "Model '${MODEL}' was not found in /v1/models response:"
  echo "${MODELS}" | (command -v jq >/dev/null && jq . || cat)
  exit 1
fi

RESP=$(curl -sS -X POST "http://127.0.0.1:${LOCAL_PORT}/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  --data "{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"say hello in 5 words\"}],\"max_tokens\":16,\"temperature\":0}")

echo "${RESP}" | (command -v jq >/dev/null && jq . || cat)

if echo "${RESP}" | rg -q '"choices"'; then
  echo ""
  echo "PASS: valid OpenAI-style response returned from ${SERVICE}."
else
  echo ""
  echo "FAIL: response missing choices field"
  exit 1
fi
