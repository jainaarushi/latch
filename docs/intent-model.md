# Intent Model

An intent is a structured request with:
- `name`: short string
- `priority`: int (higher = more important)
- `max_latency_ms`: SLA budget
- `max_cost`: cost budget
- `constraints`: list of policy constraints
- `params`: free-form dict for runtime
