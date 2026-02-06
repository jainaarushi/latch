from typing import Dict


class FeedbackLoop:
    def verify(self, outcome: Dict[str, str]) -> bool:
        try:
            latency_ms = float(outcome.get("latency_ms", "0"))
            max_latency_ms = float(outcome.get("max_latency_ms", "0"))
            cost = float(outcome.get("cost", "0"))
            max_cost = float(outcome.get("max_cost", "0"))
        except ValueError:
            return False
        return latency_ms <= max_latency_ms and cost <= max_cost

    def record(self, outcome: Dict[str, str]) -> Dict[str, str]:
        ok = self.verify(outcome)
        outcome["slo_ok"] = "true" if ok else "false"
        return outcome
