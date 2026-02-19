# vLLM + llm-d K8s Starter (A100)

Reproducible local Kubernetes + NVIDIA + vLLM + llm-d setup for A100.

## Structure

- `scripts/setup_kubnamespace_vllm.sh`: bootstrap host + k3s + NVIDIA plugin + deploy direct vLLM.
- `scripts/setup_a100_mig_3x2g10gb.sh`: enable MIG and carve `3 x 2g.10gb` slices for multi-pod decode.
- `scripts/setup_llmd_tinyllama.sh`: deploy llm-d inference-scheduling with TinyLlama decode.
- `scripts/run_synthetic_traffic.sh`: run in-cluster synthetic traffic and print JSON summary.
- `scripts/run_llmd_traffic.sh`: run synthetic traffic against llm-d inference gateway.
- `profiles/smoke.json`: small direct vLLM validation profile.
- `profiles/load.json`: direct vLLM load profile.
- `profiles/llmd-load.json`: llm-d gateway load profile.

## Quickstart (A100 + MIG + llm-d)

```bash
cd demo-2

# 1) Base host + direct vLLM deployment (single pod)
bash scripts/setup_kubnamespace_vllm.sh

# 2) Enable MIG and create 3 slices (2g.10gb each)
# If MIG was newly enabled, script may reboot once. Run it again after reboot.
bash scripts/setup_a100_mig_3x2g10gb.sh

# 3) Deploy llm-d stack (decode patches + gateway prereqs included)
bash scripts/setup_llmd_tinyllama.sh

# 4) Scale decode to 3 pods (one pod per MIG slice)
kubectl -n kubnamespace scale deploy/ms-inference-scheduling-llm-d-modelservice-decode --replicas=3
kubectl -n kubnamespace rollout status deploy/ms-inference-scheduling-llm-d-modelservice-decode --timeout=1800s

# 5) Run traffic
bash scripts/run_llmd_traffic.sh
```

## Key Defaults

`setup_kubnamespace_vllm.sh`
- `NAMESPACE=kubnamespace`
- `MODEL=TinyLlama/TinyLlama-1.1B-Chat-v1.0`
- `REPLICAS=1`
- `VLLM_IMAGE=vllm/vllm-openai:nightly`
- `VLLM_LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu`
- `VLLM_LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libcuda.so.1`

`setup_a100_mig_3x2g10gb.sh`
- `GPU_INDEX=0`
- `MIG_PROFILE_ID=14` (A100 `2g.10gb`)
- `MIG_INSTANCES=3`
- `AUTO_REBOOT=true`

`setup_llmd_tinyllama.sh`
- `NAMESPACE=kubnamespace`
- `RELEASE_NAME_POSTFIX=inference-scheduling`
- `MODEL=TinyLlama/TinyLlama-1.1B-Chat-v1.0`
- `DECODE_REPLICAS=1` (scale to 3 after MIG setup)
- `DECODE_LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu`
- `DECODE_LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libcuda.so.1`
- `ENABLE_GATEWAY_PREREQS=true`

## Repro Notes

- `:nightly` is floating. For strict reproducibility, pin to digest in both deployments:
  - `VLLM_IMAGE=vllm/vllm-openai@sha256:...`
  - `DECODE_IMAGE=vllm/vllm-openai@sha256:...`
- Decode deployment is patched for stability:
  - `runtimeClassName: nvidia`
  - `enableServiceLinks: false` (prevents bad `VLLM_PORT=tcp://...`)
  - rolling strategy `maxSurge=0,maxUnavailable=1` for single-node GPU constraints.

## Traffic Profile Fields

All optional (defaults built into script):
- `namespace`
- `gateway_uri`
- `model`
- `total_requests`
- `concurrency`
- `stream`
- `max_tokens`
- `long_system_tokens`
- `long_user_tokens`
- `start_spacing_ms`
- `jitter_ms`
- `timeout_s`
- `traffic_node_name`
