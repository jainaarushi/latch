#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-kubnamespace}
RELEASE_POSTFIX=${RELEASE_POSTFIX:-${NAMESPACE}}
SERVICE=${SERVICE:-infra-${RELEASE_POSTFIX}-inference-gateway-istio}
PORT=${PORT:-80}
MODEL=${MODEL:-tinyllama}
VLLM_MODEL_ID=${VLLM_MODEL_ID:-TinyLlama/TinyLlama-1.1B-Chat-v1.0}
SERVED_MODEL_NAME=${SERVED_MODEL_NAME:-tinyllama}
CONCURRENCY=${CONCURRENCY:-10}
STEADY_RPS=${STEADY_RPS:-8}
BASELINE_DURATION_S=${BASELINE_DURATION_S:-20}
INCIDENT_DURATION_S=${INCIDENT_DURATION_S:-45}
RECOVERY_DURATION_S=${RECOVERY_DURATION_S:-20}
STATE_INTERVAL_S=${STATE_INTERVAL_S:-2}
OUT_DIR=${OUT_DIR:-/tmp/latch-run-demo}
DEMO_VLLM_REPLICAS=${DEMO_VLLM_REPLICAS:-2}

need_cmd() { command -v "$1" >/dev/null 2>&1; }
for cmd in kubectl curl jq python3; do
  if ! need_cmd "${cmd}"; then
    echo "[run-demo] Missing required command: ${cmd}"
    exit 1
  fi
done
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[run-demo] kubectl context/cluster is not reachable"
  exit 1
fi

mkdir -p "${OUT_DIR}"

echo "[run-demo] Step 1/8 deploy stack"
if ! kubectl -n "${NAMESPACE}" get svc vllm >/dev/null 2>&1; then
  NAMESPACE="${NAMESPACE}" MODEL="${VLLM_MODEL_ID}" SERVED_MODEL_NAME="${SERVED_MODEL_NAME}" REPLICAS=1 ./scripts/up.sh
else
  echo "[run-demo] vLLM service exists, skipping up.sh"
fi
if ! kubectl -n "${NAMESPACE}" get svc "infra-${RELEASE_POSTFIX}-inference-gateway-istio" >/dev/null 2>&1; then
  NAMESPACE="${NAMESPACE}" RELEASE_POSTFIX="${RELEASE_POSTFIX}" ./scripts/up_llmd.sh
else
  echo "[run-demo] llm-d gateway service exists, skipping up_llmd.sh"
fi
kubectl -n observability get svc prometheus >/dev/null 2>&1 || kubectl apply -f deploy/observability/prometheus.yaml >/dev/null
kubectl -n kube-system get svc dcgm-exporter >/dev/null 2>&1 || kubectl apply -f deploy/observability/dcgm-exporter.yaml >/dev/null
NAMESPACE="${NAMESPACE}" ./scripts/up_latch_metrics.sh
NAMESPACE="${NAMESPACE}" ./scripts/up_latch_detector.sh
NAMESPACE="${NAMESPACE}" ./scripts/up_latch_diagnoser.sh
NAMESPACE="${NAMESPACE}" ./scripts/up_latch_api_gateway.sh
NAMESPACE="${NAMESPACE}" ./scripts/up_latch_ui.sh

ready_replicas="$(kubectl -n "${NAMESPACE}" get deploy vllm -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
if [[ -z "${ready_replicas}" || "${ready_replicas}" == "0" ]]; then
  echo "[run-demo] vLLM is not ready in namespace '${NAMESPACE}'."
  echo "[run-demo] Fix vLLM first, then rerun demo."
  echo "[run-demo] Hint: NAMESPACE=${NAMESPACE} MODEL=${VLLM_MODEL_ID} SERVED_MODEL_NAME=${SERVED_MODEL_NAME} REPLICAS=1 ./scripts/up.sh"
  exit 1
fi

if (( ready_replicas < DEMO_VLLM_REPLICAS )); then
  echo "[run-demo] vLLM ready replicas (${ready_replicas}) < required (${DEMO_VLLM_REPLICAS}) for imbalance demo."
  echo "[run-demo] Attempting to scale deployment/vllm to ${DEMO_VLLM_REPLICAS}..."
  kubectl -n "${NAMESPACE}" scale deploy/vllm --replicas="${DEMO_VLLM_REPLICAS}" >/dev/null || true
  kubectl -n "${NAMESPACE}" rollout status deploy/vllm --timeout=8m >/dev/null || true
  ready_replicas="$(kubectl -n "${NAMESPACE}" get deploy vllm -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
fi

if (( ready_replicas < DEMO_VLLM_REPLICAS )); then
  echo "[run-demo] Not enough ready vLLM replicas (${ready_replicas}/${DEMO_VLLM_REPLICAS})."
  echo "[run-demo] This demo requires multi-replica capacity (MIG slices or multiple GPUs)."
  echo "[run-demo] Exiting without running imbalance scenario."
  exit 1
fi

