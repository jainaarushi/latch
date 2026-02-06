"""
Decision Engine (MVP)

This module decides WHAT should happen given:
- customer intent (latency/cost/priority/quality)
- live signals (p95 latency, queue depth, cost rate)

Outputs:
- high-level actions: model_choice, max_tokens, context_strategy, priority_hint

MUST NOT:
- implement observability dashboards
- implement GPU scheduling/batching logic
- depend on offline logs or external monitoring systems
- implement agent orchestration frameworks

Keep it rules-first and deterministic for MVP.
"""

from dataclasses import dataclass
from .intents import Intent
from .policy_engine import PolicyResult


@dataclass
class Decision:
    allowed: bool
    action: str
    reason: str
    mode: str


class DecisionEngine:
    def decide(self, intent: Intent, policy: PolicyResult) -> Decision:
        if not policy.allowed:
            return Decision(False, "deny", policy.reason, policy.mode)
        if intent.priority >= 8:
            return Decision(True, "escalate", "high_priority", policy.mode)
        if policy.mode == "fast":
            return Decision(True, "route_fast", "latency_budget", policy.mode)
        if policy.mode == "cheap":
            return Decision(True, "route_economy", "cost_budget", policy.mode)
        return Decision(True, "allow", "policy_ok", policy.mode)
