#!/usr/bin/env bash
set -euo pipefail

python -m py_compile \
  control_plane/policy_engine.py \
  metrics/signals.py \
  runtime/gateway.py \
  latch/types.py

echo "dev_check: OK"
