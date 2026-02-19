# LLM Intent Control Plane

This repository demonstrates a reference implementation of an intent-based control plane for LLM inference systems.

A reference implementation of an intent-aware control loop that sits in the inference path and stabilizes behavior under changing traffic.

## What problem does this solve?

LLM systems break in production because traffic, prompts, and usage patterns change continuously. Static configurations and observability are not enough.

This project shows how application intent (latency, cost, priority) can be translated into real-time control decisions that stabilize LLM behavior under load.

## LATCH Quickstart

This section documents the core LATCH runtime flow for Kubernetes:

- vLLM replicas on NVIDIA GPU/MIG
- llm-d gateway + scheduler in front of vLLM
- Prometheus + DCGM exporter metrics scraping
- live per-pod metric printing
- `latch-metrics` normalizer service with `GET /state`
- deterministic incident detector service with `GET /incidents`
- evidence-based diagnoser service with `GET /incidents/{id}/diagnosis`

Run `make help` to list all targets.

### 1) Prereqs and cluster checks

```bash
make bootstrap
make doctor
```

### 2) Phase 1: Inference stack

```bash
NAMESPACE=latchverify REPLICAS=2 make up-vllm
NAMESPACE=latchverify make test-infer

NAMESPACE=latchverify RELEASE_POSTFIX=latchverify make up-llmd
NAMESPACE=latchverify SERVICE=infra-latchverify-inference-gateway-istio PORT=80 make test-infer

NAMESPACE=latchverify make status
```

One-command happy path:

```bash
NAMESPACE=latchverify RELEASE_POSTFIX=latchverify REPLICAS=2 make demo-phase1
```

### 3) Routing and MIG proof commands

Backend routing proof through llm-d (per-pod request counter deltas):

```bash
NAMESPACE=latchverify RELEASE_POSTFIX=latchverify make backend-proof
```

MIG UUID proof per vLLM pod:

```bash
NAMESPACE=latchverify make mig-check
```

### 4) Phase 2: Observability

Deploy observability components:

```bash
kubectl apply -f deploy/observability/dcgm-exporter.yaml
kubectl apply -f deploy/observability/prometheus.yaml
```

Live per-pod metrics table:

```bash
NAMESPACE=latchverify make metrics-live
```

Live per-pod metrics with built-in traffic generation:

```bash
NAMESPACE=latchverify INTERVAL_S=2 ITERATIONS=20 make metrics-live-traffic
```

### 5) Phase 2: Latch metrics normalizer (`/state`)

Deploy normalizer service:

```bash
NAMESPACE=latchverify make up-latch-metrics
```

Fetch normalized state JSON:

```bash
NAMESPACE=latchverify make state
```

Expected schema:

```json
{
  "timestamp": "2026-02-19T06:45:53Z",
  "global": {
    "qps": 1.234,
    "ttft_p95_ms": 19.5,
    "latency_p95_ms": 285.0
  },
  "replicas": [
    {
      "name": "vllm-...",
      "qps": 0.411,
      "in_flight": 1.0,
      "ttft_p95_ms": 20.2,
      "latency_p95_ms": 290.0,
      "gpu_util": 35.0,
      "gpu_mem_mb": 6605.0
    }
  ]
}
```

For detailed metric names and PromQL, see `docs/metrics.md`.
For Phase 1 command sequence, see `docs/phase1_runbook.md`.

### 6) Phase 3: Traffic generator + incident injection

Run reproducible load (steady/burst, short/long prompts):

```bash
NAMESPACE=latchverify RELEASE_POSTFIX=latchverify \
SERVICE=infra-latchverify-inference-gateway-istio PORT=80 \
REQUESTS=120 CONCURRENCY=12 MODE=steady MIXED_PROMPTS=true make run-load
```

Inject skewed routing (replica imbalance scenario):

```bash
NAMESPACE=latchverify make enable-imbalance
```

Revert skew and return to balanced routing:

```bash
NAMESPACE=latchverify make disable-imbalance
```

Watch normalized state while load is running:

```bash
NAMESPACE=latchverify make state
```

More details:
- `docs/loadgen.md`
- `docs/scenarios.md`

### 7) Phase 4/7: Deterministic detection (`/incidents`)

Deploy detector service:

```bash
NAMESPACE=latchverify make up-latch-detector
```

Print active incidents:

