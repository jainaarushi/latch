from typing import List
from .intents import Intent


class PolicyEngine:
    def __init__(self, blocked_intents: List[str] | None = None) -> None:
        self.blocked_intents = set(blocked_intents or [])

    def evaluate(self, intent: Intent) -> bool:
        if intent.name in self.blocked_intents:
            return False
        if "deny" in intent.constraints:
            return False
        return True
