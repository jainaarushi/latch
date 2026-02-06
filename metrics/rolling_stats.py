class RollingStats:
    def __init__(self) -> None:
        self.count = 0
        self.allowed = 0

    def record(self, allowed: bool) -> None:
        self.count += 1
        if allowed:
            self.allowed += 1

    def snapshot(self) -> dict:
        if self.count == 0:
            return {"count": 0, "allow_rate": 0.0}
        return {"count": self.count, "allow_rate": self.allowed / self.count}