```bash
NAMESPACE=latchverify make incidents
```

Expected output shape:

```text
[detector] Active incidents: 1
- id=inc_0241
  type=IMBALANCE
  severity=HIGH
  started_at=2026-02-18T20:12:07Z
  evidence:
    qps_skew=8.0x (threshold=3.0x)
    ttft_p95_increase=+92% (threshold=+30%)
```

Detector rule logic:
- Triggers when `max(replica_qps) / min(replica_qps) > X` for `Y` seconds.
- Also requires `ttft_p95` increase by `Z%` from baseline.
- Emits incident object with type, severity, started time, and evidence.

Rule config is externalized in `services/latch-detector/rules.yaml` so you can later replace this deterministic policy with an AI model while keeping the same detector service API and deployment wiring.

Detector tuning guide:
- `docs/detector.md`

### 8) Phase 5: Diagnosis (`/incidents/{id}/diagnosis`)

Deploy diagnoser:

```bash
NAMESPACE=latchverify make up-latch-diagnoser
```

Use deterministic mode (default):

```bash
NAMESPACE=latchverify DIAGNOSIS_MODE=deterministic make up-latch-diagnoser
```

Enable LLM formatting mode (with deterministic fallback):

```bash
NAMESPACE=latchverify DIAGNOSIS_MODE=llm \
LLM_SUMMARIZER_URL=http://your-summarizer.your-ns.svc.cluster.local/summarize \
make up-latch-diagnoser
```

Run diagnosis:

```bash
NAMESPACE=latchverify make diagnose INC=inc_0241
```

Expected output shape:

```text
[diagnosis] Incident inc_0241
Root cause: Traffic routing skew is overloading a single replica.
Confidence: 0.86

Evidence:
- vllm-0 qps=9.7 vs vllm-1 qps=1.2 vs vllm-2 qps=1.2
- vllm-0 queue=14 vs vllm-1 queue=0 vs vllm-2 queue=0
- Global TTFT p95 increased 280ms -> 520ms (+92%)

Recommendation:
- Switch to load-aware routing (or reset weights to 34/33/33)
Risk: Low (config-only change, reversible)
Rollback: restore previous routing weights
```

Guardrails:
- narrative formatter only uses diagnoser facts (no hallucinated facts)
- includes `Sources` referencing evidence field names
- details in `docs/safety.md`

## Important File Structure (Quick Map)

```text
.
├── Makefile                               # Primary interface: up/test/observe/load/scenario targets
├── scripts/
│   ├── up.sh                              # Deploy vLLM replicas + service
│   ├── up_llmd.sh                         # Deploy llm-d gateway/scheduler in front of vLLM
│   ├── test_infer.sh                      # OpenAI chat-completions smoke test
│   ├── run_load.sh                        # Phase 3 synthetic traffic runner
│   ├── enable_imbalance.sh                # Inject replica imbalance
│   ├── disable_imbalance.sh               # Revert imbalance
│   ├── metrics_live.sh                    # Live per-pod runtime metrics view
│   ├── up_latch_metrics.sh                # Deploy latch-metrics normalizer service
│   ├── state.sh                           # Query normalized GET /state JSON
│   ├── up_latch_detector.sh               # Deploy latch-detector service
│   ├── incidents.sh                       # Query and print active incidents
│   ├── up_latch_diagnoser.sh              # Deploy latch-diagnoser service
│   └── diagnose.sh                        # Query incident diagnosis output
├── deploy/
│   ├── vllm/deployment.yaml               # vLLM K8s deployment/service spec
│   ├── llmd/httproute.yaml                # Routing into llm-d entrypoint
│   ├── scenarios/imbalance.yaml           # Route-weight skew scenario manifest
│   ├── latch-detector/deployment.yaml     # Latch detector deployment/service
│   └── latch-diagnoser/deployment.yaml    # Latch diagnoser deployment/service
├── services/latch-metrics/main.py         # Normalized cluster-state API implementation
├── services/latch-detector/
│   ├── main.py                            # Deterministic incident detector API
│   └── rules.yaml                         # Rule thresholds (AI-ready swap point)
├── services/latch-diagnoser/
│   ├── main.py                            # Diagnosis endpoint with root-cause logic
│   ├── llm_summarizer.py                  # deterministic|llm narrative mode with safe fallback
│   └── templates/imbalance.md             # Human-readable diagnosis template
├── tools/loadgen/loadgen.py               # Load generation engine (steady/burst/mixed prompts)
└── docs/
    ├── phase1_runbook.md                  # Verified Phase 1 command sequence
    ├── metrics.md                         # Metrics definitions and PromQL
    ├── loadgen.md                         # Load generator usage
    ├── scenarios.md                       # Incident scenario workflow
    ├── detector.md                        # Detector rule tuning guide
    └── safety.md                          # Guardrails for diagnosis narrative
```


