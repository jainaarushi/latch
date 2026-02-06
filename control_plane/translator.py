from typing import Dict
from .decision_engine import Decision
from .intents import Intent


class Translator:
    def translate(self, intent: Intent, decision: Decision) -> Dict[str, str]:
        return {
            "intent": intent.name,
            "action": decision.action,
            "mode": decision.mode,
            "priority": str(intent.priority),
            "max_latency_ms": str(intent.max_latency_ms),
            "max_cost": f"{intent.max_cost:.4f}",
            "params": str(intent.params),
        }
