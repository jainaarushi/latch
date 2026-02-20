#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-phase1full}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[latch-api-gateway] kubectl is required"
  echo "[latch-api-gateway] Run: make bootstrap"
  exit 1
fi
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[latch-api-gateway] kubectl context/cluster is not reachable"
  echo "[latch-api-gateway] Configure kubeconfig, then retry."
  exit 1
fi

kubectl get ns "${NAMESPACE}" >/dev/null 2>&1 || kubectl create ns "${NAMESPACE}" >/dev/null

for svc in latch-metrics latch-detector latch-diagnoser; do
  kubectl -n "${NAMESPACE}" get svc "${svc}" >/dev/null 2>&1 || {
    echo "[latch-api-gateway] missing service '${svc}' in namespace '${NAMESPACE}'"
    echo "[latch-api-gateway] run up_latch_metrics/up_latch_detector/up_latch_diagnoser first"
    exit 1
  }
done

echo "[latch-api-gateway] Deploying latch-api-gateway..."
kubectl -n "${NAMESPACE}" create configmap latch-api-gateway-code \
  --from-file=services/latch-api-gateway/main.py \
  --from-file=services/latch-api-gateway/requirements.txt \
  --dry-run=client -o yaml | kubectl -n "${NAMESPACE}" apply -f - >/dev/null

kubectl -n "${NAMESPACE}" apply -f deploy/latch-api-gateway/deployment.yaml >/dev/null
kubectl -n "${NAMESPACE}" set env deploy/latch-api-gateway \
  TARGET_NAMESPACE="${NAMESPACE}" \
  METRICS_STATE_URL="http://latch-metrics.${NAMESPACE}.svc.cluster.local:8080/state" \
  DETECTOR_INCIDENTS_URL="http://latch-detector.${NAMESPACE}.svc.cluster.local:8081/incidents" \
  DIAGNOSER_BASE_URL="http://latch-diagnoser.${NAMESPACE}.svc.cluster.local:8082/incidents" >/dev/null
kubectl -n "${NAMESPACE}" rollout restart deploy/latch-api-gateway >/dev/null

echo "[latch-api-gateway] Waiting for Ready..."
kubectl -n "${NAMESPACE}" rollout status deploy/latch-api-gateway --timeout=10m >/dev/null

echo "[latch-api-gateway] Service: latch-api-gateway.${NAMESPACE}.svc.cluster.local:8090"
echo "[latch-api-gateway] Endpoints: /state /incidents /diagnosis/{id} /fix/apply /fix/rollback"
