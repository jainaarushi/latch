"""
Signals (Metrics -> Control Signals)

Purpose
- Convert rolling metrics into small, stable "signals" that drive decisions.
  Examples:
  - latency_hot = True if p95_latency_ms > threshold
  - cost_hot = True if cost_rate > threshold
  - error_hot = True if error_rate > threshold
  - overload = True if queue_depth > threshold

Hard constraints for MVP
- Signals must be few and interpretable (<= 10).
- Thresholds are configurable but simple.
- No ML anomaly detection.

Non-goals
- Not alerting or paging.
- Not dashboard logic.
"""

from dataclasses import dataclass
from typing import List


@dataclass
class Signal:
    name: str
    value: float


def derive_signals(snapshot: dict) -> List[Signal]:
    return [
        Signal("allow_rate", float(snapshot.get("allow_rate", 0.0))),
        Signal("p95_latency_ms", float(snapshot.get("p95_latency_ms", 0.0))),
        Signal("avg_cost", float(snapshot.get("avg_cost", 0.0))),
        Signal("avg_queue_depth", float(snapshot.get("avg_queue_depth", 0.0))),
    ]
