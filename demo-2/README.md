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
