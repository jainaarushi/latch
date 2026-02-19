#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-phase1full}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[latch-detector] kubectl is required"
  echo "[latch-detector] Run: make bootstrap"
  exit 1
fi
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[latch-detector] kubectl context/cluster is not reachable"
  echo "[latch-detector] Configure kubeconfig, then retry."
  exit 1
fi

kubectl get ns "${NAMESPACE}" >/dev/null 2>&1 || kubectl create ns "${NAMESPACE}" >/dev/null

kubectl -n "${NAMESPACE}" get svc latch-metrics >/dev/null 2>&1 || {
  echo "[latch-detector] latch-metrics service not found in namespace '${NAMESPACE}'"
  echo "[latch-detector] Run: NAMESPACE=${NAMESPACE} make up-latch-metrics"
  exit 1
}

echo "[latch-detector] Deploying latch-detector..."
kubectl -n "${NAMESPACE}" create configmap latch-detector-code \
  --from-file=services/latch-detector/main.py \
  --from-file=services/latch-detector/requirements.txt \
  --from-file=services/latch-detector/rules.yaml \
  --dry-run=client -o yaml | kubectl -n "${NAMESPACE}" apply -f - >/dev/null

kubectl -n "${NAMESPACE}" apply -f deploy/latch-detector/deployment.yaml >/dev/null
kubectl -n "${NAMESPACE}" set env deploy/latch-detector \
  METRICS_STATE_URL="http://latch-metrics.${NAMESPACE}.svc.cluster.local:8080/state" >/dev/null
kubectl -n "${NAMESPACE}" rollout restart deploy/latch-detector >/dev/null

echo "[latch-detector] Waiting for Ready..."
kubectl -n "${NAMESPACE}" rollout status deploy/latch-detector --timeout=10m >/dev/null

echo "[latch-detector] Endpoint: GET /incidents"
echo "[latch-detector] Service: latch-detector.${NAMESPACE}.svc.cluster.local:8081"
