#!/usr/bin/env bash
set -euo pipefail

# Minimal fast checks for early-stage dev.
# Keep deterministic; no external services.

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "$ROOT_DIR"

PYTHON_BIN="${VENV_PYTHON:-python3}"

$PYTHON_BIN -m py_compile $(git ls-files '*.py')
$PYTHON_BIN -c "import latch; import control_plane"

echo "dev_check: OK"
