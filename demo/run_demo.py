from demo.traffic_simulator import generate_traffic
from demo.demo_agent import DemoAgent


def main() -> None:
    agent = DemoAgent()
    for intent in generate_traffic():
        outcome = agent.handle(intent)
        print(outcome)
    print("metrics", agent.metrics.snapshot())


if __name__ == "__main__":
    main()
