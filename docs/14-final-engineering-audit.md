# 14 — Final Engineering and Product Audit Report

**Evaluation Date**: 2026-10-27  
**Scope**: Full Resbud MVP repository (Backend, Mobile, Contracts, Security, Documentation, CI)  
**Auditor**: Antigravity Independent Engineering Audit  
**Status**: **ACCEPTED FOR PRIVATE BETA** (0 Blocker, 0 High, 1 Medium Resolved, 2 Low Resolved, 2 Operational Notes)

---

## 1. Executive Summary

This independent engineering audit evaluates the Resbud MVP codebase against the functional and non-functional requirements specified in [`docs/01-requirements-and-acceptance.md`](01-requirements-and-acceptance.md) and the architectural invariants established across ADRs 0001–0004.

All 16 Functional Requirements (`FR-001` through `FR-016`) and all 10 Non-Functional Requirements (`NFR-001` through `NFR-010`) are backed by automated tests, deterministic test fixtures, and repeatable manual smoke tests. The backend achieves 100% offline verification across 105 automated pytest unit and integration tests. The mobile client achieves 100% offline verification across 111 Flutter widget and integration tests. No mock models or network calls are required in CI.

---

## 2. Prioritized Findings Log

| Finding ID | Severity | Category | Description & Impact | Resolution / Status |
|---|---|---|---|---|
| **AUDIT-001** | **Medium** | Mobile UX | **Narrow Viewport Button Squeeze**: On viewports < 400dp, three horizontal action buttons in the bottom bar risked text truncation or RenderFlex overflow. | **Resolved**: Wrapped in `LayoutBuilder` in `ProjectInputPage`. Narrow screens stack into a 2-row layout without label clipping. Verified by `test/ux_polish_test.dart`. |
| **AUDIT-002** | **Low** | Mobile UX | **Project List Home Screen CRUD Gaps**: Users could only delete projects from inside the project detail page, and had no direct rename capability on the list. | **Resolved**: Added `PopupMenuButton` to each `ListTile` with "Rename" and "Delete" (with destructive confirmation dialog). Verified by `test/ux_polish_test.dart`. |
| **AUDIT-003** | **Low** | State Sync | **Missing In-Flight Saving Indicator**: `ProjectInputPage` lacked visual distinction between saved, unsaved, and saving states. | **Resolved**: Added reactive `project-save-status-badge` in `ProjectInputPage` AppBar tracking "Saved", "Unsaved", and "Saving…". Verified by `test/ux_polish_test.dart`. |
| **AUDIT-004** | **Info** | Operations | **Multi-Instance Distributed Rate Limiting**: In-memory rate limiting tracks requests per-process. Scaling to multiple container replicas will partition quota tracking per pod. | **Documented**: Documented in `docs/operations-and-incident-guide.md`. For private beta single-container deployment, in-memory sliding-window is zero-dependency. Centralized Redis/WAF limits documented for horizontal scaling. |
| **AUDIT-005** | **Info** | Environment | **iOS Native Binary Build Host Constraint**: Linux/Windows host cannot compile native iOS IPA binaries without a macOS host and Xcode. | **Documented**: Documented in `docs/operations-and-incident-guide.md` Section 3.2. Mobile verification runs on Linux Flutter test harness. macOS CI runner needed for App Store submission. |

---

## 3. Security, Privacy, and Contract Integrity Audit

### 3.1 Hardened Containerization
- `backend/Dockerfile` implements a multi-stage build using `ghcr.io/astral-sh/uv:python3.12-bookworm-slim` for compilation and `python:3.12-slim-bookworm` for runtime.
- Executes as a non-root system user (`appuser`, UID `10001`, GID `10001`).
- Eliminates development tooling, compilers, and secret files from runtime layers (`.dockerignore`).
- Health check is bounded to 5s timeout and 30s interval querying `/health/live`.

### 3.2 Fail-Closed Production Gate
- `Settings.reject_fake_provider_in_production` raises a validation error on startup if `RESBUD_ENV=production` and `RESBUD_GENERATION_PROVIDER=fake`.
- `Settings.readiness_issues()` verifies that mandatory secrets (`RESBUD_PROVIDER_API_KEY`, `RESBUD_PROVIDER_MODEL`, `RESBUD_AUTH_ISSUER`, `RESBUD_AUTH_AUDIENCE`, `RESBUD_AUTH_SIGNING_KEY`) are present, failing readiness with HTTP 503 without revealing secret values.

