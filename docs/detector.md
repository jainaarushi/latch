# Detector Rules Guide

This document explains how to tune deterministic incident detection in:

- `services/latch-detector/rules.yaml`

The detector emits an `IMBALANCE` incident only when both conditions are true:

1. QPS skew breach: `max(replica_qps) / min(replica_qps) > qps_skew_threshold`
2. TTFT regression breach: global `ttft_p95` increase vs rolling baseline is greater than `ttft_p95_increase_pct_threshold`

The skew + TTFT breach must persist for `sustained_seconds`.

## Current Rule Fields

- `enabled`: Enable/disable detector rule.
- `min_replicas`: Minimum replicas required before evaluating imbalance.
- `qps_skew_threshold`: Skew ratio threshold. Example: `3.0` means 3x.
- `sustained_seconds`: Continuous breach duration required before incident creation.
- `ttft_p95_increase_pct_threshold`: Required percent increase over baseline TTFT p95.
- `baseline_window_seconds`: Rolling baseline window size.
- `min_qps_floor`: Ignore near-idle replicas below this QPS when computing skew.

## Tuning Recommendations

Start conservative, then tighten:

- Initial safe values for noisy test clusters:
  - `qps_skew_threshold: 4.0`
  - `sustained_seconds: 45`
  - `ttft_p95_increase_pct_threshold: 40`
- More sensitive values for stable environments:
  - `qps_skew_threshold: 2.5`
  - `sustained_seconds: 20`
  - `ttft_p95_increase_pct_threshold: 20`

Use `min_qps_floor` to avoid false positives at very low traffic.

## Apply Rule Changes

After editing `services/latch-detector/rules.yaml`, redeploy detector:

```bash
NAMESPACE=latchverify make up-latch-detector
```

Then validate:

```bash
NAMESPACE=latchverify make incidents
```

## Notes for Future AI Detector

The current design keeps policy in `rules.yaml` and evaluation logic in `services/latch-detector/main.py`.

That separation makes it straightforward to later:

- keep `/incidents` response schema stable
- replace deterministic thresholding with a model-driven scorer
- run hybrid mode (model recommendation + deterministic safety guardrails)
