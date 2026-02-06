"""
Policy Engine

Resolves tradeoffs across latency, cost, and constraints.

It must NOT:
- make infrastructure scheduling decisions
- call external services or rely on offline logs
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
