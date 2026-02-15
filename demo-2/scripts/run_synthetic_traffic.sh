#!/usr/bin/env bash
set -euo pipefail

PROFILE_FILE="${1:-}"

if [[ -n "$PROFILE_FILE" && ! -f "$PROFILE_FILE" ]]; then
  echo "Profile file not found: $PROFILE_FILE" >&2
  exit 1
fi

RAW_PROFILE="{}"
if [[ -n "$PROFILE_FILE" ]]; then
  RAW_PROFILE="$(cat "$PROFILE_FILE")"
fi

COMPACT_PROFILE="$(python3 - <<'PY' "$RAW_PROFILE"
import json
import sys

raw = sys.argv[1]
try:
    obj = json.loads(raw)
except Exception as e:
    raise SystemExit(f"Invalid JSON profile: {e}")
print(json.dumps(obj, separators=(",", ":")))
PY
)"

NAMESPACE="$(python3 - <<'PY' "$COMPACT_PROFILE"
import json
import sys
obj = json.loads(sys.argv[1])
print(obj.get("namespace", "kubnamespace"))
PY
)"

RUNNER_POD="llm-traffic-$(date +%s)"

# Optional: place traffic pod on a specific node via profile key traffic_node_name.
TRAFFIC_NODE="$(python3 - <<'PY' "$COMPACT_PROFILE"
import json
import sys
obj = json.loads(sys.argv[1])
print(obj.get("traffic_node_name", ""))
PY
)"

OVERRIDES="{}"
if [[ -n "$TRAFFIC_NODE" ]]; then
  OVERRIDES="{\"apiVersion\":\"v1\",\"spec\":{\"nodeName\":\"${TRAFFIC_NODE}\"}}"
fi

kubectl -n "$NAMESPACE" run "$RUNNER_POD" \
  --image=python:3.11-alpine \
  --restart=Never \
  --rm -i --quiet \
  --overrides="$OVERRIDES" \
  --env="PROFILE_JSON=$COMPACT_PROFILE" \
  --command -- python - <<'PY'
import json
import os
import random
import statistics
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

profile = json.loads(os.environ.get("PROFILE_JSON", "{}"))
namespace = profile.get("namespace", "kubnamespace")
gateway_uri = profile.get("gateway_uri", f"http://vllm.{namespace}.svc.cluster.local:8000")
model = profile.get("model", "TinyLlama/TinyLlama-1.1B-Chat-v1.0")
total_requests = int(profile.get("total_requests", 200))
concurrency = int(profile.get("concurrency", 16))
stream = bool(profile.get("stream", False))
max_tokens = int(profile.get("max_tokens", 32))
long_system_tokens = int(profile.get("long_system_tokens", 0))
long_user_tokens = int(profile.get("long_user_tokens", 0))
start_spacing_ms = int(profile.get("start_spacing_ms", 0))
jitter_ms = int(profile.get("jitter_ms", 0))
timeout_s = int(profile.get("timeout_s", 120))

def percentile(vals, pct):
    if not vals:
        return float("nan")
    if pct <= 0:
        return vals[0]
    if pct >= 100:
        return vals[-1]
    k = int((pct / 100.0) * len(vals))
    if k <= 0:
        return vals[0]
    if k >= len(vals):
        return vals[-1]
    return vals[k - 1]

def summarize(vals):
    vals = sorted(vals)
    return {
        "mean": statistics.fmean(vals) if vals else float("nan"),
        "p50": percentile(vals, 50),
        "p90": percentile(vals, 90),
        "p95": percentile(vals, 95),
        "p99": percentile(vals, 99),
        "min": vals[0] if vals else float("nan"),
        "max": vals[-1] if vals else float("nan"),
    }

def tokenish(n):
    if n <= 0:
        return ""
    return " ".join(["tok"] * n)

system_prompt = tokenish(long_system_tokens)
user_prompt = "Write a two-line haiku about clouds."
if long_user_tokens > 0:
    user_prompt = f"{user_prompt} {tokenish(long_user_tokens)}"

start_time = time.time()
lock = threading.Lock()
results = []

def one_request(i):
    delay_ms = (i * start_spacing_ms) + (random.randint(0, jitter_ms) if jitter_ms > 0 else 0)
    target = start_time + (delay_ms / 1000.0)
    now = time.time()
    if target > now:
        time.sleep(target - now)

    url = f"{gateway_uri.rstrip('/')}/v1/chat/completions"
    payload = {
        "model": model,
        "stream": stream,
        "max_tokens": max_tokens,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
    }

    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Content-Type", "application/json")

    t0 = time.time()
    ttft = None
    status = None
    err = None
    ok = False

    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            status = int(resp.getcode())
            if stream:
                chunk = resp.read(1)
                ttft = time.time() - t0 if chunk else None
                _ = resp.read()
            else:
                _ = resp.read()
            ok = 200 <= status < 300
    except urllib.error.HTTPError as e:
        status = int(getattr(e, "code", 0) or 0)
        try:
            err = e.read().decode("utf-8", errors="replace")[:500]
        except Exception:
            err = str(e)
    except Exception as e:
        err = str(e)

    lat = time.time() - t0
    with lock:
        results.append({
            "ok": ok,
            "status_code": status,
            "latency_s": lat,
            "ttft_s": ttft,
            "error": err,
        })

workers = max(1, concurrency)
with ThreadPoolExecutor(max_workers=workers) as ex:
    futs = [ex.submit(one_request, i) for i in range(total_requests)]
    for f in as_completed(futs):
        _ = f.result()

ok_results = [r for r in results if r["ok"]]
fail_results = [r for r in results if not r["ok"]]
latencies = [r["latency_s"] for r in ok_results]
ttfts = [r["ttft_s"] for r in ok_results if r["ttft_s"] is not None]

wall_s = max(time.time() - start_time, 1e-9)
summary = {
    "config": {
        "namespace": namespace,
        "gateway_uri": gateway_uri,
        "model": model,
        "total_requests": total_requests,
        "concurrency": concurrency,
        "stream": stream,
        "max_tokens": max_tokens,
        "long_system_tokens": long_system_tokens,
        "long_user_tokens": long_user_tokens,
        "start_spacing_ms": start_spacing_ms,
        "jitter_ms": jitter_ms,
        "timeout_s": timeout_s,
    },
    "counts": {
        "total": len(results),
        "ok": len(ok_results),
        "failed": len(fail_results),
    },
    "http_status_counts": {},
    "latency_s": summarize(latencies),
    "ttft_s": summarize(ttfts) if stream else None,
    "throughput_rps": len(results) / wall_s,
    "error_samples": [r["error"] for r in fail_results if r.get("error")][:5],
}

status_counts = {}
for r in results:
    code = r.get("status_code")
    key = str(code) if code is not None else "none"
    status_counts[key] = status_counts.get(key, 0) + 1
summary["http_status_counts"] = status_counts

print(json.dumps(summary, indent=2))
PY
