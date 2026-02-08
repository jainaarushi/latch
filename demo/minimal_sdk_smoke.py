"""
Minimal SDK smoke test (Phase 1).

Runs a single wrapped model call to validate:
- request context construction
- stubbed policy invocation
- metric event recording
"""

from __future__ import annotations

if __name__ == "__main__" and __package__ is None:
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import time

from latch import Intent, LatchClient


def dummy_model(prompt: str, *, model: str, max_tokens: int) -> dict:
    # Deterministic-ish fake: latency scales with prompt size; tokens_out respects max_tokens.
    time.sleep(0.02)
    tokens_out = min(max_tokens, max(1, len(prompt) // 10))
    return {"text": f"[{model}] ok", "tokens_out": tokens_out}


def main() -> None:
    client = LatchClient(intent=Intent(name="chat_user", max_latency_ms=800))

    prompt = "Hello Latch. " * 30
    with client.request(request_type="user", tier="premium", metadata={"user_id": "u1"}) as r:
        result = r.call_model(prompt, model_fn=dummy_model, model_id="large", max_tokens=9999)

        print("request_context", r.last_context)
        print("policy", r.last_policy)
        print("model_latency_ms", f"{result.latency_ms:.2f}")
        print("tokens_out", result.tokens_out)

    print("last_event", client.metrics.last_event())


if __name__ == "__main__":
    main()
