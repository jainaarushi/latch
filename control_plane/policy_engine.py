"""
Policy Engine (MVP)

Purpose
- Resolve conflicts between intents and convert them into a concrete "desired behavior"
  for the current request window.

Inputs
- intent: customer goals (latency vs cost vs priority vs quality floor)
- signals: lightweight real-time aggregates (p95 latency, error rate, cost rate, queue depth)
- request_context: request type/tier/prompt size

Outputs
- policy: normalized constraints (e.g., priority=latency, max_tokens=256, allow_degrade=True)

Hard constraints for MVP
- Deterministic rules only (no ML, no optimization solvers).
- No external dependencies (no databases, no message queues).
- No infrastructure scheduling logic (do NOT implement batching/KV cache/GPU placement).

Non-goals
- Not a UI, not observability, not governance/auth.
- Not a general policy language; YAML parsing is optional and minimal.

Keep it small, testable, and boring.
"""

from dataclasses import dataclass
from typing import List
from .intents import Intent


@dataclass
class PolicyResult:
    allowed: bool
    mode: str
    reason: str


class PolicyEngine:
    def __init__(self, blocked_intents: List[str] | None = None) -> None:
        self.blocked_intents = set(blocked_intents or [])

    def evaluate(self, intent: Intent) -> PolicyResult:
        if intent.name in self.blocked_intents:
            return PolicyResult(False, "deny", "blocked_intent")
        if "deny" in intent.constraints:
            return PolicyResult(False, "deny", "explicit_deny")
        if intent.max_latency_ms < 200 and intent.max_cost < 0.002:
            return PolicyResult(False, "deny", "impossible_sla")
        if intent.max_latency_ms <= 400:
            return PolicyResult(True, "fast", "latency_priority")
        if intent.max_cost <= 0.003:
            return PolicyResult(True, "cheap", "cost_priority")
        return PolicyResult(True, "balanced", "default_policy")
