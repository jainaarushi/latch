from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Dict, List, Optional

import httpx
from fastapi import FastAPI, HTTPException

from llm_summarizer import summarize_diagnosis

DETECTOR_INCIDENTS_URL = os.getenv("DETECTOR_INCIDENTS_URL", "http://latch-detector:8081/incidents")
METRICS_STATE_URL = os.getenv("METRICS_STATE_URL", "http://latch-metrics:8080/state")
REQUEST_TIMEOUT_S = float(os.getenv("REQUEST_TIMEOUT_S", "10"))
IMBALANCE_TEMPLATE = Path(os.getenv("IMBALANCE_TEMPLATE", "/app/imbalance.md"))
DIAGNOSIS_MODE = os.getenv("DIAGNOSIS_MODE", "deterministic")
LLM_SUMMARIZER_URL = os.getenv("LLM_SUMMARIZER_URL", "")

app = FastAPI(title="latch-diagnoser", version="0.1.0")


def _resolve_template() -> Path:
    candidates = [
        IMBALANCE_TEMPLATE,
        Path("/app/imbalance.md"),
        Path("/app/templates/imbalance.md"),
        Path(__file__).resolve().parent / "templates" / "imbalance.md",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return IMBALANCE_TEMPLATE


def _get_json(url: str) -> Dict[str, Any]:
    with httpx.Client(timeout=REQUEST_TIMEOUT_S) as client:
        resp = client.get(url)
        resp.raise_for_status()
        return resp.json()


def _find_incident(incident_id: str, incidents_payload: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    for inc in incidents_payload.get("active", []):
        if inc.get("id") == incident_id:
            return inc
    return None


def _replica_lines(replicas: List[Dict[str, Any]]) -> List[str]:
    if not replicas:
        return []
    sorted_replicas = sorted(replicas, key=lambda x: float(x.get("qps", 0.0)), reverse=True)
    qps_parts = [f"{r.get('name')} qps={float(r.get('qps', 0.0)):.3g}" for r in sorted_replicas]
    queue_parts = [f"{r.get('name')} queue={float(r.get('queue', 0.0)):.3g}" for r in sorted_replicas]
    return [
        " vs ".join(qps_parts),
        " vs ".join(queue_parts),
    ]


def _confidence(skew: float, ttft_increase_pct: float, max_queue: float) -> float:
    score = 0.45
    score += min(0.25, max(0.0, (skew - 1.0) / 10.0))
    score += min(0.20, max(0.0, ttft_increase_pct / 200.0))
    score += min(0.10, max(0.0, max_queue / 20.0))
    return round(min(0.99, max(0.50, score)), 2)


def _build_diagnosis(incident_id: str, incident: Dict[str, Any], state_payload: Dict[str, Any]) -> Dict[str, Any]:
    evidence = incident.get("evidence", {})
    replicas = state_payload.get("replicas", [])
    global_metrics = state_payload.get("global", {})

    skew = float(evidence.get("qps_skew", 0.0))
    skew_threshold = float(evidence.get("qps_skew_threshold", 0.0))
    ttft_current = float(evidence.get("ttft_p95_ms", global_metrics.get("ttft_p95_ms", 0.0)))
    ttft_baseline = float(evidence.get("baseline_ttft_p95_ms", 0.0))
    ttft_increase = float(evidence.get("ttft_p95_increase_pct", 0.0))
    ttft_threshold = float(evidence.get("ttft_p95_increase_pct_threshold", 0.0))
    max_queue = max((float(r.get("queue", 0.0)) for r in replicas), default=0.0)

    evidence_lines = []
    evidence_lines.extend(_replica_lines(replicas))
    evidence_lines.append(
        f"Global TTFT p95 increased {ttft_baseline:.1f}ms -> {ttft_current:.1f}ms ({ttft_increase:+.1f}%)"
    )
    evidence_lines.append(
        f"QPS skew {skew:.2f}x exceeded threshold {skew_threshold:.2f}x"
    )
    evidence_lines.append(
        f"TTFT increase threshold check: {ttft_increase:+.1f}% > {ttft_threshold:+.1f}%"
    )

    diagnosis: Dict[str, Any] = {
        "incident_id": incident_id,
        "incident_type": incident.get("type", "UNKNOWN"),
        "root_cause": "Traffic routing skew is overloading a single replica.",
        "confidence": _confidence(skew, ttft_increase, max_queue),
        "evidence": evidence_lines,
        "next_checks": [
            "Inspect route weights in deploy/scenarios/imbalance.yaml or gateway policy.",
            "Verify per-replica request counters stay balanced after weight reset.",
            "Confirm queue depth and TTFT p95 normalize within 2-5 minutes.",
        ],
        "recommendation": "Switch to load-aware routing (or reset weights to 34/33/33). Expected impact: TTFT p95 down ~30-50% with fewer queue spikes.",
        "risk": "Low (config-only change, reversible).",
        "rollback": "Restore previous routing weights.",
        "sources": [
            "incidents.active[].evidence.qps_skew",
            "incidents.active[].evidence.qps_skew_threshold",
            "incidents.active[].evidence.ttft_p95_increase_pct",
            "incidents.active[].evidence.ttft_p95_increase_pct_threshold",
            "incidents.active[].evidence.ttft_p95_ms",
            "incidents.active[].evidence.baseline_ttft_p95_ms",
            "state.replicas[].qps",
            "state.replicas[].queue",
            "state.global.ttft_p95_ms",
        ],
    }
    narrative, narrative_mode = summarize_diagnosis(
        diagnosis=diagnosis,
        template_path=_resolve_template(),
        mode=DIAGNOSIS_MODE,
        llm_summarizer_url=LLM_SUMMARIZER_URL,
        timeout_s=REQUEST_TIMEOUT_S,
    )
    diagnosis["narrative"] = narrative
    diagnosis["diagnosis_mode"] = DIAGNOSIS_MODE
    diagnosis["narrative_mode"] = narrative_mode
    return diagnosis


@app.get("/health")
def health() -> dict:
    return {
        "ok": True,
        "detector_incidents_url": DETECTOR_INCIDENTS_URL,
        "metrics_state_url": METRICS_STATE_URL,
        "template": str(IMBALANCE_TEMPLATE),
        "diagnosis_mode": DIAGNOSIS_MODE,
        "llm_summarizer_url_configured": bool(LLM_SUMMARIZER_URL.strip()),
    }


@app.get("/incidents/{incident_id}/diagnosis")
def diagnosis(incident_id: str) -> Dict[str, Any]:
    try:
        incidents_payload = _get_json(DETECTOR_INCIDENTS_URL)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"failed to fetch incidents: {exc}") from exc

    incident = _find_incident(incident_id, incidents_payload)
    if not incident:
        raise HTTPException(status_code=404, detail=f"incident '{incident_id}' not found in active incidents")

    incident_type = incident.get("type")
    if incident_type != "IMBALANCE":
        raise HTTPException(status_code=400, detail=f"unsupported incident type '{incident_type}'")

    try:
        state_payload = _get_json(METRICS_STATE_URL)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"failed to fetch state: {exc}") from exc

    return _build_diagnosis(incident_id, incident, state_payload)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8082)
