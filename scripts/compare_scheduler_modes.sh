#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-kubnamespace}
SERVICE=${SERVICE:-infra-${NAMESPACE}-inference-gateway-istio}
PORT=${PORT:-80}
MODEL=${MODEL:-tinyllama}
CONCURRENCY=${CONCURRENCY:-16}
STEADY_RPS=${STEADY_RPS:-10}
DURATION_S=${DURATION_S:-120}
BACKEND_PROOF_REQUESTS=${BACKEND_PROOF_REQUESTS:-240}
TMP_DIR=${TMP_DIR:-/tmp/latch-scheduler-compare}

need_cmd() { command -v "$1" >/dev/null 2>&1; }

for cmd in kubectl jq python3 curl; do
  if ! need_cmd "${cmd}"; then
    echo "[compare] Missing required command: ${cmd}"
    exit 1
  fi
done

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[compare] kubectl context/cluster is not reachable"
  echo "[compare] Configure kubeconfig, then retry."
  exit 1
fi

mkdir -p "${TMP_DIR}"

run_mode() {
  local unique="$1"
  local mode_name="$2"
  local load_out="${TMP_DIR}/load_${mode_name}.out"
  local load_json="${TMP_DIR}/load_${mode_name}.json"
  local proof_out="${TMP_DIR}/proof_${mode_name}.out"
  local state_out="${TMP_DIR}/state_${mode_name}.json"

  echo ""
  echo "[compare] ===== ${mode_name} (UNIQUE_PROMPTS=${unique}) ====="
  NAMESPACE="${NAMESPACE}" SERVICE="${SERVICE}" PORT="${PORT}" MODEL="${MODEL}" \
  MODE=steady DURATION_S="${DURATION_S}" CONCURRENCY="${CONCURRENCY}" \
  STEADY_RPS="${STEADY_RPS}" UNIQUE_PROMPTS="${unique}" \
  ./scripts/run_load.sh > "${load_out}" 2>&1

  if ! awk 'BEGIN{ok=0} /^{/{ok=1} {if(ok) print}' "${load_out}" > "${load_json}"; then
    echo "[compare] Failed to extract load JSON for ${mode_name}"
    cat "${load_out}"
    exit 1
  fi

  NAMESPACE="${NAMESPACE}" SERVICE="${SERVICE}" PORT="${PORT}" MODEL="${MODEL}" \
  REQUESTS="${BACKEND_PROOF_REQUESTS}" CONCURRENCY="${CONCURRENCY}" \
  ./scripts/backend_proof.sh > "${proof_out}" 2>&1

  if ! NAMESPACE="${NAMESPACE}" ./scripts/state.sh > "${state_out}" 2>&1; then
    echo "[compare] WARN: state collection failed for ${mode_name}"
  fi

  local qps errors p95 p99
  qps="$(jq -r '.qps // 0' "${load_json}")"
  errors="$(jq -r '.errors // 0' "${load_json}")"
  p95="$(jq -r '.latency_s.p95 // 0' "${load_json}")"
  p99="$(jq -r '.latency_s.p99 // 0' "${load_json}")"
  echo "[compare] load summary: qps=${qps} errors=${errors} p95=${p95}s p99=${p99}s"

  echo "[compare] backend proof deltas:"
  awk '/\[backend-proof\] pod=/{print "  " $0}' "${proof_out}" || true

  if [[ -s "${state_out}" ]] && jq -e . >/dev/null 2>&1 < "${state_out}"; then
    echo "[compare] state replica qps snapshot:"
    jq -r '.replicas[]? | "  " + .name + " qps=" + ((.qps // 0)|tostring) + " gpu_util=" + ((.gpu_util // 0)|tostring)' "${state_out}" || true
  fi
}

echo "[compare] namespace=${NAMESPACE} service=${SERVICE} model=${MODEL}"
echo "[compare] duration=${DURATION_S}s concurrency=${CONCURRENCY} rps=${STEADY_RPS}"
echo "[compare] output_dir=${TMP_DIR}"

run_mode 0 locality_friendly
run_mode 1 diverse_prompts

echo ""
echo "[compare] Done."
echo "[compare] Inspect raw outputs in: ${TMP_DIR}"
