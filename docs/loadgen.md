# Load Generator (Phase 3.1)

Files:

- `tools/loadgen/loadgen.py`
- `scripts/run_load.sh`

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
