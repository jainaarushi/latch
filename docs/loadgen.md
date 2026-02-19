# Load Generator (Phase 3.1)

Files:

- `tools/loadgen/loadgen.py`
- `scripts/run_load.sh`
- `scripts/compare_scheduler_modes.sh`

## Modes

- `steady`: fixed request rate for the full run
- `burst`: baseline rate with a high-rate burst window
- mixed prompt lengths: controlled by `LONG_PROMPT_RATIO`, `SHORT_USER_TOKENS`, `LONG_USER_TOKENS`

## Quick usage

Steady load:

```bash
NAMESPACE=phase1full MODE=steady DURATION_S=60 CONCURRENCY=16 STEADY_RPS=12 make run-load
```

Burst load:

```bash
NAMESPACE=phase1full MODE=burst DURATION_S=60 CONCURRENCY=16 STEADY_RPS=8 BURST_RPS=50 BURST_AFTER_S=10 BURST_FOR_S=15 make run-load
```

## Output summary

The tool prints JSON with:

- `qps`
- `ok` / `errors`
- `latency_s` (`mean`, `p50`, `p95`, `p99`, `min`, `max`)
- `error_breakdown`

## Scheduler comparison (optimal-path validation)

Run both traffic shapes back-to-back:

- locality-friendly (`UNIQUE_PROMPTS=0`)
- diverse prompts (`UNIQUE_PROMPTS=1`)

Command:

```bash
NAMESPACE=kubnamespace SERVICE=infra-kubnamespace-inference-gateway-istio MODEL=tinyllama make scheduler-compare
```

The comparison prints, for each mode:

- load summary (`qps`, `errors`, `p95`, `p99`)
- per-pod `backend_proof` deltas
- per-pod `state` snapshot (`qps`, `gpu_util`)

This is for validating scheduler behavior, not fairness. Skew can be expected in locality-friendly mode.
