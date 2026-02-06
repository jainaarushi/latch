from typing import Iterable, List
from control_plane.intents import Intent


def generate_traffic() -> Iterable[Intent]:
    intents: List[Intent] = [
        Intent(name="summarize", priority=1, constraints=[]),
        Intent(name="classify", priority=2, constraints=[]),
        Intent(name="exfiltrate", priority=9, constraints=["deny"]),
    ]
    for intent in intents:
        yield intent
