#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-phase1full}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[latch-diagnoser] kubectl is required"
  echo "[latch-diagnoser] Run: make bootstrap"
  exit 1
fi
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[latch-diagnoser] kubectl context/cluster is not reachable"
  echo "[latch-diagnoser] Configure kubeconfig, then retry."
  exit 1
fi

kubectl get ns "${NAMESPACE}" >/dev/null 2>&1 || kubectl create ns "${NAMESPACE}" >/dev/null

kubectl -n "${NAMESPACE}" get svc latch-detector >/dev/null 2>&1 || {
  echo "[latch-diagnoser] latch-detector service not found in namespace '${NAMESPACE}'"
  echo "[latch-diagnoser] Run: NAMESPACE=${NAMESPACE} make up-latch-detector"
  exit 1
}

kubectl -n "${NAMESPACE}" get svc latch-metrics >/dev/null 2>&1 || {
  echo "[latch-diagnoser] latch-metrics service not found in namespace '${NAMESPACE}'"
  echo "[latch-diagnoser] Run: NAMESPACE=${NAMESPACE} make up-latch-metrics"
  exit 1
}

echo "[latch-diagnoser] Deploying latch-diagnoser..."
kubectl -n "${NAMESPACE}" create configmap latch-diagnoser-code \
  --from-file=services/latch-diagnoser/main.py \
  --from-file=services/latch-diagnoser/llm_summarizer.py \
  --from-file=services/latch-diagnoser/requirements.txt \
  --from-file=services/latch-diagnoser/templates/imbalance.md \
  --dry-run=client -o yaml | kubectl -n "${NAMESPACE}" apply -f - >/dev/null

kubectl -n "${NAMESPACE}" apply -f deploy/latch-diagnoser/deployment.yaml >/dev/null
kubectl -n "${NAMESPACE}" set env deploy/latch-diagnoser \
  DETECTOR_INCIDENTS_URL="http://latch-detector.${NAMESPACE}.svc.cluster.local:8081/incidents" \
  METRICS_STATE_URL="http://latch-metrics.${NAMESPACE}.svc.cluster.local:8080/state" >/dev/null
kubectl -n "${NAMESPACE}" rollout restart deploy/latch-diagnoser >/dev/null

echo "[latch-diagnoser] Waiting for Ready..."
kubectl -n "${NAMESPACE}" rollout status deploy/latch-diagnoser --timeout=10m >/dev/null

echo "[latch-diagnoser] Endpoint: GET /incidents/{id}/diagnosis"
echo "[latch-diagnoser] Service: latch-diagnoser.${NAMESPACE}.svc.cluster.local:8082"
