# ADR-0001: Intent-Based Control

## Context
Customers express goals (latency, cost, priority), not scheduling rules.
Static configs fail under changing traffic.

## Decision
We represent customer goals as intents and translate them into
execution constraints at runtime.

## Consequences
- Decisions happen before inference, not after logs.
- Control logic lives above infra-level systems like llm-d.
- Policies can evolve without changing infrastructure.
