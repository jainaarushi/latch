# latch

Reference implementation of an LLM intent control plane with a small runtime and demo.

## Structure
- `control_plane/`: intent parsing, policy evaluation, decisions, translation, feedback loop
- `runtime/`: request context and fake LLM runtime
- `metrics/`: metrics collection and rolling stats
- `demo/`: demo agent and traffic simulator
- `configs/`: default intents and policies
- `docs/`: architecture and design docs

## Quick start
```bash
python3 demo/run_demo.py
```

## Notes
This is intentionally small and not production-ready. It is meant to validate the control loop architecture.
