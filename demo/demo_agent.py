from control_plane import DecisionEngine, FeedbackLoop, PolicyEngine, Translator
from control_plane.decision_engine import Decision
from control_plane.policy_engine import PolicyResult
from control_plane.intents import Intent
from metrics.collector import MetricsCollector
from runtime.gateway import RuntimeGateway
from runtime.request_context import RequestContext


class DemoAgent:
    def __init__(self) -> None:
        self.policy = PolicyEngine(blocked_intents=["exfiltrate"])
        self.decider = DecisionEngine()
        self.translator = Translator()
        self.runtime = RuntimeGateway()
        self.feedback = FeedbackLoop()
        self.metrics = MetricsCollector()

    def _baseline_decision(self) -> Decision:
        policy = PolicyResult(True, "balanced", "baseline")
        return Decision(True, "allow", "baseline", policy.mode)

    def handle(self, intent: Intent, context: RequestContext, use_control: bool) -> dict:
        if use_control:
            policy = self.policy.evaluate(intent)
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
            "mode": decision.mode,
            "max_latency_ms": str(intent.max_latency_ms),
            "max_cost": f"{intent.max_cost:.4f}",
            "latency_ms": response.get("latency_ms", "0"),
            "queue_depth": response.get("queue_depth", "0"),
            "cost": response.get("cost", "0"),
        }
        self.feedback.record(outcome)
        self.metrics.record(outcome)
        return outcome
