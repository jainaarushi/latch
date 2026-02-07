# LLM Intent Control Plane

This repository demonstrates a reference implementation of an
intent-based control plane for LLM inference systems.

A reference implementation of an intent-aware control loop that sits in the inference path and stabilizes behavior under changing traffic

## What problem does this solve?

LLM systems break in production because traffic, prompts, and usage
patterns change continuously. Static configurations and observability
are not enough.

This project shows how application intent (latency, cost, priority)
can be translated into real-time control decisions that stabilize
LLM behavior under load.

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
