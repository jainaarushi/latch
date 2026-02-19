#!/usr/bin/env bash
set -euo pipefail

GPU_INDEX=${GPU_INDEX:-0}
MIG_PROFILE_NAME=${MIG_PROFILE_NAME:-auto}
MIG_INSTANCE_COUNT=${MIG_INSTANCE_COUNT:-3}
REQUIRE_A100=${REQUIRE_A100:-true}

log() {
  echo "[bootstrap-mig] $*"
}

need_sudo() {
  if ! command -v sudo >/dev/null 2>&1; then
    log "sudo is required"
    exit 1
  fi
}

need_nvidia_smi() {
  if ! command -v nvidia-smi >/dev/null 2>&1; then
    log "nvidia-smi not found. Run ./scripts/bootstrap_gpu_host.sh first."
    exit 1
  fi
}

detect_profile_name() {
  if [[ "${MIG_PROFILE_NAME}" != "auto" ]]; then
    echo "${MIG_PROFILE_NAME}"
    return
  fi

  local total_mem
  total_mem=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits -i "${GPU_INDEX}" | tr -d ' ')

  # A100-40GB ~= 40536 MiB -> 2g.10gb slices
  # A100-80GB ~= 81165 MiB -> 2g.20gb slices
  if [[ -n "${total_mem}" ]] && (( total_mem >= 70000 )); then
    echo "2g.20gb"
  else
    echo "2g.10gb"
  fi
}

assert_gpu_model() {
  local name
  name=$(nvidia-smi --query-gpu=name --format=csv,noheader -i "${GPU_INDEX}" | head -n1)
  if [[ "${REQUIRE_A100}" == "true" ]] && [[ "${name}" != *"A100"* ]]; then
    log "GPU '${name}' is not A100 and REQUIRE_A100=true"
    exit 1
  fi
  log "GPU model: ${name}"
}

find_profile_id() {
  local profile_name="$1"
  # Parse first numeric token with trailing ":" on a matching profile line.
  nvidia-smi mig -i "${GPU_INDEX}" -lgip \
    | awk -v p="${profile_name}" '
      /GPU instance profile/ && $0 ~ p {
        for (i=1;i<=NF;i++) {
          if ($i ~ /^[0-9]+:$/) { gsub(/:/, "", $i); print $i; exit }
        }
      }
    '
}

enable_mig_mode() {
  log "Enabling MIG mode on GPU ${GPU_INDEX}"
  sudo nvidia-smi -i "${GPU_INDEX}" -mig 1 >/dev/null || true
}

reset_existing_layout() {
  log "Clearing existing MIG compute and GPU instances (if any)"
  sudo nvidia-smi mig -i "${GPU_INDEX}" -dci >/dev/null 2>&1 || true
  sudo nvidia-smi mig -i "${GPU_INDEX}" -dgi >/dev/null 2>&1 || true
}

apply_layout() {
  local profile_id="$1"
  local count="$2"
  local csv
  csv=$(yes "${profile_id}" | head -n "${count}" | paste -sd, -)

  log "Applying layout: ${count}x profile_id=${profile_id}"
  sudo nvidia-smi mig -i "${GPU_INDEX}" -cgi "${csv}" -C >/dev/null
}

verify_layout() {
  local expected="$1"
  local actual
  actual=$(nvidia-smi -L | grep -c "MIG" || true)
  log "MIG devices detected: ${actual}"
  if (( actual < expected )); then
    log "Expected at least ${expected} MIG devices, got ${actual}"
    exit 1
  fi
}

main() {
  need_sudo
  need_nvidia_smi
  assert_gpu_model

  local profile_name
  profile_name=$(detect_profile_name)
  log "Using MIG profile: ${profile_name}"

  enable_mig_mode
  reset_existing_layout

  local profile_id
  profile_id=$(find_profile_id "${profile_name}")
  if [[ -z "${profile_id}" ]]; then
    log "Could not find profile ID for '${profile_name}' on GPU ${GPU_INDEX}"
    nvidia-smi mig -i "${GPU_INDEX}" -lgip || true
    exit 1
  fi

  apply_layout "${profile_id}" "${MIG_INSTANCE_COUNT}"
  verify_layout "${MIG_INSTANCE_COUNT}"

  log "Done. MIG layout applied on GPU ${GPU_INDEX}."
}

main "$@"
