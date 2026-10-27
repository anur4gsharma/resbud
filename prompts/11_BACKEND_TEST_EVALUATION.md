# Prompt 11 — Backend Test Hardening and AI Evaluation Set

```text
Audit and improve backend tests for Resbud. Do not add features unrelated to testability. Read the test/evaluation document and map every P0 backend requirement to a test.

Add or organize:
- Unit tests for pure domain rules, schema parsing, prompt builder, integrity checks, export formatting, and error mapping.
- API tests for all routes, status codes, headers, stable error shapes, body limits, auth behavior where applicable, and request IDs.
- Provider adapter tests with mocked SDK calls; no paid network dependency in CI.
- Regression tests for data preservation and non-target section preservation.
- Security tests for prompt injection as input data, malformed/untrusted model output, secret redaction, unsafe filenames, unsupported file types, and oversized content.
- Contract tests that compare the OpenAPI implementation with its schemas as far as the toolchain supports.

Create a versioned evaluation fixture set with several research input profiles: complete input, missing results, missing methods, conflicting claims, incomplete references, non-experimental research, and unusual academic structure. For each case, define deterministic expectations such as schema validity, reference preservation, required warnings, no fabricated metrics in fake-provider output, and sections not being lost. Avoid pretending heuristic automated checks can establish scientific truth.

Use coverage as a diagnostic, not as the only quality metric. Make test names explain behavior. Run formatting/lint/type checks and pytest. Report actual results, test gaps, and any tests not run. Do not lower assertion strength just to produce a green build.
```
