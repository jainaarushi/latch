#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-kubnamespace}
REPLICAS=${REPLICAS:-2}
VLLM_IMAGE=${VLLM_IMAGE:-vllm/vllm-openai:nightly}
MODEL=${MODEL:-TinyLlama/TinyLlama-1.1B-Chat-v1.0}
SERVED_MODEL_NAME=${SERVED_MODEL_NAME:-tinyllama}
GPU_RESOURCE_KEY=${GPU_RESOURCE_KEY:-nvidia.com/mig-2g.10gb}
GPU_RESOURCE_VALUE=${GPU_RESOURCE_VALUE:-1}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required"
  exit 1
fi

kubectl get ns "${NAMESPACE}" >/dev/null 2>&1 || kubectl create ns "${NAMESPACE}"

kubectl -n "${NAMESPACE}" apply -f deploy/vllm/deployment.yaml
kubectl -n "${NAMESPACE}" set image deployment/vllm vllm="${VLLM_IMAGE}"
kubectl -n "${NAMESPACE}" scale deployment/vllm --replicas="${REPLICAS}"
kubectl -n "${NAMESPACE}" patch deployment vllm --type='json' -p "[
  {\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/args/1\",\"value\":\"${MODEL}\"},
  {\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/args/3\",\"value\":\"${SERVED_MODEL_NAME}\"}
]"
kubectl -n "${NAMESPACE}" patch deployment vllm --type='merge' -p "$(cat <<EOF
spec:
  template:
    spec:
      containers:
      - name: vllm
        resources:
          requests:
            cpu: "4"
            memory: 16Gi
            ${GPU_RESOURCE_KEY}: "${GPU_RESOURCE_VALUE}"
          limits:
            cpu: "8"
            memory: 24Gi
            ${GPU_RESOURCE_KEY}: "${GPU_RESOURCE_VALUE}"
EOF
)"

kubectl -n "${NAMESPACE}" rollout status deployment/vllm --timeout=20m
kubectl -n "${NAMESPACE}" get pods -l app.kubernetes.io/name=vllm -o wide

cat <<MSG

vLLM is up.
Namespace: ${NAMESPACE}
Replicas: ${REPLICAS}
Service: vllm:${NAMESPACE}.svc.cluster.local:8000
GPU resource request: ${GPU_RESOURCE_KEY}=${GPU_RESOURCE_VALUE}

Test command:
  make test-infer NAMESPACE=${NAMESPACE} MODEL=${SERVED_MODEL_NAME}
MSG
