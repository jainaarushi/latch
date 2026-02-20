#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-phase1full}
SELECTOR=${SELECTOR:-app.kubernetes.io/name=vllm}
LABEL_KEY=${LABEL_KEY:-llm-d.ai/inference-serving}
KEEP_POD=${KEEP_POD:-}
WAIT_S=${WAIT_S:-20}

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

echo "[scenario] Enabling replica imbalance..."

mapfile -t pods < <(kubectl -n "${NAMESPACE}" get pods -l "${SELECTOR}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sort)
if [[ ${#pods[@]} -lt 2 ]]; then
  echo "[scenario] Need at least 2 vLLM pods; found ${#pods[@]}"
  exit 1
fi

if [[ -z "${KEEP_POD}" ]]; then
  KEEP_POD="${pods[0]}"
fi

echo "[scenario] Applying route skew: target=${KEEP_POD}, others disabled for llm-d membership..."
echo "[scenario] Effective behavior: strong skew (single backend membership)."
for pod in "${pods[@]}"; do
  if [[ "${pod}" == "${KEEP_POD}" ]]; then
    kubectl -n "${NAMESPACE}" label pod "${pod}" "${LABEL_KEY}=true" --overwrite >/dev/null
  else
    kubectl -n "${NAMESPACE}" label pod "${pod}" "${LABEL_KEY}=false" --overwrite >/dev/null
  fi
done

echo "[scenario] Waiting ${WAIT_S}s for effect..."
sleep "${WAIT_S}"

echo "[scenario] Done."
if command -v jq >/dev/null 2>&1; then
  echo -e "NAME\tREADY\tLLMD"
  kubectl -n "${NAMESPACE}" get pods -l "${SELECTOR}" -o json \
    | jq -r '.items[] | [.metadata.name, (.status.containerStatuses[0].ready | tostring), (.metadata.labels["llm-d.ai/inference-serving"] // "-")] | @tsv'
  enabled_count=$(kubectl -n "${NAMESPACE}" get pods -l "${SELECTOR}" -o json | jq '[.items[] | select(.metadata.labels["llm-d.ai/inference-serving"]=="true")] | length')
  total_count=$(kubectl -n "${NAMESPACE}" get pods -l "${SELECTOR}" -o json | jq '.items | length')
  echo "[scenario] llm-d serving membership: ${enabled_count}/${total_count} pods enabled"
else
  kubectl -n "${NAMESPACE}" get pods -l "${SELECTOR}" -o custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[0].ready
fi
