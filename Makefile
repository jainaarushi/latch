.PHONY: help all check demo smoke bootstrap full-setup up up-vllm up-llmd test-infer doctor status down logs-routing

PY ?= python3
export PATH := $(HOME)/.local/bin:$(PATH)

help:
	@echo "Targets:"
	@echo "  make check   - run fast verification (scripts/dev_check.sh)"
	@echo "  make smoke   - run minimal SDK smoke demo"
	@echo "  make demo    - run the traffic-control demo"
	@echo "  make bootstrap - install required CLI tools (kubectl, helm, curl, jq)"
	@echo "  make full-setup - bootstrap + doctor + vLLM + llm-d + smoke tests"
	@echo "  make up      - deploy 2x vLLM pods + service in Kubernetes"
	@echo "  make up-vllm - same as make up (phase-1 naming)"
	@echo "  make up-llmd - deploy llm-d gateway+scheduler in front of vLLM"
	@echo "  make test-infer - run /v1/chat/completions smoke test"
	@echo "  make doctor  - cluster preflight checks (context, nodes, GPU/MIG, plugins)"
	@echo "  make status  - show namespace runtime resources"
	@echo "  make logs-routing - show gateway/scheduler/vLLM logs"
	@echo "  make down    - remove deployed vLLM + llm-d resources"
	@echo "  make all     - run check + smoke + demo"

check:
	./scripts/dev_check.sh

smoke:
	$(PY) demo/minimal_sdk_smoke.py

demo:
	$(PY) demo/run_demo.py

bootstrap:
	./scripts/bootstrap_prereqs.sh

full-setup:
	./scripts/full_setup.sh

up:
	./scripts/up.sh

up-vllm: up

up-llmd:
	./scripts/up_llmd.sh

test-infer:
	./scripts/test_infer.sh

doctor:
	./scripts/doctor.sh

status:
	./scripts/status.sh

logs-routing:
	./scripts/logs_routing.sh

down:
	./scripts/down.sh

all: check smoke demo
