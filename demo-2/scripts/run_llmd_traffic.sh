#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-kubnamespace}"
RELEASE_NAME_POSTFIX="${RELEASE_NAME_POSTFIX:-inference-scheduling}"
MODEL="${MODEL:-TinyLlama/TinyLlama-1.1B-Chat-v1.0}"
TOTAL_REQUESTS="${TOTAL_REQUESTS:-200}"
CONCURRENCY="${CONCURRENCY:-16}"
MAX_TOKENS="${MAX_TOKENS:-32}"
TIMEOUT_S="${TIMEOUT_S:-120}"
STREAM="${STREAM:-false}"
LONG_SYSTEM_TOKENS="${LONG_SYSTEM_TOKENS:-0}"
LONG_USER_TOKENS="${LONG_USER_TOKENS:-0}"
START_SPACING_MS="${START_SPACING_MS:-0}"
JITTER_MS="${JITTER_MS:-0}"

GATEWAY_URI="${GATEWAY_URI:-http://infra-${RELEASE_NAME_POSTFIX}-inference-gateway-istio.${NAMESPACE}.svc.cluster.local}"

PROFILE_FILE="$(mktemp /tmp/llmd-traffic-profile.XXXXXX.json)"
trap 'rm -f "$PROFILE_FILE"' EXIT

cat > "$PROFILE_FILE" <<JSON
{
  "namespace": "${NAMESPACE}",
  "gateway_uri": "${GATEWAY_URI}",
  "model": "${MODEL}",
  "total_requests": ${TOTAL_REQUESTS},
  "concurrency": ${CONCURRENCY},
  "stream": ${STREAM},
  "max_tokens": ${MAX_TOKENS},
  "long_system_tokens": ${LONG_SYSTEM_TOKENS},
  "long_user_tokens": ${LONG_USER_TOKENS},
  "start_spacing_ms": ${START_SPACING_MS},
  "jitter_ms": ${JITTER_MS},
  "timeout_s": ${TIMEOUT_S}
}
JSON

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/run_synthetic_traffic.sh" "$PROFILE_FILE"
