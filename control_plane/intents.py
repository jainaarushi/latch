from dataclasses import dataclass, field
from typing import Dict, List


@dataclass
class Intent:
    name: str
    priority: int = 0
    constraints: List[str] = field(default_factory=list)
    params: Dict[str, str] = field(default_factory=dict)
