if __name__ == "__main__" and __package__ is None:
    # Allow `python demo/run_demo.py` from any working directory.
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from demo.traffic_simulator import generate_traffic
from demo.demo_agent import DemoAgent
from metrics.signals import derive_signals


def run(use_control: bool) -> None:
    agent = DemoAgent()
    for intent, context in generate_traffic():
        outcome = agent.handle(intent, context, use_control)
        print(outcome)
    snapshot = agent.metrics.snapshot()
    print("metrics", snapshot)
    print("signals", derive_signals(snapshot))


def main() -> None:
    print("baseline")
    run(use_control=False)
    print("with_control")
    run(use_control=True)


if __name__ == "__main__":
    main()
