#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-kubnamespace}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required"
  exit 1
fi

echo "== kubectl context =="
kubectl config current-context

echo ""
echo "== nodes =="
kubectl get nodes -o wide

echo ""
echo "== nvidia resources (allocatable) =="
kubectl get nodes -o go-template='{{range .items}}{{.metadata.name}}{{"\n"}}{{range $k,$v := .status.allocatable}}{{printf "  %s=%s\n" $k $v}}{{end}}{{"\n"}}{{end}}' \
  | grep -E '^[^ ]|nvidia.com/' || true

echo ""
echo "== device plugin / dcgm DaemonSets =="
kubectl -n kube-system get ds | grep -Ei 'nvidia|dcgm' || true

echo ""
echo "== first node MIG details =="
FIRST_NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
if [[ -n "${FIRST_NODE}" ]]; then
  kubectl describe node "${FIRST_NODE}" | grep -Ein 'mig|nvidia.com|allocatable|capacity' || true
fi

echo ""
echo "== namespace quick status (${NAMESPACE}) =="
kubectl -n "${NAMESPACE}" get pods,svc,deploy || true
