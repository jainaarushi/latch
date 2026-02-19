.PHONY: help all check demo smoke bootstrap full-setup demo-phase1 mig-check backend-proof metrics-live metrics-live-traffic run-load enable-imbalance disable-imbalance up-latch-metrics state up up-vllm up-llmd test-infer doctor status down logs-routing

PY ?= python3
export PATH := $(HOME)/.local/bin:$(PATH)

help:
	@echo "Targets:"
	@echo "  make check   - run fast verification (scripts/dev_check.sh)"
	@echo "  make smoke   - run minimal SDK smoke demo"
	@echo "  make demo    - run the traffic-control demo"
	@echo "  make bootstrap - install required CLI tools (kubectl, helm, curl, jq)"
	@echo "  make full-setup - bootstrap + doctor + vLLM + llm-d + smoke tests"
	@echo "  make demo-phase1 - run official Phase 1 happy-path sequence"
	@echo "  make mig-check - print MIG device mapping proof per vLLM pod"
	@echo "  make backend-proof - prove llm-d backend selection using per-pod vLLM counters"
	@echo "  make metrics-live - print live per-pod runtime metrics table"
	@echo "  make metrics-live-traffic - metrics-live with built-in background traffic"
	@echo "  make run-load - run load generator (steady/burst, mixed prompts)"
	@echo "  make enable-imbalance - inject replica imbalance incident"
	@echo "  make disable-imbalance - revert replica imbalance incident"
	@echo "  make up-latch-metrics - deploy latch metrics normalizer service"
	@echo "  make state - fetch normalized JSON state from latch-metrics"
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

demo-phase1:
	@NAMESPACE=$${NAMESPACE:-latchverify}; \
	RELEASE_POSTFIX=$${RELEASE_POSTFIX:-$$NAMESPACE}; \
	REPLICAS=$${REPLICAS:-2}; \
	echo "[phase1] Step 1/6: doctor"; \
	NAMESPACE=$$NAMESPACE ./scripts/doctor.sh; \
	echo "[phase1] Step 2/6: up-vllm"; \
	NAMESPACE=$$NAMESPACE REPLICAS=$$REPLICAS ./scripts/up.sh; \
	echo "[phase1] Step 3/6: direct test"; \
	NAMESPACE=$$NAMESPACE ./scripts/test_infer.sh; \
	echo "[phase1] Step 4/6: up-llmd"; \
	NAMESPACE=$$NAMESPACE RELEASE_POSTFIX=$$RELEASE_POSTFIX ./scripts/up_llmd.sh; \
	echo "[phase1] Step 5/6: llm-d test"; \
	NAMESPACE=$$NAMESPACE SERVICE=infra-$$RELEASE_POSTFIX-inference-gateway-istio PORT=80 ./scripts/test_infer.sh; \
	echo "[phase1] Step 6/6: status"; \
	NAMESPACE=$$NAMESPACE ./scripts/status.sh

mig-check:
	./scripts/mig_check.sh

backend-proof:
	./scripts/backend_proof.sh

metrics-live:
	./scripts/metrics_live.sh

metrics-live-traffic:
	GENERATE_TRAFFIC=true ./scripts/metrics_live.sh

run-load:
	./scripts/run_load.sh

enable-imbalance:
	./scripts/enable_imbalance.sh

disable-imbalance:
	./scripts/disable_imbalance.sh

up-latch-metrics:
	./scripts/up_latch_metrics.sh

state:
	./scripts/state.sh

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
