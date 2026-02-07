"""
Request Context

Captures request-level metadata used for control decisions and
runtime constraints.

It must NOT:
- include authentication or multi-tenant authorization
- encode infrastructure scheduling policy
"""

from latch.types import RequestContext

__all__ = ["RequestContext"]
