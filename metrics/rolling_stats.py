"""
Rolling Stats (MVP)

Purpose
- Maintain rolling aggregates required by the control loop:
  - moving average
  - p50/p95 approximations (simple is fine)
  - error rate over a short window

Hard constraints for MVP
- Keep implementation simple and deterministic.
- No external libraries needed beyond stdlib.
- Operate on a bounded in-memory window.

Non-goals
- No heavy quantile algorithms.
- No time-series database integration.
"""

from collections import deque
from typing import Deque


class RollingStats:
    def __init__(self, window: int = 50) -> None:
        self.window: Deque[float] = deque(maxlen=window)
        self.count = 0
        self.allowed = 0
        self.total_cost = 0.0
        self.total_latency = 0.0
        self.total_queue = 0.0

    def record(self, allowed: bool, latency_ms: float, cost: float, queue_depth: float) -> None:
        self.count += 1
        if allowed:
            self.allowed += 1
        self.total_cost += cost
        self.total_latency += latency_ms
        self.total_queue += queue_depth
        self.window.append(latency_ms)

    def _p95(self) -> float:
        if not self.window:
            return 0.0
        values = sorted(self.window)
        idx = int(0.95 * (len(values) - 1))
        return values[idx]

    def snapshot(self) -> dict:
        if self.count == 0:
            return {
                "count": 0,
                "allow_rate": 0.0,
                "avg_latency_ms": 0.0,
                "p95_latency_ms": 0.0,
                "avg_cost": 0.0,
                "avg_queue_depth": 0.0,
            }
        return {
            "count": self.count,
            "allow_rate": self.allowed / self.count,
            "avg_latency_ms": self.total_latency / self.count,
            "p95_latency_ms": self._p95(),
            "avg_cost": self.total_cost / self.count,
            "avg_queue_depth": self.total_queue / self.count,
        }
