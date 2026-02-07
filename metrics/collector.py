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

from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from typing import Deque, Dict, List, Optional

from .rolling_stats import RollingStats


@dataclass(frozen=True)
class MetricEvent:
    ts: float
    latency_ms: float
    tokens_in: int
    tokens_out: int
    error_type: str
    request_type: str
    model_id: str
    queue_depth: float
    cost_estimate: float


class MetricsCollector:
    def __init__(self, *, max_events: int = 1000) -> None:
        self.stats = RollingStats()
        self._events: Deque[MetricEvent] = deque(maxlen=int(max_events))

    def record(self, outcome: Dict[str, str]) -> None:
        allowed = outcome.get("allowed", "false") == "true"
        latency_ms = float(outcome.get("latency_ms", "0"))
        cost = float(outcome.get("cost", "0"))
        queue_depth = float(outcome.get("queue_depth", "0"))
        self.stats.record(allowed, latency_ms, cost, queue_depth)

    def record_event(
        self,
        latency_ms: float,
        tokens_in: int,
        tokens_out: int,
        error_type: Optional[str],
        request_type: str,
        model_id: str,
        ts: float,
        *,
        queue_depth: float = 0.0,
        cost_estimate: float = 0.0,
    ) -> None:
        """
        Record a single request-path metric event.

        This is the SDK-facing API. It is intentionally in-memory only.
        """
        err = (error_type or "").strip()
        allowed = err == ""
        self._events.append(
            MetricEvent(
                ts=float(ts),
                latency_ms=float(latency_ms),
                tokens_in=int(tokens_in),
                tokens_out=int(tokens_out),
                error_type=err,
                request_type=(request_type or "user"),
                model_id=(model_id or "unknown"),
                queue_depth=float(queue_depth),
                cost_estimate=float(cost_estimate),
            )
        )
        # Feed RollingStats with the minimal aggregates needed for control signals.
        self.stats.record(allowed, float(latency_ms), float(cost_estimate), float(queue_depth))

    def events(self) -> List[MetricEvent]:
        return list(self._events)

    def last_event(self) -> Optional[MetricEvent]:
        return self._events[-1] if self._events else None

    def snapshot(self) -> dict:
        return self.stats.snapshot()
