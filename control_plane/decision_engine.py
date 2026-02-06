from dataclasses import dataclass
from .intents import Intent


@dataclass
class Decision:
    allowed: bool
    action: str
    reason: str


class DecisionEngine:
    def decide(self, intent: Intent, policy_ok: bool) -> Decision:
        if not policy_ok:
            return Decision(False, "deny", "policy_reject")
        if intent.priority > 5:
            return Decision(True, "escalate", "high_priority")
        return Decision(True, "allow", "policy_ok")
