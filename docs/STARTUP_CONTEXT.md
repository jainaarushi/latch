# Startup Context

## Problem Statement

LLM systems break in production because traffic, prompts, and usage
patterns change continuously. Static configurations and observability
are insufficient to keep latency, cost, and reliability stable.

## Core Insight

Production LLM systems need a real-time control layer that translates
application intent (latency, cost, priority) into execution behavior.
This layer must operate in the request path and close the loop via
continuous feedback.

## Non-Goals

- This is not an observability platform.
- This is not a model quality or prompt engineering system.
- This is not an infrastructure scheduler (e.g., GPU batching).

## Relationship to Other Systems

- llm-d: Infra-level control plane (GPU scheduling, batching).
  This project operates above llm-d, translating intent into constraints.
- Monitoring tools (Datadog, etc.): Used for verification and debugging,
  not for driving decisions.

## Why This Repo Exists

This repository demonstrates a reference implementation of the
application-level control loop for LLM inference systems.

The goal is correctness of architecture, not production completeness.
