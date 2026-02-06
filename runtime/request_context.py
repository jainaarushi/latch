from dataclasses import dataclass
from typing import Dict


@dataclass
class RequestContext:
    user_id: str
    trace_id: str
    metadata: Dict[str, str]
