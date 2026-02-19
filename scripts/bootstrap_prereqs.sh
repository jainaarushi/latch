#!/usr/bin/env bash
set -euo pipefail

HELM_VERSION=${HELM_VERSION:-v3.18.4}
JQ_VERSION=${JQ_VERSION:-1.7.1}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

log() {
  echo "[bootstrap] $*"
}

detect_os() {
  case "$(uname -s)" in
    Linux) echo linux ;;
    Darwin) echo darwin ;;
    *) log "Unsupported OS: $(uname -s)"; exit 1 ;;
  esac
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    *) log "Unsupported architecture: $(uname -m)"; exit 1 ;;
  esac
}

select_bin_dir() {
  if [[ -w /usr/local/bin ]]; then
    echo /usr/local/bin
  else
    mkdir -p "$HOME/.local/bin"
    echo "$HOME/.local/bin"
  fi
}

install_binary() {
  local src="$1"
  local dst="$2"
  install -m 0755 "${src}" "${dst}"
}

install_kubectl() {
  local os arch version bin_dir
  os=$(detect_os)
  arch=$(detect_arch)
  bin_dir=$(select_bin_dir)
  version="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"

  log "Installing kubectl ${version}..."
  curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${version}/bin/${os}/${arch}/kubectl"
  chmod +x /tmp/kubectl
  install_binary /tmp/kubectl "${bin_dir}/kubectl"
}

install_helm() {
  local os arch bin_dir tarball
  os=$(detect_os)
  arch=$(detect_arch)
  bin_dir=$(select_bin_dir)
  tarball="/tmp/helm-${HELM_VERSION}-${os}-${arch}.tar.gz"

  log "Installing helm ${HELM_VERSION}..."
  curl -fsSLo "${tarball}" "https://get.helm.sh/helm-${HELM_VERSION}-${os}-${arch}.tar.gz"
  tar -xzf "${tarball}" -C /tmp
  install_binary "/tmp/${os}-${arch}/helm" "${bin_dir}/helm"
}

install_jq() {
  local os arch bin_dir jq_asset
  os=$(detect_os)
  arch=$(detect_arch)
  bin_dir=$(select_bin_dir)

  if [[ "${os}" == "linux" && "${arch}" == "amd64" ]]; then
    jq_asset="jq-linux-amd64"
  elif [[ "${os}" == "linux" && "${arch}" == "arm64" ]]; then
    jq_asset="jq-linux-arm64"
  elif [[ "${os}" == "darwin" && "${arch}" == "amd64" ]]; then
    jq_asset="jq-macos-amd64"
  elif [[ "${os}" == "darwin" && "${arch}" == "arm64" ]]; then
    jq_asset="jq-macos-arm64"
  else
    log "Unsupported OS/arch for jq: ${os}/${arch}"
    exit 1
  fi

  log "Installing jq ${JQ_VERSION}..."
  curl -fsSLo /tmp/jq "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/${jq_asset}"
  chmod +x /tmp/jq
  install_binary /tmp/jq "${bin_dir}/jq"
}

maybe_warn_path() {
  if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && [[ -x "$HOME/.local/bin/kubectl" || -x "$HOME/.local/bin/helm" || -x "$HOME/.local/bin/jq" ]]; then
    log "Add to PATH if needed: export PATH=\"$HOME/.local/bin:$PATH\""
  fi
}

main() {
  if ! need_cmd curl; then
    log "curl is required for bootstrap; install curl first."
    exit 1
  fi

  log "Checking prerequisites..."

  need_cmd kubectl || install_kubectl
  need_cmd helm || install_helm
  need_cmd jq || install_jq

  maybe_warn_path

  log "kubectl: $(kubectl version --client 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')"
  log "helm: $(helm version --short 2>/dev/null || true)"
  log "jq: $(jq --version 2>/dev/null || true)"
  log "Done."
}

main "$@"
