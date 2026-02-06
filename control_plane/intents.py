from dataclasses import dataclass, field
from typing import Dict, List


@dataclass
class Intent:
    name: str
    priority: int = 0
    max_latency_ms: int = 1000
    max_cost: float = 0.01
    constraints: List[str] = field(default_factory=list)
    params: Dict[str, str] = field(default_factory=dict)