## Longer-Term Product Diagram (Not MVP)

This is the eventual product shape. The MVP in this repo focuses on the request-path control loop (signals -> decisions -> actions -> verification) and intentionally skips dashboards/tenancy/auth and real infra integrations.

```
CONTROL PLANE (LATCH)

+-------------------------------------------------------------------------+
|                      PARENT BRAIN (ORCHESTRATOR)                        |
|  - Multi-objective controller                                           |
|  - Chooses what to optimize right now                                   |
|  - Arbitrates latency vs cost vs fairness                               |
+------------------------------+------------------------------+-----------+
                               | Business intent              | Objectives + constraints
                               v                              v

+-------------------------------+   +--------------------------------------+
| AGENT 1: Policy / Business SLO|   | AGENT 2: Performance Agent           |
|  - P99 / TTFT targets         |   |  - Diagnoses root cause              |
|  - Cost constraints           |   |    - Queuing                         |
|  - Tiering / fairness         |   |    - Long prompts                    |
|  - Guardrails                 |   |    - Bad batching                    |
|                               |   |    - Prefill / decode                |
|                               |   |    - Memory pressure                 |
|                               |   |  - Executes runtime knobs            |
|                               |   |    - Routing rules                   |
|                               |   |    - Batch window                    |
|                               |   |    - Autoscaling hints               |
|                               |   |    - Variant weights                 |
|                               |   |    - Config changes                  |
+-------------------------------+   +--------------------+-----------------+
                                                     | Evidence
                                                     v

+-------------------------------------------------------------------------+
| AGENT 3: Dashboard / Analytics                                          |
|  - Unified perf view                                                    |
|  - Model / tenant metrics                                               |
|  - Action history                                                       |
|  - "Why this happened"                                                 |
|  - Trust & auditability                                                 |
+-------------------------------------------------------------------------+
                               |
                               | Feedback
                               v

                 ^ Telemetry / Signals
                 | (P99, TTFT, GPU util, queues, batch size,
                 |  prompt length, KV cache hit rate, cost)
                 |
+-------------------------------------------------------------------------+
| DATA PLANE (EXECUTION)                                                  |
|  Client Requests -> API Gateway / Router -> Inference Engines -> GPUs    |
|  (llm-d, vLLM, Triton)                                                  |
+-------------------------------------------------------------------------+

                 +---- Continuous Closed-Loop Control --------------------+
```

### Legend (What Each Box Means)

- `Parent brain`: multi-objective controller that continuously decides what to optimize and which sub-agent gets to act.
- `Agent 1 (Policy / Business SLO agent)`: translates business goals into concrete targets and constraints (example: "P99 < 2.5s for paid tier, keep GPU $/1k tokens under X, protect fairness across tenants").
- `Agent 2 (Performance / Runtime tuning agent)`: diagnoses why latency is bad and executes runtime knob changes (routing, scheduling, batching, autoscaling, config).
- `Agent 3 (Dashboard / Analytics agent)`: observability UX and the evidence layer Agent 2 uses (plus explanation/traceability for performance engineer).

## What is implemented

- Intent schema
- Policy-based decision engine
- Runtime request interception
- Closed-loop feedback verification
- Traffic and latency simulation
  ## Architecture

```
          ┌───────────────┐
Request → │ Control Layer │ → Infra Hints → Runtime
          └───────────────┘
                 ↑
            Feedback Loop
                 ↑
              Signals
```

## MVP non-goals

- No dashboards or observability UI
- No auth or tenancy
- No real llm-d integration
- No full agent framework integration
- No vector DB / RAG

## What is intentionally mocked

- GPUs
- Model servers
- Autoscaling
- Real LLMs

## Goal

Demonstrate closed-loop control, not model quality.

MVP goal: demonstrate closed-loop control, not production completeness.
