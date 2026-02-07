#!/usr/bin/env bash
set -euo pipefail

# Minimal fast checks for early-stage dev.
# Keep deterministic; no external services.

python -m py_compile $(git ls-files '*.py')
python -c "import latch; import control_plane"

echo "dev_check: OK"
