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
