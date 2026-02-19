#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-latchverify}
RELEASE_POSTFIX=${RELEASE_POSTFIX:-${NAMESPACE}}
SERVICE=${SERVICE:-infra-${RELEASE_POSTFIX}-inference-gateway-istio}
PORT=${PORT:-80}
LOCAL_PORT=${LOCAL_PORT:-18081}
REQUESTS=${REQUESTS:-20}
MODEL=${MODEL:-tinyllama}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[backend-proof] kubectl is required"
  echo "[backend-proof] Run: make bootstrap"
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "[backend-proof] curl is required"
  exit 1
fi
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[backend-proof] kubectl context/cluster is not reachable"
  echo "[backend-proof] Configure kubeconfig, then retry."
  exit 1
fi

pods=$(kubectl -n "${NAMESPACE}" get pods -l app.kubernetes.io/name=vllm -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
if [[ -z "${pods}" ]]; then
  echo "[backend-proof] No vLLM pods found in namespace ${NAMESPACE}"
  exit 1
fi

metric_count_for_pod() {
  local pod="$1"
  local metrics
  metrics=$(kubectl -n "${NAMESPACE}" get --raw "/api/v1/namespaces/${NAMESPACE}/pods/${pod}:8000/proxy/metrics" 2>/dev/null || true)
  if [[ -z "${metrics}" ]]; then
    echo 0
    return
  fi
  echo "${metrics}" | awk '/^vllm:request_success_total([ {]|$)/ {sum += $NF} END {if (sum == "") sum = 0; print sum + 0}'
}

declare -A before after
for pod in ${pods}; do
  before["${pod}"]=$(metric_count_for_pod "${pod}")
done

echo "[backend-proof] Port-forwarding svc/${SERVICE} (${NAMESPACE})..."
kubectl -n "${NAMESPACE}" port-forward svc/"${SERVICE}" "${LOCAL_PORT}:${PORT}" >/tmp/port-forward-${SERVICE}.log 2>&1 &
PF_PID=$!
cleanup() {
  kill "${PF_PID}" >/dev/null 2>&1 || true
}
trap cleanup EXIT
sleep 2

models=$(curl -sS "http://127.0.0.1:${LOCAL_PORT}/v1/models" || true)
if command -v jq >/dev/null 2>&1; then
  if ! echo "${models}" | jq -e --arg m "${MODEL}" '[.data[]?.id] | index($m) != null' >/dev/null 2>&1; then
    fallback=$(echo "${models}" | jq -r '.data[0].id // empty')
    if [[ -n "${fallback}" ]]; then
      echo "[backend-proof] Model '${MODEL}' not found; using '${fallback}'"
      MODEL="${fallback}"
    fi
  fi
fi

echo "[backend-proof] Sending ${REQUESTS} requests through llm-d (${SERVICE})..."
ok=0
for i in $(seq 1 "${REQUESTS}"); do
  resp=$(curl -sS -X POST "http://127.0.0.1:${LOCAL_PORT}/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    --data "{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"backend proof request ${i}\"}],\"max_tokens\":8,\"temperature\":0}" || true)

  if command -v jq >/dev/null 2>&1; then
    if echo "${resp}" | jq -e '.choices | type == "array" and length > 0' >/dev/null 2>&1; then
      ok=$((ok + 1))
    fi
  else
    if echo "${resp}" | grep -q '"choices"'; then
      ok=$((ok + 1))
    fi
  fi

done

for pod in ${pods}; do
  after["${pod}"]=$(metric_count_for_pod "${pod}")
done

echo "[backend-proof] Successful responses: ${ok}/${REQUESTS}"

touched=0
for pod in ${pods}; do
  b=${before["${pod}"]}
  a=${after["${pod}"]}
  d=$((a - b))
  if (( d > 0 )); then
    touched=$((touched + 1))
  fi
  printf '[backend-proof] pod=%s before=%s after=%s delta=%s\n' "${pod}" "${b}" "${a}" "${d}"
done

if (( ok == 0 )); then
  echo "[backend-proof] FAIL: no successful llm-d responses"
  exit 1
fi
if (( touched == 0 )); then
  echo "[backend-proof] FAIL: no backend pod counter increased"
  exit 1
fi

echo "[backend-proof] PASS: backend pod selection observed via per-pod vLLM counters"
