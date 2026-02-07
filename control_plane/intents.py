"""
Intent Schema

Defines application intent as latency, cost, and priority constraints.

It must NOT:
- encode infrastructure scheduling logic
- depend on runtime metrics or offline logs
"""

from latch.types import Intent

__all__ = ["Intent"]
