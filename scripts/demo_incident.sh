#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-kubnamespace}
RELEASE_POSTFIX=${RELEASE_POSTFIX:-${NAMESPACE}}
SERVICE=${SERVICE:-infra-${RELEASE_POSTFIX}-inference-gateway-istio}
PORT=${PORT:-80}
MODEL=${MODEL:-tinyllama}
CONCURRENCY=${CONCURRENCY:-12}
STEADY_RPS=${STEADY_RPS:-8}
BASELINE_DURATION_S=${BASELINE_DURATION_S:-30}
INCIDENT_DURATION_S=${INCIDENT_DURATION_S:-60}
STATE_INTERVAL_S=${STATE_INTERVAL_S:-2}
STATE_OUT=${STATE_OUT:-/tmp/latch-incident-demo/state_imbalance.jsonl}
AUTO_DISABLE_IMBALANCE=${AUTO_DISABLE_IMBALANCE:-true}
KEEP_POD=${KEEP_POD:-}

need_cmd() { command -v "$1" >/dev/null 2>&1; }
for cmd in kubectl curl jq; do
  if ! need_cmd "${cmd}"; then
    echo "[demo-incident] Missing required command: ${cmd}"
    exit 1
  fi
done
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[demo-incident] kubectl context/cluster is not reachable"
  echo "[demo-incident] Configure kubeconfig, then retry."
  exit 1
fi

echo "[demo-incident] namespace=${NAMESPACE} service=${SERVICE} model=${MODEL}"
echo "[demo-incident] baseline=${BASELINE_DURATION_S}s incident=${INCIDENT_DURATION_S}s"

for svc in latch-metrics latch-detector latch-diagnoser; do
  if ! kubectl -n "${NAMESPACE}" get svc "${svc}" >/dev/null 2>&1; then
    echo "[demo-incident] ${svc} not found in ${NAMESPACE}; deploying..."
    case "${svc}" in
      latch-metrics) NAMESPACE="${NAMESPACE}" ./scripts/up_latch_metrics.sh ;;
      latch-detector) NAMESPACE="${NAMESPACE}" ./scripts/up_latch_detector.sh ;;
      latch-diagnoser) NAMESPACE="${NAMESPACE}" ./scripts/up_latch_diagnoser.sh ;;
    esac
  fi
done

echo "[demo-incident] Step 1/6: ensure balanced routing"
NAMESPACE="${NAMESPACE}" ./scripts/disable_imbalance.sh >/tmp/demo_incident_disable.log 2>&1 || true

echo "[demo-incident] Step 2/6: baseline load"
NAMESPACE="${NAMESPACE}" SERVICE="${SERVICE}" PORT="${PORT}" MODEL="${MODEL}" \
MODE=steady DURATION_S="${BASELINE_DURATION_S}" CONCURRENCY="${CONCURRENCY}" \
STEADY_RPS="${STEADY_RPS}" UNIQUE_PROMPTS=1 ./scripts/run_load.sh >/tmp/demo_incident_baseline_load.out 2>&1
tail -n 20 /tmp/demo_incident_baseline_load.out

echo "[demo-incident] Step 3/6: enable imbalance scenario"
if [[ -n "${KEEP_POD}" ]]; then
  NAMESPACE="${NAMESPACE}" KEEP_POD="${KEEP_POD}" ./scripts/enable_imbalance.sh
else
  NAMESPACE="${NAMESPACE}" ./scripts/enable_imbalance.sh
fi

echo "[demo-incident] Step 4/6: run load + collect state timeline"
mkdir -p "$(dirname "${STATE_OUT}")"
NAMESPACE="${NAMESPACE}" SERVICE=latch-metrics PORT=8080 LOCAL_PORT=18290 \
INTERVAL_S="${STATE_INTERVAL_S}" DURATION_S="$((INCIDENT_DURATION_S + 8))" OUT_PATH="${STATE_OUT}" \
./scripts/state_live.sh >/tmp/demo_incident_state_live.log 2>&1 &
STATE_LIVE_PID=$!

NAMESPACE="${NAMESPACE}" SERVICE="${SERVICE}" PORT="${PORT}" MODEL="${MODEL}" \
MODE=steady DURATION_S="${INCIDENT_DURATION_S}" CONCURRENCY="${CONCURRENCY}" \
STEADY_RPS="${STEADY_RPS}" UNIQUE_PROMPTS=1 ./scripts/run_load.sh >/tmp/demo_incident_imbalance_load.out 2>&1
wait "${STATE_LIVE_PID}" || true
tail -n 20 /tmp/demo_incident_imbalance_load.out

echo "[demo-incident] Step 5/6: query incidents"
INCIDENTS_RAW=/tmp/demo_incident_incidents.json
NAMESPACE="${NAMESPACE}" SERVICE=latch-detector PORT=8081 LOCAL_PORT=18291 ./scripts/incidents.sh || true
kubectl -n "${NAMESPACE}" port-forward svc/latch-detector 18291:8081 >/tmp/pf-demo-inc.log 2>&1 &
PF_PID=$!
sleep 2
curl -fsS "http://127.0.0.1:18291/incidents" > "${INCIDENTS_RAW}" || true
kill "${PF_PID}" >/dev/null 2>&1 || true

INC_ID="$(jq -r '.active[0].id // empty' "${INCIDENTS_RAW}" 2>/dev/null || true)"
if [[ -n "${INC_ID}" ]]; then
  echo "[demo-incident] Step 6/6: diagnose ${INC_ID}"
  NAMESPACE="${NAMESPACE}" INC="${INC_ID}" ./scripts/diagnose.sh || true
else
  echo "[demo-incident] Step 6/6: no active incident yet (try longer incident duration or higher skew)"
fi

if [[ "${AUTO_DISABLE_IMBALANCE}" == "true" ]]; then
  echo "[demo-incident] cleanup: disable imbalance"
  NAMESPACE="${NAMESPACE}" ./scripts/disable_imbalance.sh >/tmp/demo_incident_disable_after.log 2>&1 || true
fi

echo "[demo-incident] done."
echo "[demo-incident] state timeline: ${STATE_OUT}"
echo "[demo-incident] artifacts:"
echo "  /tmp/demo_incident_baseline_load.out"
echo "  /tmp/demo_incident_imbalance_load.out"
echo "  /tmp/demo_incident_incidents.json"
echo "  /tmp/demo_incident_state_live.log"
