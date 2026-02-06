"""
Metrics Collector (MVP)

Purpose
- Collect minimal request-path metrics needed for control decisions.

Collect ONLY
- latency_ms
- tokens_in / tokens_out (can be approximate)
- error_type (optional)
- queue_depth (if available from runtime/fake_llmd)
- cost_estimate (derived, optional)

Hard constraints for MVP
- In-memory only (no Prometheus, no Datadog integration).
- No distributed tracing setup (OTel optional later).
- Must not block the request path; collection should be O(1).

Non-goals
- Not a full observability system.
- Not long-term storage.
"""

from typing import Dict
from .rolling_stats import RollingStats


class MetricsCollector:
    def __init__(self) -> None:
        self.stats = RollingStats()

    def record(self, outcome: Dict[str, str]) -> None:
        allowed = outcome.get("allowed", "false") == "true"
        latency_ms = float(outcome.get("latency_ms", "0"))
        cost = float(outcome.get("cost", "0"))
        queue_depth = float(outcome.get("queue_depth", "0"))
        self.stats.record(allowed, latency_ms, cost, queue_depth)

    def snapshot(self) -> dict:
        return self.stats.snapshot()
