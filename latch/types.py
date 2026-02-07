"""
Core schemas for the Latch control loop.

These dataclasses define the stable contracts between modules.
They are intentionally minimal and versionable.
"""

from dataclasses import dataclass, field
from typing import Dict, List


@dataclass(frozen=True)
class Intent:
    """Customer goal constraints for a single request class."""

    name: str
    priority: int = 0
    max_latency_ms: int = 1000
    max_cost: float = 0.01
    constraints: List[str] = field(default_factory=list)
    params: Dict[str, str] = field(default_factory=dict)


@dataclass(frozen=True)
class RequestContext:
    """Request classification and lightweight metadata."""

    user_id: str
    trace_id: str
    prompt_tokens: int
    tier: str
    is_background: bool
    metadata: Dict[str, str] = field(default_factory=dict)

    @property
    def request_type(self) -> str:
        """Derived request type. Keep this consistent with `is_background`."""
        return "background" if self.is_background else "user"


@dataclass(frozen=True)
class Signals:
    """Lightweight, real-time aggregates used for control decisions."""

    p95_latency_ms: float = 0.0
    error_rate: float = 0.0
    cost_rate: float = 0.0
    queue_depth: float = 0.0


@dataclass(frozen=True)
class Policy:
    """Decision output used for enforcement in the request path."""

    mode: str  # "normal" | "degraded"
    priority: str  # "latency" | "throughput"
    max_tokens: int
    notes: str