### 3.3 Zero-Data-Retention & Content-Free Logging
- The FastAPI service retains zero research inputs, user notes, prompts, or generated papers in persistent server storage. All generation requests and DOCX exports are processed strictly in-memory.
- Standard logger filters and middleware sanitize logs: request bodies, authorization headers, prompt tokens, and provider credentials are excluded.

### 3.4 Contract Parity
- Request and response schemas match OpenAPI 3.1.0 specification in `contracts/openapi.yaml`.
- Pydantic models in `backend/src/resbud_api/domain/models.py` and Dart models in `mobile/lib/features/generation/generation_models.dart` maintain field-level parity and enforce schema version 1.

---

## 4. Final P0 Acceptance Matrix

| Requirement ID | Description | Implementation Path | Automated Test / Evidence | Audit Result | Environment Limitations |
|---|---|---|---|---|---|
| **FR-001** | Project CRUD & management | `mobile/lib/main.dart`, `mobile/lib/data/` | `sqflite_project_repository_test.dart`, `ux_polish_test.dart` | **Verified** | Verified with SQLite FFI on desktop runner. |
| **FR-002** | Structured project facts | `mobile/lib/features/project_input/`, `backend/src/resbud_api/domain/` | `test_domain_contracts.py`, `project_input_page_test.dart` | **Verified** | None. |
| **FR-003** | Rough draft paste / TXT & DOCX import | `mobile/lib/import/source_document_importer.dart` | `source_document_importer_test.dart` | **Verified** | Custom ZIP/XML parsing tested offline with synthetic files. |
| **FR-004** | Explicit status distinction (Provided vs Not Conducted vs Unknown) | `mobile/lib/features/project_input/`, `backend/src/resbud_api/domain/` | `test_domain_contracts.py`, `test_research_integrity.py` | **Verified** | None. |
| **FR-005** | Input length limits and validation | `backend/src/resbud_api/domain/models.py`, `ProjectInputPage` | `test_generation_api.py`, `project_input_page_test.dart` | **Verified** | 50,000 char source limit and field bounds tested. |
| **FR-006** | Structured paper generation | `backend/src/resbud_api/services/generation.py` | `test_generation_api.py`, `generation_flow_test.dart` | **Verified** | Tested offline with `FakeProvider`. |
| **FR-007** | Conforms to PaperDraft schema v1 | `contracts/paper-draft.schema.json`, domain models | `test_domain_contracts.py`, `end_to_end_integration_test.dart` | **Verified** | Schema validated against JSON Schema draft-07. |
| **FR-008** | Pre-generation & post-generation review warnings | `backend/src/resbud_api/services/integrity.py` | `test_research_integrity.py`, `paper_editor_page_test.dart` | **Verified** | Flags missing results, conflicting numbers, citation needs. |
| **FR-009** | Interactive section editing & version bump | `mobile/lib/features/paper_editor/paper_editor_page.dart` | `paper_editor_page_test.dart`, `end_to_end_integration_test.dart` | **Verified** | Manual edits saved as new immutable version snapshots. |
| **FR-010** | Single-section regeneration with preview/reject/accept | `backend/src/resbud_api/services/generation.py`, `PaperEditorPage` | `test_section_regeneration_api.py`, `paper_editor_page_test.dart` | **Verified** | Unrelated sections proven byte-for-byte unmodified. |
| **FR-011** | Local persistence survives restart | `mobile/lib/data/local_project_repository.dart` | `sqflite_project_repository_test.dart`, `end_to_end_integration_test.dart` | **Verified** | Database survive simulated app reloads. |
| **FR-012** | Validated DOCX export | `backend/src/resbud_api/services/docx_export.py`, `DocxFileSaver` | `test_docx_export_api.py`, `end_to_end_integration_test.dart` | **Verified** | Binary output parsed and verified with python-docx & XML reader. |
| **FR-013** | Stable machine-readable error codes | `backend/src/resbud_api/core/errors.py`, `ApiException` | `test_http_foundation.py`, `test_generation_api.py` | **Verified** | Documented error shapes across all 4xx/5xx responses. |
| **FR-014** | Cancellation & duplicate tap debouncing | `ProjectInputPage`, `PaperEditorPage` | `generation_flow_test.dart`, `end_to_end_integration_test.dart` | **Verified** | Buttons disabled and loading indicators displayed during requests. |
| **FR-015** | Human review disclosure & verification notices | `privacy_notice_test.dart`, `PaperEditorPage` | `test_research_integrity.py`, `privacy_notice_test.dart` | **Verified** | Visible notice banners in editor and pre-generation screens. |
| **FR-016** | Transactional import failure resilience | `SourceDocumentImporter`, `ProjectInputPage` | `source_document_importer_test.dart`, `project_input_page_test.dart` | **Verified** | Corrupt files leave prior draft and project intact. |
| **NFR-001** | Zero secrets in client bundle, repo, or ordinary logs | `Settings`, `.gitignore`, `mobile/` | `test_security_and_auth.py`, secret scans | **Verified** | Client code contains 0 API keys; logs mask sensitive fields. |
| **NFR-002** | Content excluded from server logs | `RequestBoundaryMiddleware`, `FastAPI` handlers | `test_generation_api.py`, `test_security_and_auth.py` | **Verified** | Confirmed by log assertion tests. |
| **NFR-003** | Server does not persist generation inputs/outputs | `resbud_api` services | Code audit and integration tests | **Verified** | Stateless processing without database writes. |
| **NFR-004** | Boundary validation at all layers | `RequestBoundaryMiddleware`, `Pydantic`, `Dart` models | `test_domain_contracts.py`, `test_http_foundation.py` | **Verified** | 413, 422, and 400 validations verified. |
| **NFR-005** | Fault resilience preserves last saved version | Mobile repositories and error handlers | `end_to_end_integration_test.dart` | **Verified** | Timeout, export failure, and network error resilience tested. |
| **NFR-006** | User-visible errors include next action without exposing internals | `SafeUnexpectedErrorMiddleware`, `ApiException` | `test_http_foundation.py`, `test_end_to_end_integration.py` | **Verified** | Generic 500 error sanitization and actionable client messages. |
| **NFR-007** | Core domain logic testable without network or live LLM | Fake providers and in-memory test doubles | Complete test suites run offline | **Verified** | 100% offline verification in normal CI. |
| **NFR-008** | Automated tests and repeatable manual QA steps | Pytest, Flutter test, smoke test guide | `docs/smoke-test-guide.md`, 216 automated tests | **Verified** | Full manual checklist provided. |
| **NFR-009** | Explicit request size, timeout, and token bounds | `Settings`, `RequestBoundaryMiddleware` | `test_domain_contracts.py`, `test_security_and_auth.py` | **Verified** | 4MB body, 12,000 output tokens, 90s timeout tested. |
| **NFR-010** | Clean checkout reproducibility | `README.md`, `pyproject.toml`, `pubspec.yaml` | `uv sync --locked --dev`, `flutter pub get` | **Verified** | Zero manual patch steps required. |

