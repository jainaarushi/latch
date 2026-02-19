#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-kubnamespace}
RELEASE_POSTFIX=${RELEASE_POSTFIX:-hello}
GAIE_VERSION=${GAIE_VERSION:-v1.3.0}
LLMD_INFRA_VERSION=${LLMD_INFRA_VERSION:-v1.3.6}
ISTIO_VERSION=${ISTIO_VERSION:-1.28.1}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[llm-d] kubectl is required"
  exit 1
fi
if ! command -v helm >/dev/null 2>&1; then
  echo "[llm-d] helm is required"
  exit 1
fi

if kubectl get ns "${NAMESPACE}" >/dev/null 2>&1; then
  echo "[k8s] Namespace ${NAMESPACE} already exists... OK"
else
  kubectl create ns "${NAMESPACE}" >/dev/null
  echo "[k8s] Creating namespace ${NAMESPACE}... OK"
fi
kubectl get ns istio-system >/dev/null 2>&1 || kubectl create ns istio-system >/dev/null

echo "[llm-d] Applying Gateway API + GAIE CRDs..."
kubectl apply -k "https://github.com/kubernetes-sigs/gateway-api/config/crd?ref=v1.4.0"
kubectl apply -k "https://github.com/kubernetes-sigs/gateway-api-inference-extension/config/crd?ref=v1.3.0"

echo "[llm-d] Installing Istio gateway provider..."
helm repo add istio https://istio-release.storage.googleapis.com/charts >/dev/null
helm repo add llm-d-infra https://llm-d-incubation.github.io/llm-d-infra/ >/dev/null
helm repo update >/dev/null

helm upgrade --install istio-base istio/base \
  --version "${ISTIO_VERSION}" \
  -n istio-system --wait

helm upgrade --install istiod istio/istiod \
  --version "${ISTIO_VERSION}" \
  -n istio-system \
  --set meshConfig.defaultConfig.proxyMetadata.ENABLE_GATEWAY_API_INFERENCE_EXTENSION=true \
  --set pilot.env.ENABLE_GATEWAY_API_INFERENCE_EXTENSION=true \
  --set hub=docker.io/istio \
  --set tag="${ISTIO_VERSION}" \
  --wait

echo "[llm-d] Installing infra + scheduler..."
helm upgrade --install "infra-${RELEASE_POSTFIX}" llm-d-infra/llm-d-infra \
  --version "${LLMD_INFRA_VERSION}" \
  -n "${NAMESPACE}" \
  -f deploy/llmd/infra-values.yaml \
  --wait

helm upgrade --install "gaie-${RELEASE_POSTFIX}" \
  oci://registry.k8s.io/gateway-api-inference-extension/charts/inferencepool \
  --version "${GAIE_VERSION}" \
  -n "${NAMESPACE}" \
  -f deploy/llmd/gaie-values.yaml \
  -f <(cat <<EOF
provider:
  istio:
    destinationRule:
      host: "gaie-${RELEASE_POSTFIX}-epp.${NAMESPACE}.svc.cluster.local"
EOF
) \
  --wait

sed \
  -e "s/infra-hello/infra-${RELEASE_POSTFIX}/g" \
  -e "s/gaie-hello/gaie-${RELEASE_POSTFIX}/g" \
  deploy/llmd/httproute.yaml | kubectl -n "${NAMESPACE}" apply -f -

echo "[llm-d] Waiting for gateway + scheduler rollout..."
kubectl -n "${NAMESPACE}" rollout status deploy/"infra-${RELEASE_POSTFIX}"-inference-gateway-istio --timeout=10m >/dev/null
kubectl -n "${NAMESPACE}" rollout status deploy/"gaie-${RELEASE_POSTFIX}"-epp --timeout=10m >/dev/null

kubectl -n "${NAMESPACE}" get svc | grep -E "inference-gateway|gaie|vllm" | sed 's/^/[llm-d] /' || true

cat <<MSG

[llm-d] Gateway service:
  infra-${RELEASE_POSTFIX}-inference-gateway-istio.${NAMESPACE}.svc.cluster.local:80

[llm-d] Test through llm-d:
  make test-infer NAMESPACE=${NAMESPACE} SERVICE=infra-${RELEASE_POSTFIX}-inference-gateway-istio PORT=80

[llm-d] Show scheduler logs:
  make logs-routing NAMESPACE=${NAMESPACE} RELEASE_POSTFIX=${RELEASE_POSTFIX}
[llm-d] Done.
MSG
