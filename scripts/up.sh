#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-kubnamespace}
REPLICAS=${REPLICAS:-2}
VLLM_IMAGE=${VLLM_IMAGE:-vllm/vllm-openai:nightly}
MODEL=${MODEL:-TinyLlama/TinyLlama-1.1B-Chat-v1.0}
SERVED_MODEL_NAME=${SERVED_MODEL_NAME:-tinyllama}
GPU_RESOURCE_VALUE=${GPU_RESOURCE_VALUE:-1}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[k8s] kubectl is required"
  echo "[k8s] Run: make bootstrap"
  exit 1
fi
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[k8s] kubectl context/cluster is not reachable"
  echo "[k8s] Configure kubeconfig, then retry."
  exit 1
fi

# Auto-detect GPU resource key if caller did not set one.
# Prefer an allocatable MIG resource, else fall back to nvidia.com/gpu.
if [[ -z "${GPU_RESOURCE_KEY:-}" ]]; then
  GPU_RESOURCE_KEY=$(
    kubectl get nodes -o go-template='{{range .items}}{{range $k,$v := .status.allocatable}}{{printf "%s=%s\n" $k $v}}{{end}}{{end}}' \
      | awk -F= '/^nvidia.com\/mig-/ && $2 != "0" { print $1; exit }'
  )
  if [[ -z "${GPU_RESOURCE_KEY}" ]]; then
    GPU_RESOURCE_KEY="nvidia.com/gpu"
  fi
fi

if kubectl get ns "${NAMESPACE}" >/dev/null 2>&1; then
  echo "[k8s] Namespace ${NAMESPACE} already exists... OK"
else
  kubectl create ns "${NAMESPACE}" >/dev/null
  echo "[k8s] Creating namespace ${NAMESPACE}... OK"
fi

echo "[vllm] Applying manifests..."
kubectl -n "${NAMESPACE}" apply -f deploy/vllm/deployment.yaml
kubectl -n "${NAMESPACE}" set image deployment/vllm vllm="${VLLM_IMAGE}"
kubectl -n "${NAMESPACE}" scale deployment/vllm --replicas="${REPLICAS}"
kubectl -n "${NAMESPACE}" patch deployment vllm --type='json' -p "[
  {\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/args/1\",\"value\":\"${MODEL}\"},
  {\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/args/3\",\"value\":\"${SERVED_MODEL_NAME}\"}
]"
kubectl -n "${NAMESPACE}" patch deployment vllm --type='strategic' -p "$(cat <<EOF
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

echo "[vllm] Waiting for rollout..."
kubectl -n "${NAMESPACE}" rollout status deployment/vllm --timeout=20m
kubectl -n "${NAMESPACE}" get pods -l app.kubernetes.io/name=vllm --no-headers \
  | awk '{printf "  pod/%s   %s   %s\n", $1, $2, $3}'

echo "[vllm] Service: vllm.${NAMESPACE}.svc.cluster.local:8000 ... OK"
echo "[vllm] GPU resource request: ${GPU_RESOURCE_KEY}=${GPU_RESOURCE_VALUE}"

cat <<MSG
[vllm] Done.
Run sanity test:
  make test-infer NAMESPACE=${NAMESPACE} MODEL=${SERVED_MODEL_NAME}
MSG
