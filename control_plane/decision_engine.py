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
