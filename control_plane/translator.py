from typing import Dict
from .decision_engine import Decision
from .intents import Intent


class Translator:
    def translate(self, intent: Intent, decision: Decision) -> Dict[str, str]:
        return {
            "intent": intent.name,
            "action": decision.action,
            "priority": str(intent.priority),
            "params": str(intent.params),
        }
