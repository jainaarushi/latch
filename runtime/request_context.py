"""
Request Context

Captures request-level metadata used for control decisions and
runtime constraints.

It must NOT:
- include authentication or multi-tenant authorization
- encode infrastructure scheduling policy
"""

from __future__ import annotations

from typing import Any, Dict, Optional
from uuid import uuid4

from latch.types import RequestContext

__all__ = ["RequestContext", "build_request_context", "estimate_prompt_tokens"]


def estimate_prompt_tokens(prompt_text: str) -> int:
    """Very lightweight token estimate for MVP (approx 4 chars per token)."""
    if not prompt_text:
        return 0
    return max(1, len(prompt_text) // 4)


def build_request_context(
    request_type: str,
    tier: str,
    prompt_text: str,
    metadata: Optional[Dict[str, Any]] = None,
) -> RequestContext:
    """
    Construct a RequestContext from minimal SDK inputs.

    Notes
    - `request_type` is normalized to "user" or "background".
    - `user_id` and `trace_id` are best-effort and can be supplied via metadata.
    """
    meta: Dict[str, Any] = dict(metadata or {})
    normalized = (request_type or "user").strip().lower()
    is_background = normalized == "background"

    user_id = str(meta.pop("user_id", "anonymous"))
    trace_id = str(meta.pop("trace_id", uuid4().hex))

    prompt_tokens = int(meta.pop("prompt_tokens", estimate_prompt_tokens(prompt_text)))

    # Keep RequestContext.metadata as str->str for now. Non-strings are coerced.
    str_meta: Dict[str, str] = {str(k): str(v) for k, v in meta.items()}
    return RequestContext(
        user_id=user_id,
        trace_id=trace_id,
        prompt_tokens=prompt_tokens,
        tier=tier,
        is_background=is_background,
        metadata=str_meta,
    )
