#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-phase1full}
OBS_NAMESPACE=${OBS_NAMESPACE:-observability}
PROM_SERVICE=${PROM_SERVICE:-prometheus}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[latch-metrics] kubectl is required"
  echo "[latch-metrics] Run: make bootstrap"
  exit 1
fi
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[latch-metrics] kubectl context/cluster is not reachable"
  echo "[latch-metrics] Configure kubeconfig, then retry."
  exit 1
fi

kubectl get ns "${NAMESPACE}" >/dev/null 2>&1 || kubectl create ns "${NAMESPACE}" >/dev/null

kubectl -n "${OBS_NAMESPACE}" get svc "${PROM_SERVICE}" >/dev/null 2>&1 || {
  echo "[latch-metrics] Prometheus service '${PROM_SERVICE}' not found in namespace '${OBS_NAMESPACE}'"
  exit 1
}

echo "[latch-metrics] Deploying latch-metrics..."
kubectl -n "${NAMESPACE}" create configmap latch-metrics-code \
  --from-file=services/latch-metrics/main.py \
  --from-file=services/latch-metrics/requirements.txt \
  --dry-run=client -o yaml | kubectl -n "${NAMESPACE}" apply -f - >/dev/null

kubectl -n "${NAMESPACE}" apply -f deploy/latch-metrics/deployment.yaml >/dev/null
kubectl -n "${NAMESPACE}" set env deploy/latch-metrics \
  TARGET_NAMESPACE="${NAMESPACE}" \
  PROMETHEUS_URL="http://${PROM_SERVICE}.${OBS_NAMESPACE}.svc.cluster.local:9090" >/dev/null
kubectl -n "${NAMESPACE}" rollout restart deploy/latch-metrics >/dev/null

echo "[latch-metrics] Waiting for Ready..."
kubectl -n "${NAMESPACE}" rollout status deploy/latch-metrics --timeout=10m >/dev/null

echo "[latch-metrics] Endpoint: GET /state"
echo "[latch-metrics] Service: latch-metrics.${NAMESPACE}.svc.cluster.local:8080"
