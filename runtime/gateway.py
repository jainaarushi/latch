from typing import Dict
from .fake_llmd import FakeLLMD
from .request_context import RequestContext


class RuntimeGateway:
    def __init__(self) -> None:
        self.llmd = FakeLLMD()

    def dispatch(self, request: Dict[str, str], context: RequestContext) -> Dict[str, str]:
        enriched = dict(request)
        enriched["prompt_tokens"] = str(context.prompt_tokens)
        enriched["tier"] = context.tier
        enriched["is_background"] = "true" if context.is_background else "false"
        return self.llmd.execute(enriched)
