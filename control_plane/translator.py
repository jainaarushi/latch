"""
Translator (Intent -> Infra Constraints)

Purpose
- Translate our app-level policy outputs into a small, stable contract that an infra
  control plane (e.g., llm-d) can act on.

Inputs
- policy: normalized constraints from policy_engine
- signals: optional (used only to choose between a few translation presets)

Outputs
- infra_hints: infra-facing constraints/hints, e.g.:
  - priority: "latency" | "throughput"
  - max_queue_depth: int
  - batching: "low" | "auto"
  - concurrency_cap: int

Hard constraints for MVP
- Do NOT call real llm-d APIs; provide a fake adapter elsewhere.
- Do NOT invent deep GPU knobs; keep a minimal hint schema.
- Translator must be pure and side-effect free.

Non-goals
- Not an SDK/gateway.
- Not observability or tracing export.
"""

from typing import Dict
from .decision_engine import Decision
from .intents import Intent


class Translator:
    def translate(self, intent: Intent, decision: Decision) -> Dict[str, str]:
        if decision.action == "route_fast":
            runtime_mode = "fast"
        elif decision.action == "route_economy":
            runtime_mode = "cheap"
        else:
            runtime_mode = "balanced"
        return {
            "intent": intent.name,
            "action": decision.action,
            "policy_mode": decision.mode,
            "runtime_mode": runtime_mode,
            "mode": runtime_mode,
            "priority": str(intent.priority),
            "max_latency_ms": str(intent.max_latency_ms),
            "max_cost": f"{intent.max_cost:.4f}",
            "params": str(intent.params),
        }
