"""
Fake llm-d Adapter (MVP Simulation)

Purpose
- Simulate an infra control plane (like llm-d) without real GPUs.
- Accept infra_hints and produce:
  - simulated latency
  - simulated queue depth
  - simulated "autoscale" events (optional)

Hard constraints for MVP
- Deterministic, controllable simulation.
- Must make the demo reproducible.

Non-goals
- Not a real llm-d integration.
- Not a performance-accurate GPU model.
"""

from typing import Dict


class FakeLLMD:
    def execute(self, request: Dict[str, str]) -> Dict[str, str]:
        prompt_tokens = int(request.get("prompt_tokens", "256"))
        mode = request.get("mode", "balanced")
        base_latency = 80 + (prompt_tokens / 8)
        if mode == "fast":
            base_latency *= 0.7
        elif mode == "cheap":
            base_latency *= 1.2
        queue_depth = int(base_latency / 50)
        batching = min(8, max(1, int(prompt_tokens / 512) + 1))
        latency_ms = base_latency + queue_depth * 10
        cost = (prompt_tokens / 1000.0) * (0.002 if mode == "cheap" else 0.004)
        return {
            "status": "ok",
            "echo": request.get("intent", "unknown"),
            "action": request.get("action", "none"),
            "latency_ms": f"{latency_ms:.1f}",
            "queue_depth": str(queue_depth),
            "batch_size": str(batching),
            "cost": f"{cost:.4f}",
        }
