#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-phase1full}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[latch-ui] kubectl is required"
  echo "[latch-ui] Run: make bootstrap"
  exit 1
fi
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[latch-ui] kubectl context/cluster is not reachable"
  echo "[latch-ui] Configure kubeconfig, then retry."
  exit 1
fi

kubectl get ns "${NAMESPACE}" >/dev/null 2>&1 || kubectl create ns "${NAMESPACE}" >/dev/null
kubectl -n "${NAMESPACE}" get svc latch-api-gateway >/dev/null 2>&1 || {
  echo "[latch-ui] latch-api-gateway service not found in namespace '${NAMESPACE}'"
  echo "[latch-ui] Run: NAMESPACE=${NAMESPACE} ./scripts/up_latch_api_gateway.sh"
  exit 1
}

echo "[latch-ui] Deploying UI assets..."
kubectl -n "${NAMESPACE}" create configmap latch-ui-assets \
  --from-file=ui/index.html \
  --from-file=ui/app.js \
  --from-file=ui/styles.css \
  --dry-run=client -o yaml | kubectl -n "${NAMESPACE}" apply -f - >/dev/null

kubectl -n "${NAMESPACE}" create configmap latch-ui-nginx \
  --from-file=default.conf=ui/nginx.conf \
  --dry-run=client -o yaml | kubectl -n "${NAMESPACE}" apply -f - >/dev/null

kubectl -n "${NAMESPACE}" apply -f deploy/ui/deployment.yaml >/dev/null
kubectl -n "${NAMESPACE}" rollout restart deploy/latch-ui >/dev/null

echo "[latch-ui] Waiting for Ready..."
kubectl -n "${NAMESPACE}" rollout status deploy/latch-ui --timeout=10m >/dev/null

echo "[latch-ui] Service: latch-ui.${NAMESPACE}.svc.cluster.local:8088"
echo "[latch-ui] Use: kubectl -n ${NAMESPACE} port-forward svc/latch-ui 18088:8088"
