from control_plane import DecisionEngine, FeedbackLoop, PolicyEngine, Translator
from metrics.collector import MetricsCollector
from runtime.gateway import RuntimeGateway
from control_plane.intents import Intent


class DemoAgent:
    def __init__(self) -> None:
        self.policy = PolicyEngine(blocked_intents=["exfiltrate"])
        self.decider = DecisionEngine()
        self.translator = Translator()
        self.runtime = RuntimeGateway()
        self.feedback = FeedbackLoop()
        self.metrics = MetricsCollector()

    def handle(self, intent: Intent) -> dict:
        policy_ok = self.policy.evaluate(intent)
        decision = self.decider.decide(intent, policy_ok)
        request = self.translator.translate(intent, decision)
        response = self.runtime.dispatch(request)
        outcome = {
            "intent": intent.name,
            "allowed": "true" if decision.allowed else "false",
            "action": decision.action,
            "reason": decision.reason,
            "status": response.get("status", "unknown"),
        }
        self.feedback.record(outcome)
        self.metrics.record(outcome)
        return outcome
