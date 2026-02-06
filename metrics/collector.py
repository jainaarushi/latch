from typing import Dict
from .rolling_stats import RollingStats


class MetricsCollector:
    def __init__(self) -> None:
        self.stats = RollingStats()

    def record(self, outcome: Dict[str, str]) -> None:
        allowed = outcome.get("allowed", "false") == "true"
        self.stats.record(allowed)

    def snapshot(self) -> dict:
        return self.stats.snapshot()
