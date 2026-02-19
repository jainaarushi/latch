from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

import httpx


def _bullet(lines: List[str]) -> str:
    if not lines:
        return "- none"
    return "\n".join(f"- {line}" for line in lines)


def render_imbalance_summary(diagnosis: Dict[str, Any], template_path: Path) -> str:
    """
    Guardrailed narrative formatter.

    This function does not invent facts. It only formats fields already computed by
    rule-based diagnosis and appends explicit source field references.
    """
    template = template_path.read_text(encoding="utf-8")
    evidence_lines = _bullet(diagnosis.get("evidence", []))
    next_checks_lines = _bullet(diagnosis.get("next_checks", []))
    sources_lines = _bullet(diagnosis.get("sources", []))
    return template.format(
        incident_id=diagnosis.get("incident_id", "unknown"),
        root_cause=diagnosis.get("root_cause", "unknown"),
        confidence=diagnosis.get("confidence", 0.0),
        evidence_lines=evidence_lines,
        next_checks_lines=next_checks_lines,
        recommendation=diagnosis.get("recommendation", ""),
        risk=diagnosis.get("risk", ""),
        rollback=diagnosis.get("rollback", ""),
        sources_lines=sources_lines,
    )


def summarize_diagnosis(
    diagnosis: Dict[str, Any],
    template_path: Path,
    mode: str = "deterministic",
    llm_summarizer_url: str = "",
    timeout_s: float = 10.0,
) -> tuple[str, str]:
    """
    Returns (narrative, narrative_mode).

    - deterministic mode: local template rendering.
    - llm mode: calls an external summarizer endpoint with facts-only payload.
      If unavailable or invalid, falls back to deterministic rendering.
    """
    deterministic = render_imbalance_summary(diagnosis, template_path)
    selected_mode = (mode or "deterministic").strip().lower()
    if selected_mode != "llm":
        return deterministic, "deterministic"

    if not llm_summarizer_url.strip():
        return deterministic, "deterministic-fallback(no-llm-url)"

    payload = {
        "guardrails": {
            "facts_only": True,
            "must_include_sources": True,
            "no_external_links": True,
        },
        "diagnosis": diagnosis,
    }
    try:
        with httpx.Client(timeout=timeout_s) as client:
            resp = client.post(llm_summarizer_url, json=payload)
            resp.raise_for_status()
            body = resp.json()
        narrative = str(body.get("narrative", "")).strip()
        has_sources = "Sources:" in narrative
        if narrative and has_sources:
            return narrative, "llm"
        return deterministic, "deterministic-fallback(invalid-llm-response)"
    except Exception:
        return deterministic, "deterministic-fallback(llm-error)"
