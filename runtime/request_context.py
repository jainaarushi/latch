"""
Request Context

Captures request-level metadata used for control decisions and
runtime constraints.

It must NOT:
- include authentication or multi-tenant authorization
- encode infrastructure scheduling policy
"""

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