---

## 5. Exact Commands Run and Verified Results

### Backend Verification
```bash
cd backend
.venv/bin/ruff format --check src tests
# Result: 36 files already formatted (0 changes)

.venv/bin/ruff check src tests
# Result: All checks passed!

.venv/bin/mypy src
# Result: Success: no issues found in 23 source files

../backend/.venv/bin/python -m pytest tests/ -v
# Result: 105 passed, 1 warning (Starlette testclient deprecation) in 1.36s
```

### Mobile Verification
```bash
cd mobile
/tmp/resbud-flutter-sdk/bin/flutter analyze
# Result: Analyzing mobile... No issues found! (ran in 0.5s)

/tmp/resbud-flutter-sdk/bin/flutter test
# Result: 00:10 +111: All tests passed!
```

---

## 6. Conclusion and Release Gate Recommendation

The Resbud codebase satisfies all P0 functional and non-functional requirements. The vertical slice (project creation, structured inputs, import, pre-generation review, fake provider generation, section editing, isolated section regeneration, persistence, version history restore, and DOCX export) is verified with zero contract drift.

**Recommendation**: **APPROVED FOR CONTROLLED PRIVATE BETA**.
All core engineering gates are satisfied. Deployments should follow the container runbook and incident response guidelines in [`docs/operations-and-incident-guide.md`](operations-and-incident-guide.md).
