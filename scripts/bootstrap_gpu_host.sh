#!/usr/bin/env bash
set -euo pipefail

DRIVER_PACKAGE=${DRIVER_PACKAGE:-nvidia-driver-550}
FORCE_DRIVER_INSTALL=${FORCE_DRIVER_INSTALL:-false}

log() {
  echo "[bootstrap-gpu-host] $*"
}

need_sudo() {
  if ! command -v sudo >/dev/null 2>&1; then
    log "sudo is required"
    exit 1
  fi
}

require_linux() {
  if [[ "$(uname -s)" != "Linux" ]]; then
    log "This script supports Linux only."
    exit 1
  fi
}

install_driver_if_needed() {
  if command -v nvidia-smi >/dev/null 2>&1 && [[ "${FORCE_DRIVER_INSTALL}" != "true" ]]; then
    log "nvidia-smi already present; skipping driver install."
    return
  fi

  log "Installing NVIDIA driver package: ${DRIVER_PACKAGE}"
  sudo apt-get update
  sudo apt-get install -y "${DRIVER_PACKAGE}"
}

install_toolkit_repo() {
  log "Installing NVIDIA container toolkit repository"
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

  curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
}

main() {
  require_linux
  need_sudo

  log "Installing base packages"
  sudo apt-get update
  sudo apt-get install -y curl ca-certificates gnupg lsb-release pciutils

  install_driver_if_needed
  install_toolkit_repo

  log "Installing nvidia-container-toolkit"
  sudo apt-get update
  sudo apt-get install -y nvidia-container-toolkit

  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    log "nvidia-smi check: OK"
    nvidia-smi -L || true
  else
    log "nvidia-smi is not ready yet. A reboot may be required after driver install."
    log "After reboot, rerun: ./scripts/bootstrap_k8s_gpu.sh"
    exit 2
  fi

  log "Done. Host GPU prerequisites are installed."
}

main "$@"
