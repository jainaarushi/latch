# vLLM K8s Starter

Reproducible local Kubernetes + NVIDIA + vLLM setup and synthetic traffic runner.

## Structure

- `scripts/setup_kubnamespace_vllm.sh`: Bootstrap host + k3s + GPU plugin + deploy vLLM.
- `scripts/run_synthetic_traffic.sh`: Run in-cluster synthetic traffic and print JSON summary.
- `profiles/smoke.json`: Small validation profile.
- `profiles/load.json`: Default load profile.

## Quickstart

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

Run load traffic:

```bash
bash scripts/run_synthetic_traffic.sh profiles/load.json
```

## Setup Script Options

Environment variables for `scripts/setup_kubnamespace_vllm.sh`:

- `NAMESPACE` (default `kubnamespace`)
- `MODEL` (default `TinyLlama/TinyLlama-1.1B-Chat-v1.0`)
- `REPLICAS` (default `2`)
- `MAX_MODEL_LEN` (default `512`)
- `GPU_MEMORY_UTILIZATION` (default `0.20`)
- `K3S_CHANNEL` (default `stable`)
- `KILL_LOCAL_VLLM` (default `false`)
- `LOCAL_VLLM_KILL_PATTERN` (default `vllm serve`) used only when `KILL_LOCAL_VLLM=true`

Example:

```bash
NAMESPACE=kubnamespace \
REPLICAS=2 \
MAX_MODEL_LEN=512 \
GPU_MEMORY_UTILIZATION=0.20 \
bash scripts/setup_kubnamespace_vllm.sh
```

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

## llm-d (TinyLlama) Setup

This deploys llm-d inference scheduling on top of your Kubernetes cluster using TinyLlama only.

```bash
# from repo root
cd demo-2
bash scripts/setup_llmd_tinyllama.sh
```

Important defaults for low footprint:

- Single decode replica (`DECODE_REPLICAS=1`)
- TinyLlama model (`TinyLlama/TinyLlama-1.1B-Chat-v1.0`)
- No Prometheus CRD objects (`ServiceMonitor`/`PodMonitor` disabled)

Environment variables:

- `NAMESPACE` (default `kubnamespace`)
- `LLMD_DIR` (default `/home/ubuntu/llm-d`)
- `LLMD_REPO` (default `git@github.com:llm-d/llm-d.git`)
- `MODEL` (default `TinyLlama/TinyLlama-1.1B-Chat-v1.0`)
- `MAX_MODEL_LEN` (default `512`)
- `GPU_MEMORY_UTILIZATION` (default `0.30`)
- `DECODE_REPLICAS` (default `1`)

## Run Traffic Through llm-d Gateway

Using static profile:

```bash
bash scripts/run_synthetic_traffic.sh profiles/llmd-load.json
```

Using dynamic wrapper (builds profile from env):

```bash
bash scripts/run_llmd_traffic.sh
```

Optional wrapper env vars:

- `NAMESPACE`
- `RELEASE_NAME_POSTFIX` (default `inference-scheduling`)
- `GATEWAY_URI` (overrides computed URI)
- `MODEL`
- `TOTAL_REQUESTS`
- `CONCURRENCY`
- `STREAM`
- `MAX_TOKENS`
- `LONG_SYSTEM_TOKENS`
- `LONG_USER_TOKENS`
- `START_SPACING_MS`
- `JITTER_MS`
- `TIMEOUT_S`