run_window() {
  local name="$1"
  local duration="$2"
  local local_port="$3"
  local state_file="${OUT_DIR}/state_${name}.jsonl"
  local load_file="${OUT_DIR}/load_${name}.json"
  echo "[run-demo] ${name}: load ${duration}s + state timeline"
  NAMESPACE="${NAMESPACE}" SERVICE=latch-metrics PORT=8080 LOCAL_PORT="${local_port}" \
  INTERVAL_S="${STATE_INTERVAL_S}" DURATION_S="$((duration + 4))" OUT_PATH="${state_file}" \
  ./scripts/state_live.sh >/dev/null 2>&1 &
  local state_pid=$!

  NAMESPACE="${NAMESPACE}" SERVICE="${SERVICE}" PORT="${PORT}" MODEL="${MODEL}" \
  MODE=steady DURATION_S="${duration}" CONCURRENCY="${CONCURRENCY}" STEADY_RPS="${STEADY_RPS}" UNIQUE_PROMPTS=1 \
  ./scripts/run_load.sh > "${load_file}.out" 2>&1
  wait "${state_pid}" || true
  awk 'BEGIN{ok=0} /^{/{ok=1} {if(ok) print}' "${load_file}.out" > "${load_file}"
}

echo "[run-demo] Step 2/8 baseline (balanced)"
NAMESPACE="${NAMESPACE}" ./scripts/disable_imbalance.sh >/dev/null 2>&1 || true
run_window "before" "${BASELINE_DURATION_S}" 18490

echo "[run-demo] Step 3/8 enable imbalance"
NAMESPACE="${NAMESPACE}" ./scripts/enable_imbalance.sh

echo "[run-demo] Step 4/8 run incident load"
run_window "incident" "${INCIDENT_DURATION_S}" 18491

echo "[run-demo] Step 5/8 show incident"
NAMESPACE="${NAMESPACE}" SERVICE=latch-detector PORT=8081 LOCAL_PORT=18492 ./scripts/incidents.sh | tee "${OUT_DIR}/incidents.txt"
kubectl -n "${NAMESPACE}" port-forward svc/latch-detector 18492:8081 >/tmp/pf-run-demo-inc.log 2>&1 &
PF_INC=$!
sleep 2
curl -fsS "http://127.0.0.1:18492/incidents" > "${OUT_DIR}/incidents.json"
kill "${PF_INC}" >/dev/null 2>&1 || true
INC_ID="$(jq -r '.active[0].id // empty' "${OUT_DIR}/incidents.json")"
echo "[run-demo] incident_id=${INC_ID}"

echo "[run-demo] Step 6/8 apply fix via API gateway"
kubectl -n "${NAMESPACE}" port-forward svc/latch-api-gateway 18493:8090 >/tmp/pf-run-demo-api.log 2>&1 &
PF_API=$!
sleep 2
curl -fsS -X POST "http://127.0.0.1:18493/fix/apply" > "${OUT_DIR}/fix_apply.json"
kill "${PF_API}" >/dev/null 2>&1 || true

echo "[run-demo] Step 7/8 run recovery load"
run_window "after" "${RECOVERY_DURATION_S}" 18494

echo "[run-demo] Step 8/8 diagnosis + report"
if [[ -n "${INC_ID}" ]]; then
  NAMESPACE="${NAMESPACE}" SERVICE=latch-diagnoser PORT=8082 INC="${INC_ID}" LOCAL_PORT=18495 ./scripts/diagnose.sh | tee "${OUT_DIR}/diagnosis.txt" || true
fi

python3 - "${OUT_DIR}" <<'PY'
import json
import os
import sys

out = sys.argv[1]

def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def read_jsonl(path):
    rows = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            rows.append(json.loads(line))
    return rows

def summarize_state(rows):
    if not rows:
        return {"qps": 0.0, "ttft": 0.0, "gpu": 0.0}
    qps = [float((r.get("global") or {}).get("qps") or 0.0) for r in rows]
    ttft = [float((r.get("global") or {}).get("ttft_p95_ms") or 0.0) for r in rows]
    gpu = []
    for r in rows:
        reps = r.get("replicas") or []
        vals = [float(rep.get("gpu_util") or 0.0) for rep in reps]
        gpu.append(max(vals) if vals else 0.0)
    return {
        "qps": sum(qps) / max(1, len(qps)),
        "ttft": sum(ttft) / max(1, len(ttft)),
        "gpu": sum(gpu) / max(1, len(gpu)),
    }

before_state = summarize_state(read_jsonl(os.path.join(out, "state_before.jsonl")))
after_state = summarize_state(read_jsonl(os.path.join(out, "state_after.jsonl")))
incident_state = summarize_state(read_jsonl(os.path.join(out, "state_incident.jsonl")))

before_load = load_json(os.path.join(out, "load_before.json"))
after_load = load_json(os.path.join(out, "load_after.json"))
incident_load = load_json(os.path.join(out, "load_incident.json"))

print("[run-demo] Final report")
print("phase\tqps_avg\tttft_p95_ms_avg\tgpu_util_max_avg\tload_qps\tload_p95_s")
print(f"before\t{before_state['qps']:.3f}\t{before_state['ttft']:.3f}\t{before_state['gpu']:.3f}\t{before_load.get('qps',0):.3f}\t{before_load.get('latency_s',{}).get('p95',0):.3f}")
print(f"incident\t{incident_state['qps']:.3f}\t{incident_state['ttft']:.3f}\t{incident_state['gpu']:.3f}\t{incident_load.get('qps',0):.3f}\t{incident_load.get('latency_s',{}).get('p95',0):.3f}")
print(f"after\t{after_state['qps']:.3f}\t{after_state['ttft']:.3f}\t{after_state['gpu']:.3f}\t{after_load.get('qps',0):.3f}\t{after_load.get('latency_s',{}).get('p95',0):.3f}")
print("[run-demo] Artifacts:", out)
PY

echo "[run-demo] Dashboard port-forward:"
echo "  kubectl -n ${NAMESPACE} port-forward svc/latch-ui 18088:8088"
