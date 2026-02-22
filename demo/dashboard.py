"""
Minimal live dashboard for the local demo loop.

Reads latch demo logs and exposes:
- JSON state at /api/state
- lightweight HTML dashboard at /
"""

from __future__ import annotations

import ast
import os
from collections import defaultdict, deque
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Deque, Dict, List, Optional

from fastapi import FastAPI
from fastapi.responses import HTMLResponse, JSONResponse

app = FastAPI(title="Latch Demo Dashboard", version="0.1.0")


def _default_log_path() -> Path:
    env = os.getenv("LATCH_DEMO_LOG")
    if env:
        return Path(env).expanduser()
    return Path.home() / "latch-demo.log"


def _parse_log(log_path: Path, max_outcomes: int = 200) -> Dict[str, Any]:
    latest_metrics: Dict[str, Dict[str, Any]] = {}
    outcomes: Deque[Dict[str, Any]] = deque(maxlen=max_outcomes)
    mode_counts: Dict[str, int] = defaultdict(int)
    current_mode: Optional[str] = None

    if not log_path.exists():
        return {
            "log_path": str(log_path),
            "exists": False,
            "latest_metrics": {},
            "recent_outcomes": [],
            "mode_counts": {},
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }

    for raw in log_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw.strip()
        if not line:
            continue
        if line == "baseline":
            current_mode = "baseline"
            continue
        if line == "with_control":
            current_mode = "with_control"
            continue
        if line.startswith("metrics "):
            payload = line[len("metrics ") :]
            try:
                parsed = ast.literal_eval(payload)
                if isinstance(parsed, dict):
                    key = current_mode or "unknown"
                    latest_metrics[key] = parsed
            except (ValueError, SyntaxError):
                continue
            continue
        if line.startswith("{") and line.endswith("}"):
            try:
                parsed = ast.literal_eval(line)
                if isinstance(parsed, dict) and "intent" in parsed:
                    record = dict(parsed)
                    record["phase"] = current_mode or "unknown"
                    outcomes.append(record)
                    mode_counts[record.get("phase", "unknown")] += 1
            except (ValueError, SyntaxError):
                continue

    return {
        "log_path": str(log_path),
        "exists": True,
        "latest_metrics": latest_metrics,
        "recent_outcomes": list(outcomes)[-50:],
        "mode_counts": dict(mode_counts),
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/api/state")
def api_state() -> JSONResponse:
    state = _parse_log(_default_log_path())
    return JSONResponse(state)


@app.get("/", response_class=HTMLResponse)
def index() -> HTMLResponse:
    return HTMLResponse(
        """
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Latch Demo Dashboard</title>
    <style>
      :root { --bg:#0f172a; --panel:#111827; --muted:#93a3b8; --fg:#e2e8f0; --ok:#22c55e; --warn:#f59e0b; --bad:#ef4444; --accent:#38bdf8; }
      body { margin:0; background:linear-gradient(160deg,#0b1220,#111827); color:var(--fg); font:14px/1.45 ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto; }
      .wrap { max-width: 1180px; margin: 20px auto; padding: 0 14px 30px; }
      .title { font-size: 24px; font-weight: 700; margin: 8px 0 14px; }
      .meta { color: var(--muted); margin-bottom: 14px; }
      .grid { display:grid; grid-template-columns: repeat(2,minmax(0,1fr)); gap:12px; margin-bottom: 14px; }
      .card { background: rgba(17,24,39,.88); border:1px solid rgba(148,163,184,.2); border-radius:12px; padding:12px; }
      .card h3 { margin:0 0 8px; font-size:13px; letter-spacing:.02em; color:#cbd5e1; text-transform:uppercase; }
      .metric { display:flex; justify-content:space-between; padding:2px 0; color:#dbe7f5; }
      table { width:100%; border-collapse:collapse; background:rgba(17,24,39,.88); border:1px solid rgba(148,163,184,.2); border-radius:12px; overflow:hidden; }
      th, td { padding:8px; border-bottom:1px solid rgba(148,163,184,.15); text-align:left; }
      th { color:#bfdbfe; font-weight:600; }
      .ok { color: var(--ok); } .bad { color: var(--bad); } .warn { color: var(--warn); }
      .pill { display:inline-block; border-radius:999px; padding:2px 8px; border:1px solid rgba(148,163,184,.35); color:#d1e4ff; }
      .phase-baseline { border-color:#475569; color:#cbd5e1; }
      .phase-with_control { border-color: var(--accent); color:#bae6fd; }
      @media (max-width: 900px) { .grid { grid-template-columns: 1fr; } th:nth-child(8), td:nth-child(8) { display:none; } }
    </style>
  </head>
  <body>
    <div class="wrap">
      <div class="title">Latch Demo Dashboard</div>
      <div id="meta" class="meta">Loading...</div>
      <div class="grid">
        <div class="card"><h3>Baseline Metrics</h3><div id="baseline"></div></div>
        <div class="card"><h3>With Control Metrics</h3><div id="with_control"></div></div>
      </div>
      <table>
        <thead>
          <tr>
            <th>Phase</th><th>Intent</th><th>Action</th><th>Reason</th><th>Latency</th><th>Queue</th><th>Cost</th><th>SLO</th>
          </tr>
        </thead>
        <tbody id="rows"></tbody>
      </table>
    </div>
    <script>
      function fmt(v){ return (v===undefined || v===null) ? "-" : String(v); }
      function renderMetrics(el, data){
        const keys = ["count","allow_rate","avg_latency_ms","p95_latency_ms","avg_cost","avg_queue_depth"];
        if(!data){ el.innerHTML = "<div class='metric'>No data yet</div>"; return; }
        el.innerHTML = keys.map(k => `<div class='metric'><span>${k}</span><strong>${fmt(data[k])}</strong></div>`).join("");
      }
      async function tick(){
        const r = await fetch("/api/state", {cache:"no-store"});
        const s = await r.json();
        document.getElementById("meta").textContent = `Log: ${s.log_path} | Updated: ${s.updated_at} | Records: ${s.recent_outcomes.length}`;
        renderMetrics(document.getElementById("baseline"), s.latest_metrics["baseline"]);
        renderMetrics(document.getElementById("with_control"), s.latest_metrics["with_control"]);
        const rows = (s.recent_outcomes || []).slice(-30).reverse().map(o => {
          const ok = o.slo_ok === "true";
          const cls = ok ? "ok" : "bad";
          return `<tr>
            <td><span class="pill phase-${fmt(o.phase)}">${fmt(o.phase)}</span></td>
            <td>${fmt(o.intent)}</td>
            <td>${fmt(o.action)}</td>
            <td>${fmt(o.reason)}</td>
            <td>${fmt(o.latency_ms)}</td>
            <td>${fmt(o.queue_depth)}</td>
            <td>${fmt(o.cost)}</td>
            <td class="${cls}">${fmt(o.slo_ok)}</td>
          </tr>`;
        }).join("");
        document.getElementById("rows").innerHTML = rows || "<tr><td colspan='8'>No outcomes yet</td></tr>";
      }
      tick();
      setInterval(tick, 2000);
    </script>
  </body>
</html>
"""
    )
