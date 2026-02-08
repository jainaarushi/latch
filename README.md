# LLM Intent Control Plane

This repository demonstrates a reference implementation of an intent-based control plane for LLM inference systems.

A reference implementation of an intent-aware control loop that sits in the inference path and stabilizes behavior under changing traffic.

## What problem does this solve?

LLM systems break in production because traffic, prompts, and usage patterns change continuously. Static configurations and observability are not enough.

This project shows how application intent (latency, cost, priority) can be translated into real-time control decisions that stabilize LLM behavior under load.

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

User Request
-> Control Layer (this repo)
-> Inference Infrastructure (simulated llm-d)
-> Model Server

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
- `Agent 3 (Dashboard / Analytics agent)`: observability UX and the evidence layer Agent 2 uses (plus explanation/traceability for humans).

## What is implemented

- Intent schema
- Policy-based decision engine
- Runtime request interception
- Closed-loop feedback verification
- Traffic and latency simulation

## MVP non-goals

- No dashboards or observability UI (see [STARTUP_CONTEXT](docs/STARTUP_CONTEXT.md))
- No auth or tenancy (see [STARTUP_CONTEXT](docs/STARTUP_CONTEXT.md))
- No real llm-d integration (see [MENTAL_MODEL](docs/MENTAL_MODEL.md))
- No full agent framework integration (see [STARTUP_CONTEXT](docs/STARTUP_CONTEXT.md))
- No vector DB / RAG (see [STARTUP_CONTEXT](docs/STARTUP_CONTEXT.md))

## What is intentionally mocked

- GPUs
- Model servers
- Autoscaling
- Real LLMs

## Goal

Demonstrate closed-loop control, not model quality.

MVP goal: demonstrate closed-loop control, not production completeness.
