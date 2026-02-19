#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-kubnamespace}
SERVICE=${SERVICE:-vllm}
PORT=${PORT:-8000}
LOCAL_PORT=${LOCAL_PORT:-18080}
SERVED_MODEL_NAME=${SERVED_MODEL_NAME:-tinyllama}
MODEL=${MODEL:-${SERVED_MODEL_NAME}}
MODEL_WAIT_RETRIES=${MODEL_WAIT_RETRIES:-30}
MODEL_WAIT_INTERVAL_S=${MODEL_WAIT_INTERVAL_S:-2}
COMPLETION_RETRIES=${COMPLETION_RETRIES:-30}
COMPLETION_WAIT_INTERVAL_S=${COMPLETION_WAIT_INTERVAL_S:-2}

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

MODELS=""
MODEL_FOUND="no"
for _ in $(seq 1 "${MODEL_WAIT_RETRIES}"); do
  MODELS=$(curl -sS "http://127.0.0.1:${LOCAL_PORT}/v1/models" || true)
  if command -v jq >/dev/null 2>&1; then
    MODEL_FOUND=$(echo "${MODELS}" | jq -e --arg m "${MODEL}" '[.data[]?.id] | index($m) != null' >/dev/null && echo yes || echo no)
  else
    MODEL_FOUND=$(echo "${MODELS}" | grep -Fq "\"${MODEL}\"" && echo yes || echo no)
  fi
  if [[ "${MODEL_FOUND}" == "yes" ]]; then
    break
  fi
  sleep "${MODEL_WAIT_INTERVAL_S}"
done

if [[ "${MODEL_FOUND}" != "yes" ]]; then
  if command -v jq >/dev/null 2>&1; then
    FALLBACK_MODEL=$(echo "${MODELS}" | jq -r '.data[0].id // empty')
    if [[ -n "${FALLBACK_MODEL}" ]]; then
      echo "Model '${MODEL}' not found; using gateway model '${FALLBACK_MODEL}' instead."
      MODEL="${FALLBACK_MODEL}"
    else
      echo "Model '${MODEL}' was not found in /v1/models after ${MODEL_WAIT_RETRIES} retries; proceeding with original model id."
    fi
  else
    echo "Model '${MODEL}' was not found in /v1/models after ${MODEL_WAIT_RETRIES} retries; proceeding with original model id."
  fi
fi

RESP=""
HAS_CHOICES="no"
for _ in $(seq 1 "${COMPLETION_RETRIES}"); do
  RESP=$(curl -sS -X POST "http://127.0.0.1:${LOCAL_PORT}/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    --data "{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"say hello in 5 words\"}],\"max_tokens\":16,\"temperature\":0}" || true)

  if command -v jq >/dev/null 2>&1; then
    HAS_CHOICES=$(echo "${RESP}" | jq -e '.choices | type == "array" and length > 0' >/dev/null 2>&1 && echo yes || echo no)
  else
    HAS_CHOICES=$(echo "${RESP}" | grep -Fq '"choices"' && echo yes || echo no)
  fi
  if [[ "${HAS_CHOICES}" == "yes" ]]; then
    break
  fi
  sleep "${COMPLETION_WAIT_INTERVAL_S}"
done

echo "${RESP}" | (command -v jq >/dev/null && jq . || cat)

if [[ "${HAS_CHOICES}" == "yes" ]]; then
  echo ""
  echo "PASS: valid OpenAI-style response returned from ${SERVICE}."
else
  echo ""
  echo "FAIL: response missing choices field after ${COMPLETION_RETRIES} retries"
  exit 1
fi
