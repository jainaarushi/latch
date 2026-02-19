#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-phase1full}
OBS_NAMESPACE=${OBS_NAMESPACE:-observability}
PROM_SERVICE=${PROM_SERVICE:-prometheus}
LOCAL_PORT=${LOCAL_PORT:-19090}
INTERVAL_S=${INTERVAL_S:-5}
ITERATIONS=${ITERATIONS:-0}

need_cmd() { command -v "$1" >/dev/null 2>&1; }

if ! need_cmd kubectl; then
  echo "[metrics-live] kubectl is required"
  echo "[metrics-live] Run: make bootstrap"
  exit 1
fi
if ! need_cmd curl || ! need_cmd jq; then
  echo "[metrics-live] curl and jq are required"
  echo "[metrics-live] Run: make bootstrap"
  exit 1
fi
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[metrics-live] kubectl context/cluster is not reachable"
  echo "[metrics-live] Configure kubeconfig, then retry."
  exit 1
fi

kubectl -n "${OBS_NAMESPACE}" get svc "${PROM_SERVICE}" >/dev/null 2>&1 || {
  echo "[metrics-live] Prometheus service ${PROM_SERVICE} not found in ${OBS_NAMESPACE}"
  exit 1
}

kubectl -n "${NAMESPACE}" get pods -l app.kubernetes.io/name=vllm >/dev/null 2>&1 || {
  echo "[metrics-live] No vLLM pods found in namespace ${NAMESPACE}"
  exit 1
}

kubectl -n "${OBS_NAMESPACE}" port-forward svc/"${PROM_SERVICE}" "${LOCAL_PORT}:9090" >/tmp/pf-prometheus.log 2>&1 &
PF_PID=$!
cleanup() {
  kill "${PF_PID}" >/dev/null 2>&1 || true
}
trap cleanup EXIT
sleep 2

prom_query() {
  local q="$1"
  curl -sS --get "http://127.0.0.1:${LOCAL_PORT}/api/v1/query" --data-urlencode "query=${q}" | jq -r '.data.result[]? | [.metric.pod, .value[1]] | @tsv'
}

fill_map() {
  local map_name="$1"
  local query="$2"
  declare -n map_ref="${map_name}"
  map_ref=()
  while IFS=$'\t' read -r pod value; do
    [[ -n "${pod}" ]] || continue
    map_ref["${pod}"]="${value}"
  done < <(prom_query "${query}")
}

fmt() {
  local v="${1:-}"
  local p="${2:-2}"
  if [[ -z "${v}" ]]; then
    printf "-"
  else
    printf "%.*f" "${p}" "${v}"
  fi
}

print_snapshot() {
  local pods
  pods=$(kubectl -n "${NAMESPACE}" get pods -l app.kubernetes.io/name=vllm -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sort)

  declare -A req_rate running waiting ttft_p95 e2e_p95 prompt_tps gen_tps gpu_mem gpu_util

  fill_map req_rate "sum by (pod) (rate(vllm:request_success_total{namespace=\"${NAMESPACE}\"}[1m]))"
  fill_map running "max by (pod) (vllm:num_requests_running{namespace=\"${NAMESPACE}\"})"
  fill_map waiting "max by (pod) (vllm:num_requests_waiting{namespace=\"${NAMESPACE}\"})"
  fill_map ttft_p95 "histogram_quantile(0.95, sum by (le,pod) (rate(vllm:time_to_first_token_seconds_bucket{namespace=\"${NAMESPACE}\"}[5m])))"
  fill_map e2e_p95 "histogram_quantile(0.95, sum by (le,pod) (rate(vllm:e2e_request_latency_seconds_bucket{namespace=\"${NAMESPACE}\"}[5m])))"
  fill_map prompt_tps "sum by (pod) (rate(vllm:prompt_tokens_total{namespace=\"${NAMESPACE}\"}[1m]))"
  fill_map gen_tps "sum by (pod) (rate(vllm:generation_tokens_total{namespace=\"${NAMESPACE}\"}[1m]))"
  fill_map gpu_mem "avg by (pod) (DCGM_FI_DEV_FB_USED{namespace=\"${NAMESPACE}\"}) or label_replace(avg by (exported_pod) (DCGM_FI_DEV_FB_USED{exported_namespace=\"${NAMESPACE}\"}), \"pod\", \"\$1\", \"exported_pod\", \"(.*)\")"

  # Prefer explicit util when available; otherwise use MIG-safe GR engine active ratio.
  fill_map gpu_util "avg by (pod) (DCGM_FI_DEV_GPU_UTIL{namespace=\"${NAMESPACE}\"}) or label_replace(avg by (exported_pod) (DCGM_FI_DEV_GPU_UTIL{exported_namespace=\"${NAMESPACE}\"}), \"pod\", \"\$1\", \"exported_pod\", \"(.*)\")"
  if [[ ${#gpu_util[@]} -eq 0 ]]; then
    fill_map gpu_util "100 * (avg by (pod) (DCGM_FI_PROF_GR_ENGINE_ACTIVE{namespace=\"${NAMESPACE}\"}) or label_replace(avg by (exported_pod) (DCGM_FI_PROF_GR_ENGINE_ACTIVE{exported_namespace=\"${NAMESPACE}\"}), \"pod\", \"\$1\", \"exported_pod\", \"(.*)\"))"
  fi

  echo ""
  echo "[metrics-live] $(date -u +'%Y-%m-%dT%H:%M:%SZ') namespace=${NAMESPACE}"
  printf "%-34s %7s %7s %7s %9s %9s %10s %10s %10s %9s\n" \
    "POD" "req/s" "run" "wait" "ttft_p95" "lat_p95" "prompt_t/s" "gen_t/s" "gpu_memMB" "gpu_util%"

  while IFS= read -r pod; do
    [[ -n "${pod}" ]] || continue
    printf "%-34s %7s %7s %7s %9s %9s %10s %10s %10s %9s\n" \
      "${pod}" \
      "$(fmt "${req_rate[${pod}]-}" 2)" \
      "$(fmt "${running[${pod}]-}" 0)" \
      "$(fmt "${waiting[${pod}]-}" 0)" \
      "$(fmt "${ttft_p95[${pod}]-}" 3)" \
      "$(fmt "${e2e_p95[${pod}]-}" 3)" \
      "$(fmt "${prompt_tps[${pod}]-}" 2)" \
      "$(fmt "${gen_tps[${pod}]-}" 2)" \
      "$(fmt "${gpu_mem[${pod}]-}" 0)" \
      "$(fmt "${gpu_util[${pod}]-}" 1)"
  done <<< "${pods}"
}

count=0
while :; do
  print_snapshot
  count=$((count + 1))
  if [[ "${ITERATIONS}" != "0" ]] && (( count >= ITERATIONS )); then
    break
  fi
  sleep "${INTERVAL_S}"
done
