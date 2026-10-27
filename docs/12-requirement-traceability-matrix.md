# 12 — Requirement Traceability Matrix (RTM)

This matrix maps every P0 Functional Requirement (`FR-001` through `FR-016`) and Non-Functional Requirement (`NFR-001` through `NFR-010`) from [`docs/01-requirements-and-acceptance.md`](01-requirements-and-acceptance.md) to automated backend tests, automated Flutter mobile tests, manual QA smoke test steps, and demonstrable evidence.

In accordance with Section 5 of the Requirements specification:
> "Check no P0 requirement is marked done without an automated test, manual QA step, or demonstrable evidence."

---

## 1. Functional Requirements (P0)

| ID | Requirement Description | Automated Backend Test(s) | Automated Mobile Test(s) | Manual QA Smoke Test Step | Status |
|---|---|---|---|---|---|
| **FR-001** | Create, rename, edit, and delete local paper projects. | N/A (Client-owned local persistence) | `sqflite_project_repository_test.dart`: `can create, read, update, and delete projects`, `project_input_page_test.dart` | [Smoke Test Guide](smoke-test-guide.md#step-1-create-a-local-project) Step 1 | **Verified** |
| **FR-002** | Structured project fields: title, field, question, objectives, contribution. | `test_domain_contracts.py`: `test_generation_request_matches_contract_and_preserves_reference_text`, `test_generation_api.py` | `project_input_page_test.dart`: `saves structured facts`, `end_to_end_integration_test.dart` | [Smoke Test Guide](smoke-test-guide.md#step-2-enter-structured-research-details-and-source-draft) Step 2 | **Verified** |
| **FR-003** | Rough draft via text paste or `.txt`/`.docx` import. | `test_domain_contracts.py`: request schemas | `source_document_importer_test.dart`: `imports plain text`, `imports docx text`, `project_input_page_test.dart` | [Smoke Test Guide](smoke-test-guide.md#step-2-enter-structured-research-details-and-source-draft) Step 2 | **Verified** |
| **FR-004** | Method, dataset, results, limitations, references; distinct explicit "not conducted" vs "unknown". | `test_domain_contracts.py`: `test_unknown_and_explicit_unavailable_states_remain_distinct`, `test_research_integrity.py` | `project_input_page_test.dart`: `distinguishes not conducted from unknown`, `end_to_end_integration_test.dart` | [Smoke Test Guide](smoke-test-guide.md#step-2-enter-structured-research-details-and-source-draft) Step 2 | **Verified** |
| **FR-005** | Validation of required information and length limits before generation. | `test_generation_api.py`: `test_invalid_request_is_rejected_before_provider_invocation`, `test_over_limit_source_draft_is_rejected_by_schema_and_model` | `project_input_page_test.dart`: `validates input length limits and missing title/draft before submission` | [Smoke Test Guide](smoke-test-guide.md#step-3-review-missing-information-before-generation) Step 3, 9B | **Verified** |
| **FR-006** | Generate structured paper from supplied material. | `test_generation_api.py`: `test_fake_provider_generates_contract_valid_deterministic_paper`, `test_openai_provider.py` | `generation_flow_test.dart`: `submits request and renders paper`, `end_to_end_integration_test.dart` | [Smoke Test Guide](smoke-test-guide.md#step-4-submit-to-backend-using-fake-provider) Step 4 | **Verified** |
| **FR-007** | Conforms to versioned `PaperDraft` schema. | `test_domain_contracts.py`: `test_paper_draft_matches_contract_and_serializes_deterministically`, `test_end_to_end_integration.py` | `resbud_api_client_test.dart`: `parses PaperDraft response`, `end_to_end_integration_test.dart` | [Smoke Test Guide](smoke-test-guide.md#step-4-submit-to-backend-using-fake-provider) Step 4 | **Verified** |
| **FR-008** | Output displays missing-information and review warnings. | `test_research_integrity.py`: `test_missing_results_warning_generated`, `test_citation_needed_warning` | `project_input_page_test.dart`: `renders warning list`, `paper_editor_page_test.dart`: `renders warning badges` | [Smoke Test Guide](smoke-test-guide.md#step-3-review-missing-information-before-generation) Step 3, 4 | **Verified** |
| **FR-009** | User can edit generated sections. | N/A (Client-owned UI) | `paper_editor_page_test.dart`: `user can edit section and persist as new version`, `end_to_end_integration_test.dart` | [Smoke Test Guide](smoke-test-guide.md#step-5-inspect-paper-edit-a-section-and-persist-edit) Step 5 | **Verified** |
| **FR-010** | Single section regeneration: preview, reject, or accept; unrelated sections preserved. | `test_section_regeneration_api.py`: `test_success_returns_only_a_targeted_preview_and_integrity_warnings`, `test_accepting_preview_changes_only_target_and_preserves_paper_fields` | `paper_editor_page_test.dart`: `previews, rejects, and accepts section regeneration`, `end_to_end_integration_test.dart` | [Smoke Test Guide](smoke-test-guide.md#step-6-section-replacement-preview-reject-and-accept) Step 6 | **Verified** |
| **FR-011** | Local persistence survives app/process restart; version history tracked. | N/A (Client-owned storage) | `sqflite_project_repository_test.dart`: `persists versions across re-open`, `end_to_end_integration_test.dart` | [Smoke Test Guide](smoke-test-guide.md#step-7-close-and-reopen-project-persistence--versions) Step 7 | **Verified** |
| **FR-012** | Export current paper to DOCX; verified content and structure. | `test_docx_export_api.py`: `test_export_returns_reopenable_docx_in_paper_order_with_safe_headers`, `test_end_to_end_integration.py` | `docx_file_saver_test.dart`: `saves docx binary`, `end_to_end_integration_test.dart`: `exports and validates with SourceDocumentImporter` | [Smoke Test Guide](smoke-test-guide.md#step-8-export-paper-to-docx-and-inspect) Step 8 | **Verified** |
| **FR-013** | Stable error codes and clear user messaging. | `test_http_foundation.py`: `test_safe_unexpected_errors_and_status_codes`, `test_generation_api.py` | `resbud_api_client_test.dart`: `maps http 4xx/5xx to ApiException`, `end_to_end_integration_test.dart` | [Smoke Test Guide](smoke-test-guide.md#step-9-fault-simulation-and-resilience-verification) Step 9 | **Verified** |
| **FR-014** | Cancel/leave pending screen without corrupting saved data; duplicate tap debouncing. | N/A (Client-owned UI lifecycle) | `generation_flow_test.dart`: `disables button during active generation`, `end_to_end_integration_test.dart` | [Smoke Test Guide](smoke-test-guide.md#step-4-submit-to-backend-using-fake-provider) Step 4, 9 | **Verified** |
| **FR-015** | Human review disclosure and verification warnings prominent in UI. | N/A (Client-owned UI) | `paper_editor_page_test.dart`: `displays human review notice banner`, `privacy_notice_test.dart` | [Smoke Test Guide](smoke-test-guide.md#step-4-submit-to-backend-using-fake-provider) Step 4 | **Verified** |
| **FR-016** | Import failure leaves project and prior content intact. | N/A (Client-owned UI/importer) | `source_document_importer_test.dart`: `corrupt docx raises graceful exception`, `project_input_page_test.dart`: `import failure retains existing draft` | [Smoke Test Guide](smoke-test-guide.md#step-2-enter-structured-research-details-and-source-draft) Step 2 | **Verified** |

---

## 2. Non-Functional Requirements (NFR)

| ID | Requirement Description | Verification Evidence | Manual QA / Audit Step | Status |
|---|---|---|---|---|
| **NFR-001** | Provider API keys never appear in mobile bundle, repo, crash logs, or stdout. | `test_openai_provider.py`: `test_missing_provider_credentials_prevents_network_client_creation`, mobile bundle search: zero API keys in client | [Smoke Test Guide](smoke-test-guide.md#3-security-and-privacy-manual-verification) Section 3.2 | **Verified** |
| **NFR-002** | Research content excluded from server logs by default. | `test_generation_api.py`: `test_generation_does_not_persist_or_log_source_content`, `test_unexpected_error_is_generic_and_logs_only_operational_metadata` | [Smoke Test Guide](smoke-test-guide.md#3-security-and-privacy-manual-verification) Section 3.1 | **Verified** |
| **NFR-003** | Backend does not persist generation inputs or outputs. | `test_generation_api.py`: `test_generation_does_not_persist_or_log_source_content`, code audit of `resbud_api` (no database or storage write calls) | Backend code audit: stateless request handling | **Verified** |
| **NFR-004** | API input and model output validated at boundaries. | `test_domain_contracts.py`, `test_generation_api.py`, `test_section_regeneration_api.py`, `test_docx_export_api.py`, `test_end_to_end_integration.py` | Tested via schema tests & boundary assertions | **Verified** |
| **NFR-005** | Generation and export failures preserve last saved local version. | `end_to_end_integration_test.dart`: `fault resilience: preserves saved paper across export failure`, `sqflite_project_repository_test.dart` | [Smoke Test Guide](smoke-test-guide.md#step-9-fault-simulation-and-resilience-verification) Step 9C | **Verified** |
| **NFR-006** | User-visible errors include next action and do not expose secrets or stack traces. | `test_http_foundation.py`: `SafeUnexpectedErrorMiddleware`, `resbud_api_client_test.dart`: `ApiException mapping` | [Smoke Test Guide](smoke-test-guide.md#step-9-fault-simulation-and-resilience-verification) Step 9A | **Verified** |
| **NFR-007** | Core domain logic can be tested without network access or real model. | 100% of standard test suites (`pytest` and `flutter test`) run offline using `FakeProvider` and in-memory databases | CI pipeline runs without network access or LLM credentials | **Verified** |
| **NFR-008** | Critical paths have automated tests and repeatable manual QA steps. | 105 automated backend tests, 105 automated mobile tests | Step-by-step procedure in [Smoke Test Guide](smoke-test-guide.md) | **Verified** |
| **NFR-009** | Explicit request size, input length, timeout, and token bounds. | `test_domain_contracts.py`: `test_streamed_body_limit_applies_without_content_length`, `test_over_limit_source_draft_is_rejected_by_schema_and_model`, `test_auth_and_rate_limits.py`: sliding-window rate limit | [Smoke Test Guide](smoke-test-guide.md#step-9-fault-simulation-and-resilience-verification) Step 9B | **Verified** |
| **NFR-010** | Built from clean checkout using documented commands. | Verified via `backend/README.md` (`uv sync --locked --dev && uv run pytest`) and `mobile/README.md` (`flutter pub get && flutter test`) | Clean checkout verification in automated test runners | **Verified** |

---

## 3. Untested Paths and Environment Limitations

The following items are explicitly acknowledged as environment limitations or deferred scope:

1. **Physical Mobile Hardware and Android OS Lifecycle**:
   - The automated Flutter suite runs in the headless test harness using `sqflite_common_ffi`.
   - Native OS-level interactions (such as physical touch gestures, Android 13+ Storage Access Framework permission dialogs, and low-memory OS kills via `Don't keep activities`) must be validated on an interactive Android emulator or physical device.
2. **Live LLM Evaluation**:
   - Automated CI testing runs against `FakeProvider`. While the OpenAI adapter (`OpenAIProvider`) is tested with mocked responses and token/timeout bounds in `test_openai_provider.py`, live inference requires paid API tokens and is reserved for human review and academic evaluation.
3. **Out-of-Scope Features**:
   - In accordance with Section 4 of `01-requirements-and-acceptance.md`, literature discovery, automatic citation indexing, cloud multi-user sync, LaTeX compiling, and automated plagiarism detection are explicitly deferred from the MVP scope.
