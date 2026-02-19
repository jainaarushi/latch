#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-phase1full}
SERVICE=${SERVICE:-latch-metrics}
PORT=${PORT:-8080}
LOCAL_PORT=${LOCAL_PORT:-18090}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[state] kubectl is required"
  echo "[state] Run: make bootstrap"
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "[state] curl is required"
  exit 1
fi
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[state] kubectl context/cluster is not reachable"
  echo "[state] Configure kubeconfig, then retry."
  exit 1
fi

kubectl -n "${NAMESPACE}" get svc "${SERVICE}" >/dev/null

kubectl -n "${NAMESPACE}" port-forward svc/"${SERVICE}" "${LOCAL_PORT}:${PORT}" >/tmp/pf-state.log 2>&1 &
PF_PID=$!
cleanup() {
  kill "${PF_PID}" >/dev/null 2>&1 || true
}
trap cleanup EXIT
sleep 2

RESP=$(curl -sS "http://127.0.0.1:${LOCAL_PORT}/state")
if command -v jq >/dev/null 2>&1; then
  echo "${RESP}" | jq .
else
  echo "${RESP}"
fi
