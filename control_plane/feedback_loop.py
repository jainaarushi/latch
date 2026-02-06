"""
Feedback Loop (Verification)

Purpose
- Close the loop by checking whether actions improved outcomes.
- Adjust future decisions by updating internal state or recommending a mode change.

Inputs
- previous_decision / previous_policy
- new signals after action (p95 latency, errors, cost rate, queue depth)

Outputs
- feedback: small result object, e.g.:
  - outcome: "improved" | "worse" | "no_change"
  - recommended_mode: optional ("degraded" | "normal")
  - notes: short reason string for logs/tests

Hard constraints for MVP
- Must be lightweight; no heavy analytics.
- No dashboards; only structured logs/records.
- No offline training or historical big-data jobs.

Non-goals
- Not postmortem tooling.
- Not anomaly detection platform.
"""

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
