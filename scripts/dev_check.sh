#!/usr/bin/env bash
set -euo pipefail

# Minimal fast checks for early-stage dev.
# Keep deterministic; no external services.

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "$ROOT_DIR"

PYTHON_BIN="${VENV_PYTHON:-python3}"

export PYTHONPYCACHEPREFIX="${PYTHONPYCACHEPREFIX:-$ROOT_DIR/.pycache}"
mkdir -p "$PYTHONPYCACHEPREFIX"

git ls-files -z -- '*.py' | xargs -0 -r "$PYTHON_BIN" -m py_compile
"$PYTHON_BIN" -c "import latch; import control_plane"

echo "dev_check: OK"
