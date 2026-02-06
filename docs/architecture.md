# Architecture

Components:
- Control plane: takes intents + context, enforces policy, decides action
- Runtime: executes decisions against a (fake) LLM
- Metrics: records outcomes and signals

Flow:
1. Input arrives with intent + context
2. Policy engine evaluates constraints
3. Decision engine selects action
4. Translator produces runtime request
5. Runtime executes and returns response
6. Feedback loop records outcome + metrics
