from typing import Dict


class FakeLLMD:
    def execute(self, request: Dict[str, str]) -> Dict[str, str]:
        return {
            "status": "ok",
            "echo": request.get("intent", "unknown"),
            "action": request.get("action", "none"),
        }
