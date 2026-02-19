#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-phase1full}
SELECTOR=${SELECTOR:-app.kubernetes.io/name=vllm}
LABEL_KEY=${LABEL_KEY:-llm-d.ai/inference-serving}
WAIT_S=${WAIT_S:-10}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[scenario] kubectl is required"
  echo "[scenario] Run: make bootstrap"
  exit 1
fi
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[scenario] kubectl context/cluster is not reachable"
  echo "[scenario] Configure kubeconfig, then retry."
  exit 1
fi

echo "[scenario] Disabling replica imbalance..."
mapfile -t pods < <(kubectl -n "${NAMESPACE}" get pods -l "${SELECTOR}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sort)
for pod in "${pods[@]}"; do
  kubectl -n "${NAMESPACE}" label pod "${pod}" "${LABEL_KEY}=true" --overwrite >/dev/null
done

echo "[scenario] Waiting ${WAIT_S}s for effect..."
sleep "${WAIT_S}"

echo "[scenario] Done."
if command -v jq >/dev/null 2>&1; then
  echo -e "NAME\tREADY\tLLMD"
  kubectl -n "${NAMESPACE}" get pods -l "${SELECTOR}" -o json \
    | jq -r '.items[] | [.metadata.name, (.status.containerStatuses[0].ready | tostring), (.metadata.labels["llm-d.ai/inference-serving"] // "-")] | @tsv'
else
  kubectl -n "${NAMESPACE}" get pods -l "${SELECTOR}" -o custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[0].ready
fi
