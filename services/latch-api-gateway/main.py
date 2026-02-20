from __future__ import annotations

import os
from typing import Any, Dict, List, Optional

import httpx
from fastapi import FastAPI, HTTPException
from kubernetes import client, config

METRICS_STATE_URL = os.getenv("METRICS_STATE_URL", "http://latch-metrics:8080/state")
DETECTOR_INCIDENTS_URL = os.getenv("DETECTOR_INCIDENTS_URL", "http://latch-detector:8081/incidents")
DIAGNOSER_BASE_URL = os.getenv(
    "DIAGNOSER_BASE_URL",
    "http://latch-diagnoser:8082/incidents",
)
REQUEST_TIMEOUT_S = float(os.getenv("REQUEST_TIMEOUT_S", "10"))
TARGET_NAMESPACE = os.getenv("TARGET_NAMESPACE", "kubnamespace")
VLLM_SELECTOR = os.getenv("VLLM_SELECTOR", "app.kubernetes.io/name=vllm")
INFERENCE_LABEL_KEY = os.getenv("INFERENCE_LABEL_KEY", "llm-d.ai/inference-serving")
DEFAULT_KEEP_POD = os.getenv("DEFAULT_KEEP_POD", "")

app = FastAPI(title="latch-api-gateway", version="0.1.0")


def _load_k8s_client() -> client.CoreV1Api:
    try:
        config.load_incluster_config()
    except Exception:
        config.load_kube_config()
    return client.CoreV1Api()


K8S = _load_k8s_client()


def _get_json(url: str) -> Dict[str, Any]:
    with httpx.Client(timeout=REQUEST_TIMEOUT_S) as http:
        resp = http.get(url)
        resp.raise_for_status()
        return resp.json()


def _list_vllm_pods() -> List[client.V1Pod]:
    pod_list = K8S.list_namespaced_pod(
        namespace=TARGET_NAMESPACE,
        label_selector=VLLM_SELECTOR,
    )
    return sorted(pod_list.items, key=lambda p: p.metadata.name or "")


def _set_membership(all_true: bool, keep_pod: Optional[str] = None) -> Dict[str, Any]:
    pods = _list_vllm_pods()
    if not pods:
        raise HTTPException(status_code=404, detail="no vLLM pods found")

    if keep_pod and keep_pod not in [p.metadata.name for p in pods]:
        raise HTTPException(status_code=400, detail=f"keep_pod '{keep_pod}' not found")

    if not all_true and not keep_pod:
        keep_pod = DEFAULT_KEEP_POD or (pods[0].metadata.name or "")

    changed: List[Dict[str, str]] = []
    for pod in pods:
        name = pod.metadata.name or ""
        desired = "true" if all_true or name == keep_pod else "false"
        body = {"metadata": {"labels": {INFERENCE_LABEL_KEY: desired}}}
        K8S.patch_namespaced_pod(name=name, namespace=TARGET_NAMESPACE, body=body)
        changed.append({"pod": name, INFERENCE_LABEL_KEY: desired})

    return {
        "namespace": TARGET_NAMESPACE,
        "selector": VLLM_SELECTOR,
        "label_key": INFERENCE_LABEL_KEY,
        "all_true": all_true,
        "keep_pod": keep_pod,
        "changed": changed,
    }


@app.get("/health")
def health() -> Dict[str, Any]:
    return {
        "ok": True,
        "namespace": TARGET_NAMESPACE,
        "state_url": METRICS_STATE_URL,
        "incidents_url": DETECTOR_INCIDENTS_URL,
        "diagnoser_base_url": DIAGNOSER_BASE_URL,
    }


@app.get("/state")
def state() -> Dict[str, Any]:
    return _get_json(METRICS_STATE_URL)


@app.get("/incidents")
def incidents() -> Dict[str, Any]:
    return _get_json(DETECTOR_INCIDENTS_URL)


@app.get("/diagnosis/{incident_id}")
def diagnosis(incident_id: str) -> Dict[str, Any]:
    url = f"{DIAGNOSER_BASE_URL}/{incident_id}/diagnosis"
    try:
        return _get_json(url)
    except httpx.HTTPStatusError as exc:
        raise HTTPException(status_code=exc.response.status_code, detail=exc.response.text) from exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"failed to query diagnoser: {exc}") from exc


@app.post("/fix/apply")
def apply_fix() -> Dict[str, Any]:
    # Apply fix = restore all backends to serving membership.
    return {"result": _set_membership(all_true=True)}


@app.post("/fix/rollback")
def rollback_fix(payload: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    keep = None
    if payload and isinstance(payload, dict):
        keep = payload.get("keep_pod")
    return {"result": _set_membership(all_true=False, keep_pod=keep)}

