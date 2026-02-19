from __future__ import annotations

import os
from datetime import datetime, timezone
from typing import Dict, List

import httpx
from fastapi import FastAPI

PROM_URL = os.getenv("PROMETHEUS_URL", "http://prometheus.observability.svc.cluster.local:9090")
TARGET_NAMESPACE = os.getenv("TARGET_NAMESPACE", "kubnamespace")
REQUEST_TIMEOUT_S = float(os.getenv("REQUEST_TIMEOUT_S", "10"))

app = FastAPI(title="latch-metrics", version="0.1.0")


def _iso_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _query(client: httpx.Client, expr: str) -> List[dict]:
    resp = client.get(
        f"{PROM_URL}/api/v1/query",
        params={"query": expr},
        timeout=REQUEST_TIMEOUT_S,
    )
    resp.raise_for_status()
    body = resp.json()
    if body.get("status") != "success":
        raise RuntimeError(f"prometheus query failed: {expr}")
    return body.get("data", {}).get("result", [])


def _pod_map(result: List[dict]) -> Dict[str, float]:
    values: Dict[str, float] = {}
    for row in result:
        pod = row.get("metric", {}).get("pod")
        value = row.get("value", [None, "0"])[1]
        if pod:
            try:
                values[pod] = float(value)
            except (TypeError, ValueError):
                continue
    return values


def _scalar(result: List[dict]) -> float:
    if not result:
        return 0.0
    value = result[0].get("value", [None, "0"])[1]
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


@app.get("/health")
def health() -> dict:
    return {"ok": True}


@app.get("/state")
def state() -> dict:
    ns = TARGET_NAMESPACE
    with httpx.Client() as client:
        qps_by_pod = _pod_map(
            _query(client, f'sum by (pod) (rate(vllm:request_success_total{{namespace="{ns}"}}[1m]))')
        )
        ttft_p95_by_pod = _pod_map(
            _query(
                client,
                (
                    f'1000 * histogram_quantile(0.95, '
                    f'sum by (le,pod) (rate(vllm:time_to_first_token_seconds_bucket{{namespace="{ns}"}}[5m])))'
                ),
            )
        )
        latency_p95_by_pod = _pod_map(
            _query(
                client,
                (
                    f'1000 * histogram_quantile(0.95, '
                    f'sum by (le,pod) (rate(vllm:e2e_request_latency_seconds_bucket{{namespace="{ns}"}}[5m])))'
                ),
            )
        )
        running_by_pod = _pod_map(
            _query(client, f'max by (pod) (vllm:num_requests_running{{namespace="{ns}"}})')
        )
        queue_by_pod = _pod_map(
            _query(client, f'max by (pod) (vllm:num_requests_waiting{{namespace="{ns}"}})')
        )

        gpu_mem_by_pod = _pod_map(
            _query(
                client,
                (
                    f'avg by (pod) (DCGM_FI_DEV_FB_USED{{namespace="{ns}"}}) '
                    f'or label_replace('
                    f'avg by (exported_pod) (DCGM_FI_DEV_FB_USED{{exported_namespace="{ns}"}}), '
                    f'"pod", "$1", "exported_pod", "(.*)")'
                ),
            )
        )

        gpu_util_by_pod = _pod_map(
            _query(
                client,
                (
                    f'avg by (pod) (DCGM_FI_DEV_GPU_UTIL{{namespace="{ns}"}}) '
                    f'or label_replace('
                    f'avg by (exported_pod) (DCGM_FI_DEV_GPU_UTIL{{exported_namespace="{ns}"}}), '
                    f'"pod", "$1", "exported_pod", "(.*)") '
                    f'or 100 * (avg by (pod) (DCGM_FI_PROF_GR_ENGINE_ACTIVE{{namespace="{ns}"}}) '
                    f'or label_replace('
                    f'avg by (exported_pod) (DCGM_FI_PROF_GR_ENGINE_ACTIVE{{exported_namespace="{ns}"}}), '
                    f'"pod", "$1", "exported_pod", "(.*)"))'
                ),
            )
        )

        global_qps = _scalar(
            _query(client, f'sum(rate(vllm:request_success_total{{namespace="{ns}"}}[1m]))')
        )
        global_ttft_p95_ms = _scalar(
            _query(
                client,
                (
                    f'1000 * histogram_quantile(0.95, '
                    f'sum by (le) (rate(vllm:time_to_first_token_seconds_bucket{{namespace="{ns}"}}[5m])))'
                ),
            )
        )
        global_latency_p95_ms = _scalar(
            _query(
                client,
                (
                    f'1000 * histogram_quantile(0.95, '
                    f'sum by (le) (rate(vllm:e2e_request_latency_seconds_bucket{{namespace="{ns}"}}[5m])))'
                ),
            )
        )
        global_queue = _scalar(
            _query(client, f'sum(vllm:num_requests_waiting{{namespace="{ns}"}})')
        )

    pod_names = sorted(
        set(qps_by_pod)
        | set(ttft_p95_by_pod)
        | set(latency_p95_by_pod)
        | set(running_by_pod)
        | set(gpu_mem_by_pod)
        | set(gpu_util_by_pod)
    )

    replicas = []
    for pod in pod_names:
        replicas.append(
            {
                "name": pod,
                "qps": round(qps_by_pod.get(pod, 0.0), 3),
                "in_flight": round(running_by_pod.get(pod, 0.0), 3),
                "queue": round(queue_by_pod.get(pod, 0.0), 3),
                "ttft_p95_ms": round(ttft_p95_by_pod.get(pod, 0.0), 3),
                "latency_p95_ms": round(latency_p95_by_pod.get(pod, 0.0), 3),
                "gpu_util": round(gpu_util_by_pod.get(pod, 0.0), 3),
                "gpu_mem_mb": round(gpu_mem_by_pod.get(pod, 0.0), 3),
            }
        )

    return {
        "timestamp": _iso_now(),
        "global": {
            "qps": round(global_qps, 3),
            "ttft_p95_ms": round(global_ttft_p95_ms, 3),
            "latency_p95_ms": round(global_latency_p95_ms, 3),
            "queue": round(global_queue, 3),
        },
        "replicas": replicas,
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8080)
