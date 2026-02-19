# Incident Scenarios (Phase 3.2)

Files:

- `deploy/scenarios/imbalance.yaml`
- `scripts/enable_imbalance.sh`
- `scripts/disable_imbalance.sh`

## Replica imbalance scenario

This scenario injects route skew by endpoint membership:

- One vLLM pod is kept with `llm-d.ai/inference-serving=true`
- Other vLLM pods are set to `llm-d.ai/inference-serving=false`
- llm-d scheduler then sends backend traffic to the kept pod, creating visible imbalance

Enable:

```bash
NAMESPACE=phase1full make enable-imbalance
```

Disable (restore all pods):

```bash
NAMESPACE=phase1full make disable-imbalance
```

Validate with:

```bash
NAMESPACE=phase1full make state
NAMESPACE=phase1full make metrics-live-traffic
```

For timeline evidence during/after injection:

```bash
NAMESPACE=phase1full INTERVAL_S=2 DURATION_S=120 make state-live
NAMESPACE=phase1full make incidents
NAMESPACE=phase1full make diagnose INC=<incident_id>
```

Expected effect:

- one replica shows higher `qps` / queue / in-flight
- other replicas show low or near-zero load
