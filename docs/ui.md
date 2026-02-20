# Minimal Dashboard (Phase UI)

This UI shows:

- live metrics panel (QPS, TTFT p95, latency p95, max GPU util)
- active incidents list
- diagnosis view (markdown rendering)
- actions: **Apply Fix** and **Rollback**

## Components

- `services/latch-api-gateway/`
  - proxies `state`, `incidents`, `diagnosis`
  - exposes fix actions:
    - `POST /fix/apply` (restore all backends)
    - `POST /fix/rollback` (re-introduce skew)
- `ui/`
  - static React dashboard served by nginx
  - nginx proxies `/api/*` to `latch-api-gateway`

## Deploy

```bash
NAMESPACE=kubnamespace make up-latch-metrics
NAMESPACE=kubnamespace make up-latch-detector
NAMESPACE=kubnamespace make up-latch-diagnoser
NAMESPACE=kubnamespace make up-latch-api-gateway
NAMESPACE=kubnamespace make up-latch-ui
```

## Open dashboard

```bash
kubectl -n kubnamespace port-forward svc/latch-ui 18088:8088
```

Open: `http://127.0.0.1:18088`

## API quick checks

```bash
kubectl -n kubnamespace port-forward svc/latch-api-gateway 18090:8090
curl -s http://127.0.0.1:18090/health | jq .
curl -s http://127.0.0.1:18090/state | jq .
curl -s http://127.0.0.1:18090/incidents | jq .
```
