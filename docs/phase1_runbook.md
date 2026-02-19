# Phase 1 Runbook

Official command sequence used to validate Phase 1.

## Commands

```bash
make doctor

NAMESPACE=latchverify REPLICAS=2 make up-vllm
NAMESPACE=latchverify make test-infer

NAMESPACE=latchverify RELEASE_POSTFIX=latchverify make up-llmd
NAMESPACE=latchverify SERVICE=infra-latchverify-inference-gateway-istio PORT=80 make test-infer

NAMESPACE=latchverify make status
NAMESPACE=latchverify RELEASE_POSTFIX=latchverify make backend-proof
```

## MIG Proof (Mode B)

```bash
NAMESPACE=latchverify make mig-check
```

Expected per vLLM pod output:
- `NVIDIA_VISIBLE_DEVICES=...`
- first lines from `nvidia-smi -L`
