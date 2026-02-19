#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-kubnamespace}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required"
  exit 1
fi

echo "== core resources (${NAMESPACE}) =="
kubectl -n "${NAMESPACE}" get pods,svc,deploy

echo ""
echo "== llm-d / gateway resources (${NAMESPACE}) =="
kubectl -n "${NAMESPACE}" get gateways.gateway.networking.k8s.io 2>/dev/null || true
kubectl -n "${NAMESPACE}" get httproutes.gateway.networking.k8s.io 2>/dev/null || true
kubectl -n "${NAMESPACE}" get inferencepools.inference.networking.k8s.io 2>/dev/null || true
