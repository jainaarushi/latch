# Architecture

Components:
- Control plane: takes intents + context, enforces policy, decides action
- Runtime: executes decisions against a simulated llm-d
- Metrics: records outcomes and signals

Flow:
1. Input arrives with intent + context
2. Policy engine resolves latency vs cost constraints
3. Decision engine selects action
4. Translator produces runtime constraints
5. Runtime executes and returns response
6. Feedback loop verifies SLA and records metrics
