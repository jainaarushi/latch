# vLLM + llm-d K8s Starter

Reproducible local Kubernetes + NVIDIA + vLLM + llm-d setup for small-model testing on a single GPU node.

## Structure

- `scripts/setup_kubnamespace_vllm.sh`: Bootstrap host + k3s + NVIDIA plugin + deploy direct vLLM.
- `scripts/setup_llmd_tinyllama.sh`: Deploy llm-d inference-scheduling with TinyLlama decode.
- `scripts/run_synthetic_traffic.sh`: Run in-cluster synthetic traffic and print JSON summary.
- `scripts/run_llmd_traffic.sh`: Run synthetic traffic against llm-d inference gateway.
- `profiles/smoke.json`: Small direct vLLM validation profile.
- `profiles/load.json`: Direct vLLM load profile.
- `profiles/llmd-load.json`: llm-d gateway load profile.

## Quickstart (Direct vLLM)

```bash
# from the repository root
cd demo-2
bash scripts/setup_kubnamespace_vllm.sh
```

Verify deployment:

```bash
kubectl -n kubnamespace get deploy,pods,svc
```

Run smoke traffic:

```bash
bash scripts/run_synthetic_traffic.sh profiles/smoke.json
```

## Quickstart (llm-d on top of vLLM)

```bash
cd demo-2
bash scripts/setup_llmd_tinyllama.sh
bash scripts/run_llmd_traffic.sh
```

## Setup Script Options

Environment variables for `scripts/setup_kubnamespace_vllm.sh`:

- `NAMESPACE` (default `kubnamespace`)
- `MODEL` (default `TinyLlama/TinyLlama-1.1B-Chat-v1.0`)
- `REPLICAS` (default `1`)
- `MAX_MODEL_LEN` (default `512`)
- `GPU_MEMORY_UTILIZATION` (default `0.20`)
- `K3S_CHANNEL` (default `stable`)
- `KILL_LOCAL_VLLM` (default `false`)
- `LOCAL_VLLM_KILL_PATTERN` (default `vllm serve`) used only when `KILL_LOCAL_VLLM=true`
- `VLLM_IMAGE` (default `vllm/vllm-openai:nightly`)
- `VLLM_LD_LIBRARY_PATH` (default `/lib/x86_64-linux-gnu`)
- `VLLM_LD_PRELOAD` (default `/lib/x86_64-linux-gnu/libcuda.so.1`)

Environment variables for `scripts/setup_llmd_tinyllama.sh`:

- `NAMESPACE` (default `kubnamespace`)
- `RELEASE_NAME_POSTFIX` (default `inference-scheduling`)
- `MODEL` (default `TinyLlama/TinyLlama-1.1B-Chat-v1.0`)
- `MODEL_SIZE` (default `4Gi`)
- `DECODE_REPLICAS` (default `1`)
- `MAX_MODEL_LEN` (default `512`)
- `GPU_MEMORY_UTILIZATION` (default `0.30`)
- `LLMD_DIR` (default `$HOME/llm-d`)
- `DECODE_IMAGE` (default `vllm/vllm-openai:nightly`)
- `DECODE_LD_LIBRARY_PATH` (default `/lib/x86_64-linux-gnu`)
- `DECODE_LD_PRELOAD` (default `/lib/x86_64-linux-gnu/libcuda.so.1`)

## A100 Note

On this A100 setup, stable `vllm/vllm-openai` tags failed with CUDA compatibility errors. The working path uses:

- `vllm/vllm-openai:nightly`
- `LD_LIBRARY_PATH=/lib/x86_64-linux-gnu`
- `LD_PRELOAD=/lib/x86_64-linux-gnu/libcuda.so.1`

Those defaults are baked into both setup scripts and can be overridden with env vars.

## Traffic Profile Fields

All optional (defaults are built into the script):

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
- `traffic_node_name` (optional node pin for traffic pod)
