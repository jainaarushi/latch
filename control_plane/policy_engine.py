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

from latch.types import Intent, Policy, RequestContext, Signals


def decide_policy(intent: Intent, signals: Signals, request_context: RequestContext) -> Policy:
    """Public API for policy decisions in the control plane."""
    return PolicyEngine().evaluate(intent, signals, request_context)

class PolicyEngine:
    def evaluate(self, intent: Intent, signals: Signals, request_context: RequestContext) -> Policy:
        p95_latency = float(signals.p95_latency_ms)
        cost_rate = float(signals.cost_rate)
        error_rate = float(signals.error_rate)
        queue_depth = float(signals.queue_depth)
        tier = request_context.tier
        prompt_tokens = int(request_context.prompt_tokens)

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
