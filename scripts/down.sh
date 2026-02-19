#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-kubnamespace}
RELEASE_POSTFIX=${RELEASE_POSTFIX:-hello}
DELETE_NAMESPACE=${DELETE_NAMESPACE:-false}
CLEAN_ISTIO=${CLEAN_ISTIO:-false}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required"
  exit 1
fi

kubectl -n "${NAMESPACE}" delete -f deploy/vllm/deployment.yaml --ignore-not-found=true || true
kubectl -n "${NAMESPACE}" delete httproute llmd-hello-world --ignore-not-found=true || true

if command -v helm >/dev/null 2>&1; then
  helm -n "${NAMESPACE}" uninstall "gaie-${RELEASE_POSTFIX}" --wait >/dev/null 2>&1 || true
  helm -n "${NAMESPACE}" uninstall "infra-${RELEASE_POSTFIX}" --wait >/dev/null 2>&1 || true
fi

if [[ "${DELETE_NAMESPACE}" == "true" ]]; then
  kubectl delete ns "${NAMESPACE}" --wait=false || true
fi

if [[ "${CLEAN_ISTIO}" == "true" ]] && command -v helm >/dev/null 2>&1; then
  helm -n istio-system uninstall istiod >/dev/null 2>&1 || true
  helm -n istio-system uninstall istio-base >/dev/null 2>&1 || true
fi

echo "Cleanup complete."
echo "NAMESPACE=${NAMESPACE} DELETE_NAMESPACE=${DELETE_NAMESPACE} CLEAN_ISTIO=${CLEAN_ISTIO}"
