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
kubectl get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu,MIG_1G5:.status.allocatable.nvidia\.com/mig-1g\.5gb,MIG_2G10:.status.allocatable.nvidia\.com/mig-2g\.10gb,MIG_3G20:.status.allocatable.nvidia\.com/mig-3g\.20gb' || true

echo ""
echo "== device plugin / dcgm DaemonSets =="
kubectl -n kube-system get ds | rg -i 'nvidia|dcgm' || true

echo ""
echo "== first node MIG details =="
FIRST_NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
if [[ -n "${FIRST_NODE}" ]]; then
  kubectl describe node "${FIRST_NODE}" | rg -n -i 'mig|nvidia.com|allocatable|capacity' || true
fi

echo ""
echo "== namespace quick status (${NAMESPACE}) =="
kubectl -n "${NAMESPACE}" get pods,svc,deploy || true
