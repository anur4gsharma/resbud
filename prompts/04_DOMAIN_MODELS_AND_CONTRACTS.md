# Prompt 04 — Domain Models and Contract Alignment

```text
Implement Resbud's domain and API data models from the reconciled contracts. Read the paper schema and generation request schema carefully. Do not invent a parallel schema.

Create typed representations for the research brief/project context, reference input, paper section, paper draft, review warning, generation metadata, section-regeneration request/response, import result if defined, and stable application error types. Separate transport schemas from domain models only where that boundary provides real value.

Requirements:
- Reject unknown fields and invalid enums where the contract requires strictness.
- Enforce size limits and stable section/reference IDs.
- Validate unique section IDs and any other invariants the specification explicitly requires; do not introduce unsupported academic rules.
- Preserve user-supplied reference text verbatim unless the specification states otherwise.
- Distinguish provided, explicitly unavailable/not collected, and unknown/not supplied facts.
- Ensure `review_warnings` and paper warnings have the same source of truth; resolve schema mismatch rather than duplicating incompatible definitions.
- Keep API response objects serializable and deterministic.
- Add tests for valid fixtures, missing required fields, over-limit input, invalid enums, extra properties, duplicate section IDs, malformed IDs, and nullability rules.

Add contract tests that validate fixtures against the JSON Schemas, or explain and implement the strongest available equivalence check if a JSON Schema library is not already selected. Validate OpenAPI and JSON Schema files. Do not call an LLM in this task.
```
