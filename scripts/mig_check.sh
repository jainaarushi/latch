#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-latchverify}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[mig-check] kubectl is required"
  echo "[mig-check] Run: make bootstrap"
  exit 1
fi
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[mig-check] kubectl context/cluster is not reachable"
  echo "[mig-check] Configure kubeconfig, then retry."
  exit 1
fi

PODS=$(kubectl -n "${NAMESPACE}" get pods -l app.kubernetes.io/name=vllm -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
if [[ -z "${PODS}" ]]; then
  echo "[mig-check] No vLLM pods found in namespace ${NAMESPACE}"
  exit 1
fi

echo "[mig-check] Namespace: ${NAMESPACE}"
for pod in ${PODS}; do
  echo "[mig-check] POD=${pod}"
  kubectl -n "${NAMESPACE}" exec "${pod}" -- bash -lc 'echo "NVIDIA_VISIBLE_DEVICES=${NVIDIA_VISIBLE_DEVICES:-}"; nvidia-smi -L | sed -n "1,5p"'
  echo
done
