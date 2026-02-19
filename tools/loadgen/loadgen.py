#!/usr/bin/env python3
from __future__ import annotations

import argparse
import concurrent.futures as cf
import json
import math
import random
import statistics
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Optional


@dataclass(frozen=True)
class Result:
    ok: bool
    status_code: Optional[int]
    latency_s: float
    error: Optional[str] = None


def percentile(sorted_values: list[float], pct: float) -> float:
    if not sorted_values:
        return float("nan")
    if pct <= 0:
        return sorted_values[0]
    if pct >= 100:
        return sorted_values[-1]
    k = int((pct / 100.0) * len(sorted_values))
    if k <= 0:
        return sorted_values[0]
    if k >= len(sorted_values):
        return sorted_values[-1]
    return sorted_values[k - 1]


def tokenish_text(token_count: int) -> str:
    if token_count <= 0:
        return ""
    return " ".join(["token"] * token_count)


def request_once(
    url: str,
    model: str,
    timeout_s: float,
    max_tokens: int,
    user_content: str,
) -> Result:
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": "You are concise."},
            {"role": "user", "content": user_content},
        ],
        "max_tokens": max_tokens,
        "temperature": 0,
    }
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        headers={
            "Content-Type": "application/json",
            # Avoid long-lived client connections that can hide per-request balancing.
            "Connection": "close",
        },
        method="POST",
    )
    start = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            raw = resp.read()
            latency_s = time.monotonic() - start
            status_code = getattr(resp, "status", None)
            if status_code != 200:
                return Result(False, status_code, latency_s, error=f"status={status_code}")
            parsed = json.loads(raw.decode("utf-8", errors="replace"))
            choices = parsed.get("choices")
            if isinstance(choices, list) and choices:
                return Result(True, status_code, latency_s)
            return Result(False, status_code, latency_s, error="missing choices")
    except urllib.error.HTTPError as e:
        latency_s = time.monotonic() - start
        return Result(False, e.code, latency_s, error=f"http_error:{e.code}")
    except Exception as e:  # noqa: BLE001
        latency_s = time.monotonic() - start
        return Result(False, None, latency_s, error=str(e))


def summarize(results: list[Result], wall_s: float, mode: str) -> dict:
    latencies = [r.latency_s for r in results if r.ok]
    lat_sorted = sorted(latencies)
    total = len(results)
    ok = sum(1 for r in results if r.ok)
    errors = total - ok
    error_counts: dict[str, int] = {}
    for r in results:
        if r.ok:
            continue
        key = r.error or "unknown"
        error_counts[key] = error_counts.get(key, 0) + 1

    return {
        "mode": mode,
        "duration_s": wall_s,
        "requests_total": total,
        "ok": ok,
        "errors": errors,
        "qps": (total / wall_s) if wall_s > 0 else 0.0,
        "latency_s": {
            "mean": statistics.mean(lat_sorted) if lat_sorted else float("nan"),
            "p50": percentile(lat_sorted, 50),
            "p95": percentile(lat_sorted, 95),
            "p99": percentile(lat_sorted, 99),
            "min": lat_sorted[0] if lat_sorted else float("nan"),
            "max": lat_sorted[-1] if lat_sorted else float("nan"),
        },
        "error_breakdown": error_counts,
    }


def run_load(args: argparse.Namespace) -> dict:
    endpoint = args.endpoint.rstrip("/") + "/v1/chat/completions"
    start = time.monotonic()
    end = start + args.duration_s
    futures: set[cf.Future[Result]] = set()
    results: list[Result] = []

    rng = random.Random(args.seed)

    def pick_user_tokens() -> int:
        if rng.random() < args.long_prompt_ratio:
            return args.long_user_tokens
        return args.short_user_tokens

    def build_user_content(req_id: int) -> str:
        user_tokens = pick_user_tokens()
        base = tokenish_text(user_tokens) or "say hello"
        if not args.unique_prompts:
            return base
        return f"req_id={req_id} nonce={rng.getrandbits(32)} {base}"

    def effective_rps(now: float) -> float:
        if args.mode == "steady":
            return args.steady_rps
        burst_start = start + args.burst_after_s
        burst_end = burst_start + args.burst_for_s
        if burst_start <= now <= burst_end:
            return args.burst_rps
        return args.steady_rps

    with cf.ThreadPoolExecutor(max_workers=args.concurrency) as pool:
        next_send = start
        req_id = 0
        while True:
            now = time.monotonic()
            if now >= end:
                break

            rps = max(effective_rps(now), 0.01)
            send_interval = 1.0 / rps

            if now >= next_send:
                if len(futures) >= args.concurrency:
                    done, futures = cf.wait(futures, return_when=cf.FIRST_COMPLETED)
                    for fut in done:
                        results.append(fut.result())
                fut = pool.submit(
                    request_once,
                    endpoint,
                    args.model,
                    args.timeout_s,
                    args.max_tokens,
                    build_user_content(req_id),
                )
                req_id += 1
                futures.add(fut)
                next_send = max(next_send + send_interval, now)
            else:
                time.sleep(min(0.005, next_send - now))

        for fut in cf.as_completed(futures):
            results.append(fut.result())

    wall_s = time.monotonic() - start
    return summarize(results, wall_s, args.mode)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Load generator for llm-d / vLLM OpenAI endpoint")
    p.add_argument("--endpoint", required=True, help="Base URL, e.g. http://127.0.0.1:18080")
    p.add_argument("--model", default="tinyllama")
    p.add_argument("--mode", choices=["steady", "burst"], default="steady")
    p.add_argument("--duration-s", type=float, default=60.0)
    p.add_argument("--concurrency", type=int, default=16)
    p.add_argument("--steady-rps", type=float, default=8.0)
    p.add_argument("--burst-rps", type=float, default=40.0)
    p.add_argument("--burst-after-s", type=float, default=10.0)
    p.add_argument("--burst-for-s", type=float, default=10.0)
    p.add_argument("--long-prompt-ratio", type=float, default=0.3)
    p.add_argument("--short-user-tokens", type=int, default=24)
    p.add_argument("--long-user-tokens", type=int, default=400)
    p.add_argument("--max-tokens", type=int, default=32)
    p.add_argument("--timeout-s", type=float, default=120.0)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--unique-prompts", action="store_true")
    return p


def main() -> int:
    args = build_parser().parse_args()
    result = run_load(args)
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
