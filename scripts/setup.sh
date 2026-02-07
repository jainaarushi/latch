#!/usr/bin/env bash
set -euo pipefail

# Latch setup (CPU-only, SDK-first)
# Usage: ./scripts/setup.sh

echo "==> Setting up Latch (CPU-only, SDK-first)"

# 1. Check Python version
PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
REQUIRED_MIN="3.10"

if [[ "$(printf '%s\n' "$REQUIRED_MIN" "$PYTHON_VERSION" | sort -V | head -n1)" != "$REQUIRED_MIN" ]]; then
  echo "ERROR: Python >= $REQUIRED_MIN required. Found $PYTHON_VERSION"
  exit 1
fi

echo "OK: Python $PYTHON_VERSION detected"

# 2. Create virtual environment
if [ ! -d ".venv" ]; then
  echo "==> Creating virtual environment (.venv)"
  python3 -m venv .venv
else
  echo "==> Virtual environment already exists"
fi

# 3. Activate venv
# shellcheck disable=SC1091
source .venv/bin/activate

# 4. Upgrade pip
echo "==> Upgrading pip"
pip install --upgrade pip >/dev/null

# 5. Install dependencies
echo "==> Installing dependencies"
pip install \
  pyyaml \
  click \
  pytest \
  matplotlib \
  fastapi \
  uvicorn \
  >/dev/null

# 6. Editable install (if latch is a package)
if [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
  echo "==> Installing Latch in editable mode"
  pip install -e . >/dev/null
fi

# 7. Sanity checks
echo "==> Running sanity checks"

python - <<'EOF_PY'
import sys
print("Python:", sys.version)
EOF_PY

if [ -d "latch" ] || [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
  python - <<'EOF_PY'
try:
    import latch
    print("Latch import: OK")
except Exception as e:
    print("Latch import failed:", e)
    raise SystemExit(1)
EOF_PY
else
  echo "Latch import skipped (SDK not yet scaffolded)"
fi

if [ -d "tests" ]; then
  pytest -q || echo "WARN: Tests failed (ok early on)"
fi

echo ""
echo "Setup complete"
echo ""
echo "Next steps:"
echo "  source .venv/bin/activate"
echo "  latch demo slo_spike"
