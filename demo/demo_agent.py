from control_plane import DecisionEngine, FeedbackLoop, PolicyEngine, Translator
from control_plane.decision_engine import Decision
from control_plane.intents import Intent
from metrics.collector import MetricsCollector
from runtime.gateway import RuntimeGateway
from runtime.request_context import RequestContext


class DemoAgent:
    def __init__(self) -> None:
        self.policy = PolicyEngine()
        self.decider = DecisionEngine()
        self.translator = Translator()
        self.runtime = RuntimeGateway()
        self.feedback = FeedbackLoop()
        self.metrics = MetricsCollector()

    def _baseline_decision(self) -> Decision:
        return Decision(True, "allow", "baseline", "normal")

    def handle(self, intent: Intent, context: RequestContext, use_control: bool) -> dict:
        if use_control:
            signals = {
                # Demo uses a cold-start signal set. Later phases will derive
                # these from rolling metrics.
                "p95_latency_ms": 0.0,
                "error_rate": 0.0,
                "cost_rate": 0.0,
                "queue_depth": 0.0,
            }
            request_context = {
                "tier": context.tier,
                "prompt_tokens": str(context.prompt_tokens),
            }
            policy = self.policy.evaluate(intent, signals, request_context)
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
