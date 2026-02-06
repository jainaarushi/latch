from typing import Dict
from .fake_llmd import FakeLLMD


class RuntimeGateway:
    def __init__(self) -> None:
        self.llmd = FakeLLMD()

    def dispatch(self, request: Dict[str, str]) -> Dict[str, str]:
        return self.llmd.execute(request)
