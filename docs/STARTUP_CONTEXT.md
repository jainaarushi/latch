# Startup Context

## What we are building
An intent-based control layer for LLM inference systems.

This repository intentionally avoids building observability dashboards, infrastructure schedulers, or production gateways. The sole goal is to demonstrate closed-loop control logic.

This system sits in the request path and continuously:
Signals -> Decisions -> Actions -> Verification

Goal: keep latency/cost/reliability stable as traffic and prompts change.

## What this is NOT
- NOT an observability product (no dashboards-first design).
- NOT a model hosting platform.
- NOT a GPU scheduler (llm-d does infra scheduling; we do app-level intent).
- NOT an agent orchestration framework (we wrap agent calls but do not implement agents).

## Key boundaries
- Decisions must be made before or during inference, not after offline logs.
- We express customer goals as intents (latency, cost, priority, quality floor).
- We output actions/constraints, not infrastructure-specific scheduling.
- We integrate with infra control planes (e.g., llm-d) via a small "intent -> constraint" translation layer.

## MVP scope (do only this)
- Minimal intent schema
- Policy/decision engine (rules-first)
- Request interceptor (SDK/gateway mock)
- Lightweight metrics signals (rolling windows)
- Fake llm-d adapter (simulated response times/queue pressure)
- Demo script showing stabilization under traffic spike

## Explicit non-goals for MVP
- Auth, multi-tenant RBAC, billing
- Full tracing stack / dashboards
- Real GPU integration
- RAG/vector DB/memory
- Multi-agent planning or tool graphs

## Definition of success (MVP)
A demo where:
- baseline system degrades under load
- with control loop enabled, latency/cost stay within target
- decisions are logged clearly ("switched model", "capped tokens", "reduced batching")

Under a simulated traffic spike, baseline inference degrades; with the control loop enabled, latency and/or cost stay within bounds automatically.

Why this works: Codex sees hard boundaries, MVP scope, and non-goals.
