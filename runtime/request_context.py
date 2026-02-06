from dataclasses import dataclass
from typing import Dict


@dataclass
class RequestContext:
    user_id: str
    trace_id: str
    prompt_tokens: int
    tier: str
    is_background: bool
    metadata: Dict[str, str]
