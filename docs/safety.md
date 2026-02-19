# Safety Guardrails: Diagnosis Narrative

This project uses a guardrailed narrative step in `services/latch-diagnoser/llm_summarizer.py`.

Runtime mode is controlled by:

- `DIAGNOSIS_MODE=deterministic|llm`
- `LLM_SUMMARIZER_URL` (required only for `llm` mode)

## Rules

- The summarizer may only format facts from rule-based diagnosis output.
- It must not invent metrics, thresholds, incidents, or remediation steps.
- Every narrative must include a `Sources` section.
- `Sources` must reference internal evidence field names (for example `state.replicas[].qps`), not web links.
- If required evidence fields are missing, diagnosis must fail closed or lower confidence.
- In `llm` mode, if response is invalid or endpoint fails, fallback must be deterministic.

## LLM endpoint contract

When `DIAGNOSIS_MODE=llm`, the diagnoser sends:

```json
{
  "guardrails": {
    "facts_only": true,
    "must_include_sources": true,
    "no_external_links": true
  },
  "diagnosis": { "..." : "rule-based facts" }
}
```

Expected response:

```json
{
  "narrative": "Human-readable explanation with a Sources section."
}
```

## Why this is safe

- Deterministic detector generates incident facts.
- Diagnoser computes root-cause hypothesis from those facts.
- Summarizer only reformats this fixed fact set into human-readable text.

This keeps explanation quality high without allowing hallucinated operational guidance.
