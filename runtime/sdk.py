"""
SDK (MVP)

This module provides the SDK-first entry point: a thin request-path wrapper
around model calls.

It must NOT:
- implement auth/tenancy/billing
- call external systems (no databases, no llm-d integration)
- implement dashboards/observability frameworks
"""

from __future__ import annotations

import inspect
import time
from dataclasses import dataclass
from typing import Any, Callable, Dict, Optional, Tuple
from uuid import uuid4

from control_plane.policy_engine import decide_policy
from latch.types import Intent, Policy, Signals
from metrics.collector import MetricsCollector
from runtime.request_context import RequestContext, build_request_context


@dataclass
class ModelCallResult:
    value: Any
    latency_ms: float
    tokens_out: int


class RequestSession:
    def __init__(
        self,
        *,
        client: "LatchClient",
        request_type: str,
        tier: str,
        metadata: Optional[Dict[str, Any]],
        intent: Optional[Intent],
    ) -> None:
        self._client = client
        self._request_type = request_type
        self._tier = tier
        self._metadata: Dict[str, Any] = dict(metadata or {})
        self._intent = intent or client.intent

        # Keep identifiers stable across multiple model calls in the same session.
        self._metadata.setdefault("user_id", self._metadata.get("user_id", "anonymous"))
        self._metadata.setdefault("trace_id", self._metadata.get("trace_id", uuid4().hex))

        self.last_context: Optional[RequestContext] = None
        self.last_policy: Optional[Policy] = None

    def __enter__(self) -> "RequestSession":
        return self

    def __exit__(self, exc_type: Any, exc: Any, tb: Any) -> None:
        return None

    def before_model_call(self, prompt_text: str) -> Tuple[RequestContext, Policy]:
        context = build_request_context(
            self._request_type,
            self._tier,
            prompt_text,
            metadata=self._metadata,
        )

        # Phase 1: stubbed signals (all zeros) to keep the hot-path shape.
        policy = decide_policy(self._intent, Signals(), context)

        self.last_context = context
        self.last_policy = policy
        return context, policy

    def after_model_call(
        self,
        *,
        context: RequestContext,
        latency_ms: float,
        tokens_out: int,
        error_type: Optional[str],
        model_id: str,
    ) -> None:
        self._client.metrics.record_event(
            latency_ms,
            tokens_in=context.prompt_tokens,
            tokens_out=tokens_out,
            error_type=error_type,
            request_type=context.request_type,
            model_id=model_id,
            ts=time.time(),
        )

    def call_model(
        self,
        prompt_text: str,
        *,
        model_fn: Callable[..., Any],
        model_id: str = "unknown",
        max_tokens: Optional[int] = None,
        **kwargs: Any,
    ) -> ModelCallResult:
        context, policy = self.before_model_call(prompt_text)

        # Phase 1 placeholder enforcement: cap max_tokens using the policy output.
        policy_cap = max(0, int(policy.max_tokens))
        requested = policy_cap if max_tokens is None else int(max_tokens)
        effective_max_tokens = min(max(0, requested), policy_cap)

        start_ts = time.time()
        start = time.perf_counter()
        error_type: Optional[str] = None
        value: Any = None
        tokens_out = 0
        try:
            call_kwargs: Dict[str, Any] = {"model": model_id, "max_tokens": effective_max_tokens, **kwargs}

            # Avoid "retry on TypeError" because it can swallow real TypeErrors from inside model_fn.
            # Instead, filter kwargs based on the callable signature when available.
            try:
                sig = inspect.signature(model_fn)
                params = sig.parameters
                accepts_var_kw = any(p.kind == inspect.Parameter.VAR_KEYWORD for p in params.values())
                filtered = call_kwargs if accepts_var_kw else {k: v for k, v in call_kwargs.items() if k in params}
                value = model_fn(prompt_text, **filtered)
            except (TypeError, ValueError):
                # Signature introspection can fail for builtins/extension callables; fall back to minimal call.
                value = model_fn(prompt_text)
        except Exception as exc:
            error_type = type(exc).__name__
            raise
        finally:
            latency_ms = (time.perf_counter() - start) * 1000.0

            # Best-effort tokens_out extraction.
            if isinstance(value, dict):
                try:
                    tokens_out = int(value.get("tokens_out", 0))
                except Exception:
                    tokens_out = 0

            self.after_model_call(
                context=context,
                latency_ms=latency_ms,
                tokens_out=tokens_out,
                error_type=error_type,
                model_id=model_id,
            )

        return ModelCallResult(value=value, latency_ms=latency_ms, tokens_out=tokens_out)


class LatchClient:
    def __init__(self, *, intent: Optional[Intent] = None, metrics: Optional[MetricsCollector] = None) -> None:
        self.intent = intent or Intent(name="default")
        self.metrics = metrics or MetricsCollector()

    def request(
        self,
        *,
        request_type: str = "user",
        tier: str = "free",
        metadata: Optional[Dict[str, Any]] = None,
        intent: Optional[Intent] = None,
    ) -> RequestSession:
        return RequestSession(
            client=self,
            request_type=request_type,
            tier=tier,
            metadata=metadata,
            intent=intent,
        )
