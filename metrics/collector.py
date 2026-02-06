"""
Metrics Collector

Collects lightweight metrics needed for control decisions.

It must NOT:
- implement dashboards or full observability
- export to external systems
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
