from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List


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
