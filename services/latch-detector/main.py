from __future__ import annotations

import os
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

import httpx
import yaml
from fastapi import FastAPI

METRICS_STATE_URL = os.getenv("METRICS_STATE_URL", "http://latch-metrics:8080/state")
RULES_PATH = Path(os.getenv("RULES_PATH", "/app/rules.yaml"))
REQUEST_TIMEOUT_S = float(os.getenv("REQUEST_TIMEOUT_S", "10"))
POLL_INTERVAL_S = float(os.getenv("POLL_INTERVAL_S", "5"))

app = FastAPI(title="latch-detector", version="0.1.0")


@dataclass
class ImbalanceRule:
    enabled: bool
    min_replicas: int
    qps_skew_threshold: float
    sustained_seconds: int
    ttft_p95_increase_pct_threshold: float
    baseline_window_seconds: int
    min_qps_floor: float
    zero_qps_epsilon: float


class DetectorState:
    def __init__(self) -> None:
        self.rules = self._load_rules()
        self.baseline_ttft_samples: List[float] = []
        self.baseline_updated_at = 0.0
        self.first_breach_at: Optional[float] = None
        self.active_incident: Optional[dict] = None
        self.last_error: Optional[str] = None

    def _load_rules(self) -> ImbalanceRule:
        with RULES_PATH.open("r", encoding="utf-8") as f:
            raw = yaml.safe_load(f) or {}
        cfg = (raw.get("rules") or {}).get("imbalance") or {}
        return ImbalanceRule(
            enabled=bool(cfg.get("enabled", True)),
            min_replicas=int(cfg.get("min_replicas", 2)),
            qps_skew_threshold=float(cfg.get("qps_skew_threshold", 3.0)),
            sustained_seconds=int(cfg.get("sustained_seconds", 30)),
            ttft_p95_increase_pct_threshold=float(cfg.get("ttft_p95_increase_pct_threshold", 30.0)),
            baseline_window_seconds=int(cfg.get("baseline_window_seconds", 120)),
            min_qps_floor=float(cfg.get("min_qps_floor", 0.1)),
            zero_qps_epsilon=float(cfg.get("zero_qps_epsilon", 0.001)),
        )

    def _iso(self, ts: float) -> str:
        return (
            datetime.fromtimestamp(ts, tz=timezone.utc)
            .replace(microsecond=0)
            .isoformat()
            .replace("+00:00", "Z")
        )

    def _compute_skew(self, replicas: List[dict]) -> Optional[float]:
        all_qps = [float(r.get("qps", 0.0)) for r in replicas]
        if len(all_qps) < self.rules.min_replicas:
            return None

        max_qps = max(all_qps)
        if max_qps < self.rules.min_qps_floor:
            return None

        min_qps = min(all_qps)
        # If one replica is effectively idle while another is active, treat as extreme skew.
        denominator = max(min_qps, self.rules.zero_qps_epsilon)
        return max_qps / denominator

    def _update_baseline(self, ttft_ms: float, now: float) -> float:
        if ttft_ms > 0:
            self.baseline_ttft_samples.append(ttft_ms)
            self.baseline_updated_at = now

        # keep only window-sized sample count based on polling interval
        max_samples = max(1, int(self.rules.baseline_window_seconds / max(POLL_INTERVAL_S, 1)))
        if len(self.baseline_ttft_samples) > max_samples:
            self.baseline_ttft_samples = self.baseline_ttft_samples[-max_samples:]

        if not self.baseline_ttft_samples:
            return 0.0
        return sum(self.baseline_ttft_samples) / len(self.baseline_ttft_samples)

    def _evaluate(self, state_payload: Dict[str, Any], now: float) -> None:
        if not self.rules.enabled:
            self.active_incident = None
            return

        replicas = state_payload.get("replicas") or []
        if len(replicas) < self.rules.min_replicas:
            self.first_breach_at = None
            self.active_incident = None
            return

        ttft_p95_ms = float((state_payload.get("global") or {}).get("ttft_p95_ms", 0.0))
        baseline_ttft_ms = self._update_baseline(ttft_p95_ms, now)

        skew = self._compute_skew(replicas)
        if skew is None or baseline_ttft_ms <= 0 or ttft_p95_ms <= 0:
            self.first_breach_at = None
            self.active_incident = None
            return

        ttft_increase_pct = ((ttft_p95_ms - baseline_ttft_ms) / baseline_ttft_ms) * 100.0
        skew_breached = skew > self.rules.qps_skew_threshold
        ttft_breached = ttft_increase_pct >= self.rules.ttft_p95_increase_pct_threshold

        if skew_breached and ttft_breached:
            if self.first_breach_at is None:
                self.first_breach_at = now
            sustained = now - self.first_breach_at
            if sustained >= self.rules.sustained_seconds:
                started = self.first_breach_at
                self.active_incident = {
                    "id": f"inc_{int(started)}",
                    "type": "IMBALANCE",
                    "severity": "HIGH",
                    "started_at": self._iso(started),
                    "evidence": {
                        "qps_skew": round(skew, 3),
                        "qps_skew_threshold": self.rules.qps_skew_threshold,
                        "ttft_p95_increase_pct": round(ttft_increase_pct, 3),
                        "ttft_p95_increase_pct_threshold": self.rules.ttft_p95_increase_pct_threshold,
                        "ttft_p95_ms": round(ttft_p95_ms, 3),
                        "baseline_ttft_p95_ms": round(baseline_ttft_ms, 3),
                    },
                }
            return

        self.first_breach_at = None
        self.active_incident = None

    def poll_once(self) -> None:
        now = time.time()
        try:
            with httpx.Client(timeout=REQUEST_TIMEOUT_S) as client:
                resp = client.get(METRICS_STATE_URL)
                resp.raise_for_status()
                payload = resp.json()
            self._evaluate(payload, now)
            self.last_error = None
        except Exception as exc:  # broad by design for resilient poll loop
            self.last_error = str(exc)


STATE = DetectorState()
STOP_EVENT = threading.Event()
POLL_THREAD: Optional[threading.Thread] = None


def _poll_loop() -> None:
    while not STOP_EVENT.is_set():
        STATE.poll_once()
        STOP_EVENT.wait(max(POLL_INTERVAL_S, 0.5))


@app.on_event("startup")
def startup() -> None:
    global POLL_THREAD
    # Perform one initial evaluation so /incidents has data quickly, then keep polling in background.
    STATE.poll_once()
    POLL_THREAD = threading.Thread(target=_poll_loop, name="latch-detector-poller", daemon=True)
    POLL_THREAD.start()


@app.on_event("shutdown")
def shutdown() -> None:
    STOP_EVENT.set()
    if POLL_THREAD is not None:
        POLL_THREAD.join(timeout=2)


@app.get("/health")
def health() -> dict:
    return {
        "ok": True,
        "rules_path": str(RULES_PATH),
        "metrics_state_url": METRICS_STATE_URL,
        "last_error": STATE.last_error,
    }


@app.get("/incidents")
def incidents() -> dict:
    active: List[dict] = []
    if STATE.active_incident is not None:
        active = [STATE.active_incident]
    return {
        "timestamp": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "active": active,
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8081)
