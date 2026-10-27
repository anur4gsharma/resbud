# 07 — Testing and AI Quality Evaluation

Testing must establish two different things: whether the software behaves correctly, and whether the generated paper is useful and faithful to the supplied research. One does not prove the other.

## 1. Test pyramid

### Unit tests

Test deterministic logic without network access:

- request validation and size limits;
- mapping project fields to a normalized research brief;
- prompt construction with untrusted input separated from policy;
- response parsing and schema validation;
- warning-code generation;
- reference-ID and section-ID checks;
- provider-error mapping;
- DOCX formatting helpers and filename sanitization;
- SQLite repository, version ordering, and migrations.

### Integration tests

Use a fake provider to exercise FastAPI routes and services:

- valid generation;
- invalid/oversized input;
- timeout, provider 429, 5xx, malformed output;
- export response MIME type and bytes;
- authentication and rate limiting in deployment-mode tests;
- confirm content is absent from captured logs;
- confirm failure never writes over a saved draft.

### End-to-end tests

Use the mobile app against a local/test API and verify create → input → generate → review → edit → save → reopen → export. Add failure scenarios: network disappears during generation, malformed import, and provider failure.

### Manual QA

Check keyboard behavior, text editing, long content, small-screen layout, file-picker behavior, loading/error messaging, accessibility labels, and exported DOCX readability.

## 2. Fake provider design

The fake provider should return fixtures selected by test case, not imitate probabilistic language generation. It should also be able to simulate a delay, timeout, rate-limit error, server error, and invalid JSON. This makes route and error behavior reproducible without using tokens or a real API key.

Real provider tests should be opt-in, use synthetic/non-confidential material, have a cost limit, and never be required for ordinary CI.

## 3. AI evaluation set

Check a small, versioned set of synthetic or public-domain cases into the repository. Do not put confidential or unpublished student research into permanent fixtures without permission.

Recommended cases:

1. **Complete input:** source draft, method, results, and supplied references exist.
2. **No results collected:** user explicitly states that experiments have not been conducted.
3. **Results omitted:** result information is unknown rather than explicitly absent.
4. **No references:** paper needs citation-needed placeholders rather than invented citations.
5. **Conflicting evidence:** project fields disagree with the draft on a numeric value.
6. **Prompt injection in source:** document text attempts to override the drafting policy.
7. **Large input:** at/near configured boundaries and above the limit.
8. **Malformed model response:** missing keys, wrong types, empty content, or duplicate section IDs.
9. **Specialist vocabulary:** technical terms should not be flattened into generic prose.
10. **Section regeneration:** one section changes while the other sections remain unchanged.

Version each fixture and the scoring rubric. Store a run manifest containing date, model/provider identifier, relevant model settings, schema version, prompt version, and evaluator notes. Never include secrets.

## 4. Human review rubric

Score each category from 0 to 4:

- **0:** unacceptable / absent;
- **1:** major problems;
- **2:** mixed, requires substantial edits;
- **3:** good, minor edits required;
- **4:** strong for a first draft, no major issue found in this category.

| Category | What the evaluator checks |
|---|---|
| Faithfulness | Technical claims and meaning match supplied evidence |
| Non-fabrication | No invented result values, methods, people, datasets, or references |
| Structure | Sections are appropriate, ordered, and non-duplicative |
| Clarity | Writing is coherent, precise, and grammatically sound |
| Academic restraint | Limitations and uncertainty are not erased or overstated |
| Reference handling | Supplied references are retained; missing sources are flagged honestly |
| Editability | Content is sectioned and practical to revise/export |

**Hard failure:** any invented experimental result, fabricated reference, or material change to a critical technical claim makes the case fail regardless of its average score.

The score is a project evaluation measure, not a validated scientific benchmark. Explain evaluator count and limitations in the report.

## 5. Regression policy

- Add a new test whenever a bug is fixed.
- Keep a fixed evaluation set and compare new prompt/model configurations against it.
- Review regressions before changing the default provider model or prompt.
- Do not judge a model change from one hand-picked sample.
- Preserve negative examples so the team can verify that known failures remain fixed.

## 6. Suggested automation and quality gates

Backend CI should run:

1. formatting/lint checks;
2. type checks where configured;
3. unit and integration tests;
4. schema validation tests;
5. dependency/secret checks;
6. OpenAPI/contract consistency checks where feasible.

Mobile CI should run formatting, static analysis, unit/widget tests, and a build for the intended development target. Cross-platform platform builds must be explicitly tested; passing Dart tests alone does not prove that a platform package builds.

## 7. Metrics worth recording

- successful generation rate;
- failure rate by stable error code;
- end-to-end generation latency (median and p95, once sample size is meaningful);
- average input/output size and provider token usage/cost where available;
- proportion of evaluation cases passing the hard fabrication gate;
- category scores and reviewer notes;
- DOCX export success rate.

Do not report a precise p95 or success percentage from a tiny sample without giving the sample count and caveat.

## 8. Backend P0 traceability

This table covers requirements whose implementation boundary includes the backend. Client-owned persistence, interface, and device workflows are listed as gaps below rather than implied by API tests.

