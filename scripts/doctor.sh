#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-kubnamespace}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[doctor] Checking kubectl... FAIL (not found)"
  echo "[doctor] Run: make bootstrap"
  exit 1
fi
KVER=$(kubectl version --client -o yaml 2>/dev/null | awk '/gitVersion:/{print $2; exit}' || true)
echo "[doctor] Checking kubectl... OK (${KVER:-installed})"

if command -v helm >/dev/null 2>&1; then
  HVER=$(helm version --short 2>/dev/null | head -n1)
  echo "[doctor] Checking helm... OK (${HVER})"
else
  echo "[doctor] Checking helm... WARN (not found)"
fi

CTX=$(kubectl config current-context 2>/dev/null || true)
if [[ -n "${CTX}" ]]; then
  echo "[doctor] Checking cluster access... OK (context: ${CTX})"
else
  echo "[doctor] Checking cluster access... FAIL (no current context)"
  echo "[doctor] Set kubeconfig/context, then retry."
  exit 1
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[doctor] Checking API server reachability... FAIL (context set, server unreachable)"
  echo "[doctor] Verify cluster is running and kubeconfig points to it."
  exit 1
fi

NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "${NODE}" ]]; then
  echo "[doctor] Checking node discovery... FAIL"
  exit 1
fi
echo "[doctor] Checking node discovery... OK (${NODE})"

ALLOC=$(kubectl describe node "${NODE}" | sed -n '/Allocatable:/,/System Info:/p' | grep -E 'nvidia.com/(gpu|mig)' || true)
if [[ -z "${ALLOC}" ]]; then
  echo "[doctor] Checking node GPU allocatable... FAIL (no nvidia resource)"
  exit 1
fi
echo "[doctor] Checking node GPU allocatable... OK"
echo "${ALLOC}" | sed 's/^/[doctor]   /'

if echo "${ALLOC}" | grep -q 'nvidia.com/mig-'; then
  echo "[doctor] Checking MIG mode... Mode A (explicit MIG resources)"
else
  echo "[doctor] Checking MIG mode... Mode B (MIG-backed gpu units)"
fi

PLUGIN=$(kubectl -n kube-system get ds --no-headers 2>/dev/null | grep -Ei 'nvidia|dcgm' || true)
if [[ -n "${PLUGIN}" ]]; then
  echo "[doctor] Checking device plugin... OK"
else
  echo "[doctor] Checking device plugin... WARN (not found)"
fi

if kubectl get runtimeclass nvidia >/dev/null 2>&1; then
  echo "[doctor] Checking GPU runtime class... OK (nvidia)"
else
  echo "[doctor] Checking GPU runtime class... WARN (runtimeclass nvidia not found)"
fi

echo "[doctor] Checking namespace resources (${NAMESPACE})..."
kubectl -n "${NAMESPACE}" get pods,svc,deploy 2>/dev/null | sed 's/^/[doctor]   /' || echo "[doctor]   (namespace empty or missing)"
echo "[doctor] Done."
