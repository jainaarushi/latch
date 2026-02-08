.PHONY: help all check demo smoke

PY ?= python3

help:
	@echo "Targets:"
	@echo "  make check   - run fast verification (scripts/dev_check.sh)"
	@echo "  make smoke   - run minimal SDK smoke demo"
	@echo "  make demo    - run the traffic-control demo"
	@echo "  make all     - run check + smoke + demo"

check:
	./scripts/dev_check.sh

smoke:
	$(PY) demo/minimal_sdk_smoke.py

demo:
	$(PY) demo/run_demo.py

all: check smoke demo
