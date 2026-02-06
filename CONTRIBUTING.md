# Contributing (MVP rules)

Before adding a feature, answer:

1) Does it change decisions or enforcement in the request path?
2) Is it required to demonstrate stabilization under load?
3) Can it be mocked without affecting the control loop?

If "no" -> do not build it in MVP.

Prefer:
- deterministic rules over ML/optimization
- fake runtimes over real GPUs
- logs of decisions over dashboards
