from typing import Iterable, List, Tuple
from control_plane.intents import Intent
from runtime.request_context import RequestContext


def generate_traffic() -> Iterable[Tuple[Intent, RequestContext]]:
    intents: List[Intent] = [
        Intent(name="summarize", priority=1, max_latency_ms=800, max_cost=0.004),
        Intent(name="classify", priority=2, max_latency_ms=400, max_cost=0.003),
        Intent(name="exfiltrate", priority=9, max_latency_ms=200, max_cost=0.001, constraints=["deny"]),
    ]
    prompt_sizes = [128, 256, 512, 1024, 1536]
    for i in range(10):
        intent = intents[i % len(intents)]
        prompt_tokens = prompt_sizes[min(i, len(prompt_sizes) - 1)]
        is_background = i % 4 == 0
        context = RequestContext(
            user_id=f"user-{i%3}",
            trace_id=f"trace-{i}",
            prompt_tokens=prompt_tokens,
            tier="pro" if i % 3 == 0 else "free",
            is_background=is_background,
            metadata={"spike": "true" if i in (6, 7, 8) else "false"},
        )
        yield intent, context
