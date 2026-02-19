# Phase 2 Metrics (Issue 2.1)

This setup uses Prometheus scraping and DCGM exporter for GPU visibility.

## Deployment Files

- `/Users/aarushijain/Documents/New project/deploy/observability/prometheus.yaml`
- `/Users/aarushijain/Documents/New project/deploy/observability/dcgm-exporter.yaml`

Apply:

```bash
kubectl apply -f deploy/observability/dcgm-exporter.yaml
kubectl apply -f deploy/observability/prometheus.yaml
```

Open Prometheus UI:

```bash
kubectl -n observability port-forward svc/prometheus 9090:9090
```

Live per-pod table while traffic runs:

```bash
NAMESPACE=phase1full make metrics-live
# optional:
# INTERVAL_S=2 ITERATIONS=30 NAMESPACE=phase1full make metrics-live
```

Generate traffic automatically while printing metrics:

```bash
NAMESPACE=phase1full ITERATIONS=20 make metrics-live-traffic
```

## Scrape Targets

- `job="vllm"`: vLLM pods via `vllm` service on port `8000`
- `job="llmd_scheduler_epp"`: llm-d scheduler EPP via `gaie-*-epp` services on port `9090`
- `job="dcgm_exporter"`: GPU metrics from `kube-system/dcgm-exporter` on port `9400`

## Required Metrics and Mapping

### 1) Request rate / concurrency (per replica)

- `vllm:request_success_total` (counter)
- `vllm:num_requests_running` (gauge)

PromQL:

```promql
sum by (namespace, pod) (rate(vllm:request_success_total[1m]))
sum by (namespace, pod) (vllm:num_requests_running)
```

### 2) TTFT and latency histogram (p95/p99)

- TTFT histogram: `vllm:time_to_first_token_seconds_bucket`
- End-to-end latency histogram: `vllm:e2e_request_latency_seconds_bucket`

PromQL:

```promql
histogram_quantile(0.95, sum by (le, namespace, pod) (rate(vllm:time_to_first_token_seconds_bucket[5m])))
histogram_quantile(0.99, sum by (le, namespace, pod) (rate(vllm:time_to_first_token_seconds_bucket[5m])))

histogram_quantile(0.95, sum by (le, namespace, pod) (rate(vllm:e2e_request_latency_seconds_bucket[5m])))
histogram_quantile(0.99, sum by (le, namespace, pod) (rate(vllm:e2e_request_latency_seconds_bucket[5m])))
```

### 3) Tokens/sec throughput

- Prefill tokens: `vllm:prompt_tokens_total`
- Generation tokens: `vllm:generation_tokens_total`

PromQL:

```promql
sum by (namespace, pod) (rate(vllm:prompt_tokens_total[1m]))
sum by (namespace, pod) (rate(vllm:generation_tokens_total[1m]))
```

### 4) Queue depth / in-flight requests

- Queue depth: `vllm:num_requests_waiting`
- In-flight: `vllm:num_requests_running`
- Queue-time distribution: `vllm:request_queue_time_seconds_bucket`

PromQL:

```promql
sum by (namespace, pod) (vllm:num_requests_waiting)
sum by (namespace, pod) (vllm:num_requests_running)
histogram_quantile(0.95, sum by (le, namespace, pod) (rate(vllm:request_queue_time_seconds_bucket[5m])))
```

### 5) GPU util + memory used

From DCGM exporter (per GPU / MIG instance depending on runtime mapping):

- Utilization:
  - Preferred (if exposed): `DCGM_FI_DEV_GPU_UTIL`
  - MIG-safe fallback used on this cluster: `DCGM_FI_PROF_GR_ENGINE_ACTIVE` (0..1 ratio)
- Framebuffer memory used: `DCGM_FI_DEV_FB_USED`

PromQL:

```promql
avg by (pod, namespace, gpu, UUID) (DCGM_FI_DEV_GPU_UTIL)
or
100 * avg by (pod, namespace, gpu, UUID) (DCGM_FI_PROF_GR_ENGINE_ACTIVE)

avg by (pod, namespace, gpu, UUID) (DCGM_FI_DEV_FB_USED)
```

## Notes

- Metric names above are from live vLLM `/metrics` on this cluster.
- On this MIG cluster, `DCGM_FI_DEV_GPU_UTIL` is not emitted; use `DCGM_FI_PROF_GR_ENGINE_ACTIVE` for utilization.
- If model serving config changes, labels like `model_name` can differ but metric names remain stable.
- llm-d scheduler metrics are scraped; use them for deeper routing/scheduling diagnostics as needed.
