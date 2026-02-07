from control_plane import DecisionEngine, FeedbackLoop, Translator
from control_plane.policy_engine import decide_policy
from control_plane.decision_engine import Decision
from control_plane.intents import Intent
from latch.types import Signals
from metrics.collector import MetricsCollector
from runtime.gateway import RuntimeGateway
from runtime.request_context import RequestContext


class DemoAgent:
    def __init__(self) -> None:
        self.decider = DecisionEngine()
        self.translator = Translator()
        self.runtime = RuntimeGateway()
        self.feedback = FeedbackLoop()
        self.metrics = MetricsCollector()

    def _baseline_decision(self) -> Decision:
        return Decision(True, "allow", "baseline", "normal")

    def handle(self, intent: Intent, context: RequestContext, use_control: bool) -> dict:
        if use_control:
            policy = decide_policy(intent, Signals(), context)
            decision = self.decider.decide(intent, policy)
        else:
            decision = self._baseline_decision()
        request = self.translator.translate(intent, decision)
        response = self.runtime.dispatch(request, context)
        outcome = {
            "intent": intent.name,
            "allowed": "true" if decision.allowed else "false",
            "action": decision.action,
            "reason": decision.reason,
            # Keep `mode` as the policy/controller mode for now (normal/degraded).
            # Runtime-facing mode (fast/cheap/balanced) is separately recorded.
            "mode": decision.mode,
            "runtime_mode": request.get("mode", "unknown"),
            "max_latency_ms": str(intent.max_latency_ms),
            "max_cost": f"{intent.max_cost:.4f}",
            "latency_ms": response.get("latency_ms", "0"),
            "queue_depth": response.get("queue_depth", "0"),
            "cost": response.get("cost", "0"),
        }
        self.feedback.record(outcome)
        self.metrics.record(outcome)
        return outcome