| Requirement | Backend evidence |
|---|---|
| FR-002 — structured project facts | `test_generation_request_matches_contract_and_preserves_reference_text`, `test_provided_status_requires_nonblank_details` |
| FR-004 — explicit evidence statuses and references | `test_unknown_and_explicit_unavailable_states_remain_distinct`, `test_generation_does_not_persist_or_log_source_content`, `test_provider_cannot_add_unprovided_references` |
| FR-005 — validation and limits before generation | `test_invalid_request_is_rejected_before_provider_invocation`, `test_over_limit_source_draft_is_rejected_by_schema_and_model`, `test_streamed_body_limit_applies_without_content_length`, `test_provider_timeout_and_token_limits_are_bounded` |
| FR-006 — generation from supplied material | `test_fake_provider_generates_contract_valid_deterministic_paper`, mocked OpenAI adapter tests in `test_openai_provider.py` |
| FR-007 — schema-valid output | `test_paper_draft_matches_contract_and_serializes_deterministically`, `test_json_that_does_not_match_the_paper_contract_fails_closed` |
| FR-008 — review warnings | missing-results, missing-method, conflict, incomplete-reference, and numeric-claim tests in `test_research_integrity.py` and `test_generation_api.py` |
| FR-010 — single-section proposal | `test_success_returns_only_a_targeted_preview_and_integrity_warnings`, `test_accepting_preview_changes_only_target_and_preserves_paper_fields`, `test_mismatched_or_unsupported_provider_section_fails_closed` |
| FR-012 — DOCX export | `test_export_returns_reopenable_docx_in_paper_order_with_safe_headers`, `test_export_filename_strips_path_control_and_non_ascii_characters`, export failure and size-limit cases in `test_docx_export_api.py` |
| FR-013 — stable API errors | validation, provider failure, HTTP failure, export failure, and request-ID assertions across `test_http_foundation.py`, `test_generation_api.py`, `test_section_regeneration_api.py`, and `test_docx_export_api.py` |
| NFR-001 — provider secrets stay server-side | `test_example_secret_placeholder_is_not_treated_as_a_credential`, `test_missing_provider_credentials_or_model_prevents_network_client_creation`, and the no-content log tests; mobile-bundle scanning remains a release task |
| NFR-002 — content-free server logs | `test_generation_does_not_persist_or_log_source_content`, `test_unexpected_error_is_generic_and_logs_only_operational_metadata` |
| NFR-003 — no backend content persistence | `test_generation_does_not_persist_or_log_source_content`; export is in-memory and the service contains no storage writes |
| NFR-004 — boundary validation | domain/schema tests, malformed provider response tests, and invalid/oversized API request tests |
| NFR-005 — failures preserve saved versions | the backend has no saved-version store to overwrite; service and export failure tests prove safe errors, while local-version preservation remains a client/repository test gap |
| NFR-006 — safe errors | framework/provider/export failures use the fixed error catalog; UI next-action presentation is a client test gap |
| NFR-007 — no paid network in ordinary tests | `FakeProvider` tests and mocked SDK tests; no live provider test is required by CI |
| NFR-008 — critical paths have repeatable checks | API and document tests run in pytest; Flutter device/manual QA is not available in this environment |
| NFR-009 — explicit request, input, timeout, and token bounds | `test_streamed_body_limit_applies_without_content_length`, `test_over_limit_source_draft_is_rejected_by_schema_and_model`, `test_provider_timeout_and_token_limits_are_bounded` |
| NFR-010 — clean backend setup | the locked dependency set is checked with `uv lock --check` and `uv sync --locked --dev` |

Static OpenAPI validity and operation/schema parity are checked by `test_openapi_document_is_valid_and_matches_status_contracts` and `test_checked_in_openapi_operations_match_running_fastapi_routes`.

For full end-to-end requirement traceability covering both backend and Flutter mobile client across all P0 functional and non-functional requirements, see [`12-requirement-traceability-matrix.md`](12-requirement-traceability-matrix.md). For repeatable manual verification steps, see [`smoke-test-guide.md`](smoke-test-guide.md). Authentication, sliding-window rate limits, and client privacy controls are verified in `test_auth_and_rate_limits.py` and `privacy_notice_test.dart`.

## 9. Deterministic evaluation fixture set

`backend/tests/evaluation/v1/manifest.json` is evaluation set version 1. It includes complete input, missing results, missing method, conflicting numeric facts, an incomplete reference, non-experimental research, and an unusual section structure. `run_manifest` records the date, deterministic provider/model, model settings, paper schema version, prompt version, and limits of automated evaluation without storing secrets.

`test_synthetic_evaluation_cases_preserve_contract_and_evidence_invariants` runs each profile through the fake provider and checks schema validity, reference equality, section identity/order, expected warning codes, and that output numbers occur somewhere in the supplied input. This last check is a narrow regression guard, not proof that a value is scientifically correct or supported in context. No automated test establishes truth, reference validity, technical faithfulness, or writing quality; those require human review under section 4. No real-model score, coverage percentage, or scientific-quality score is reported here.
