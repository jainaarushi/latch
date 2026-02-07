"""
Policy Engine (MVP)

Purpose
- Decide how the system should behave given intent, signals, and request context.

Inputs
- intent: customer goals (latency vs cost vs priority vs quality floor)
- signals: lightweight real-time aggregates (p95 latency, error rate, cost rate, queue depth)
- request_context: request type/tier/prompt size

Outputs
- policy: small, deterministic decision object with mode/priority/max_tokens/notes

Hard constraints for MVP
- Deterministic rules only (no ML, no optimization solvers).
- No external dependencies (no databases, no message queues).
- No infrastructure scheduling logic (do NOT implement batching/KV cache/GPU placement).

Non-goals
- Not a UI, not observability, not governance/auth.
- Not a general policy language; YAML parsing is optional and minimal.

Keep it small, testable, and boring.
"""

from typing import Dict
from .intents import Intent
from latch.types import Policy

class PolicyEngine:
    def evaluate(self, intent: Intent, signals: Dict[str, float], request_context: Dict[str, str]) -> Policy:
        p95_latency = float(signals.get("p95_latency_ms", 0.0))
        cost_rate = float(signals.get("cost_rate", 0.0))
        error_rate = float(signals.get("error_rate", 0.0))
        queue_depth = float(signals.get("queue_depth", 0.0))
        tier = request_context.get("tier", "free")
        prompt_tokens = int(request_context.get("prompt_tokens", "256"))

        if "deny" in intent.constraints:
            return Policy("degraded", "throughput", 0, "explicit_deny")

        if error_rate > 0.05 or queue_depth > 8:
            return Policy("degraded", "throughput", 128, "system_hot")

        if p95_latency > intent.max_latency_ms:
            return Policy("degraded", "latency", 256, "latency_hot")

        if cost_rate > intent.max_cost:
            return Policy("degraded", "throughput", 192, "cost_hot")

        if intent.max_latency_ms <= 400 or intent.priority >= 8:
            return Policy("normal", "latency", max(256, prompt_tokens // 2), "latency_priority")

        if tier == "free":
            return Policy("normal", "throughput", 256, "free_tier")

        return Policy("normal", "throughput", 512, "default")
