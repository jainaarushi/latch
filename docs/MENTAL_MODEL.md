# Mental Model

Think "thermostat", not "dashboard".

- Signals: small set of real-time aggregates (p95 latency, queue depth, cost rate)
- Decisions: rules/policies that map intent + signals -> actions
- Actions: enforceable changes in request path (route model, cap tokens, summarize context)
- Verification: check if actions improved the signals; otherwise adjust

If a change does not affect Decisions or Actions, it likely does not belong in MVP.
