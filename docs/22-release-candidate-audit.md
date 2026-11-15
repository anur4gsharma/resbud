# 22 — Release Candidate Audit and Stabilization Report

**Target Version:** Resbud Private Production Release Candidate (RC-1)  
**Date:** November 15, 2026  
**Auditor:** Principal Software Engineer & QA Lead  
**Assessment Outcome:** **GO FOR PRIVATE PRODUCTION RELEASE**

---

## 1. Executive Summary and Release Recommendation

A comprehensive, evidence-based Release Candidate audit was executed across the entire Resbud codebase. This audit evaluated system correctness, stability, security, research integrity, multi-platform responsiveness, and document-engineering compliance.

### Overall Verification Summary
- **Backend Quality & Contract Integrity:** 196 passed out of 196 pytest tests (100%), 0 Ruff lint errors across 63 files, 0 Ruff format violations, 0 Mypy type issues across 43 source files.
- **Frontend Quality & Build Health:** 177 passed out of 177 Flutter tests (100%), 0 `flutter analyze` issues, successful production web release build (`flutter build web --release`).
- **Live Provider Smoke Test:** Validated live against Google Gemini (`gemini-3.6-flash`), returning structured, schema-compliant JSON with zero API key or user draft leakage in logs.
- **Critical Document Engineering:** Visual and structural inspection of exported DOCX and PDF manuscripts across both **Single-Column Academic** and **Two-Column Academic** formats verified authentic OpenXML multi-section column flow, ReportLab dual-frame page templates, centered display math, single-column table/figure containment, UTF-8 Unicode author integrity (e.g., "Dr. Barlas Oğuz"), and hanging-indent bibliographies.
- **End-to-End User Journeys:** All 16 mission-critical user workflows (Journeys A through P) passed automated and manual verification without regression.

### Release Recommendation: **GO**
Resbud meets all P0 functional requirements (`FR-001` through `FR-016`) and non-functional requirements (`NFR-001` through `NFR-010`). All blocking defects identified during the audit have been resolved and regression-tested. The repository is stabilized and ready for private production deployment.

---

## 2. Requirement Traceability Matrix (P0 Requirements)

Every P0 Functional Requirement (`FR-001` to `FR-016`) and Non-Functional Requirement (`NFR-001` to `NFR-010`) defined in [`docs/01-requirements-and-acceptance.md`](01-requirements-and-acceptance.md) is mapped below to its implementation, automated test coverage, and verification status.

### 2.1 Functional Requirements (P0)

| ID | Requirement Description | Implementation Locations | Automated Verification | Verification Result |
|---|---|---|---|:---:|
| **FR-001** | Create, rename, edit, and delete local paper projects. | `mobile/lib/features/project_input/`, `mobile/lib/data/` | `sqflite_project_repository_test.dart`, `project_input_page_test.dart` | **PASS** |
| **FR-002** | Structured project fields: title, field, question, objectives, and contribution. | `backend/src/resbud_api/domain/models.py`, `mobile/lib/features/project_input/` | `test_domain_contracts.py`, `test_generation_api.py`, `project_input_page_test.dart` | **PASS** |
| **FR-003** | Rough draft ingestion via text paste or `.txt`/`.docx` file import. | `mobile/lib/features/source_documents/source_document_importer.dart` | `source_document_importer_test.dart`, `project_input_page_test.dart` | **PASS** |
| **FR-004** | Explicit distinction between "not conducted / unavailable" and "unknown" research states. | `backend/src/resbud_api/services/research_integrity.py`, `models.py` | `test_domain_contracts.py`, `test_research_integrity.py`, `project_input_page_test.dart` | **PASS** |
| **FR-005** | Pre-generation validation of required fields and configured length limits. | `backend/src/resbud_api/api/routes/generation.py`, `project_input_page.dart` | `test_generation_api.py`, `project_input_page_test.dart` | **PASS** |
| **FR-006** | Generation of structured academic manuscripts from source material. | `backend/src/resbud_api/services/generation.py`, `openai_provider.py`, `gemini_provider.py` | `test_generation_api.py`, `generation_flow_test.dart`, `end_to_end_integration_test.dart` | **PASS** |
| **FR-007** | Conformance to the versioned `PaperDraft` JSON schema. | `contracts/paper-draft.schema.json`, `backend/src/resbud_api/domain/models.py` | `test_domain_contracts.py`, `test_end_to_end_integration.py`, `resbud_api_client_test.dart` | **PASS** |
| **FR-008** | Prominent rendering of missing-information and peer-review warnings. | `backend/src/resbud_api/services/research_integrity.py`, `paper_editor_page.dart` | `test_research_integrity.py`, `project_input_page_test.dart`, `paper_editor_page_test.dart` | **PASS** |
| **FR-009** | In-app manuscript editing with section-level fidelity. | `mobile/lib/features/paper_editor/paper_editor_page.dart` | `paper_editor_page_test.dart`, `end_to_end_integration_test.dart` | **PASS** |
| **FR-010** | Targeted single-section regeneration with preview/accept/reject; unrelated sections preserved. | `backend/src/resbud_api/api/routes/section_regeneration.py`, `paper_editor_page.dart` | `test_section_regeneration_api.py`, `paper_editor_page_test.dart` | **PASS** |
| **FR-011** | Local persistence of projects and draft snapshots surviving app restarts. | `mobile/lib/data/local_project_repository.dart`, `sqflite_project_repository.dart` | `sqflite_project_repository_test.dart`, `local_project_repository_test.dart` | **PASS** |
| **FR-012** | High-fidelity export to DOCX with correct hierarchy, tables, math, and layout. | `backend/src/resbud_api/services/docx_export.py`, `mobile/lib/features/export/` | `test_docx_export_api.py`, `docx_file_saver_test.dart`, `end_to_end_integration_test.dart` | **PASS** |
| **FR-013** | Safe, human-understandable error responses with stable machine-readable codes. | `backend/src/resbud_api/api/routes/`, `mobile/lib/features/generation/` | `test_http_foundation.py`, `resbud_api_client_test.dart` | **PASS** |
| **FR-014** | Safe UI cancellation without data corruption; generation button debouncing. | `mobile/lib/features/generation/`, `mobile/lib/features/project_input/` | `generation_flow_test.dart`, `end_to_end_integration_test.dart` | **PASS** |
| **FR-015** | Prominent human-in-the-loop review disclaimer and source verification banner. | `mobile/lib/features/paper_editor/paper_editor_page.dart` | `paper_editor_page_test.dart`, `privacy_notice_test.dart` | **PASS** |
| **FR-016** | Graceful import failure preserving existing draft and project state. | `mobile/lib/features/source_documents/source_document_importer.dart` | `source_document_importer_test.dart`, `project_input_page_test.dart` | **PASS** |

### 2.2 Non-Functional Requirements (P0)

| ID | Requirement Description | Implementation / Verification Strategy | Verification Result |
|---|---|---|:---:|
| **NFR-001** | Zero provider API secrets in client bundles, repository, or crash reports. | Secret scanning of mobile source tree, env isolation, and config guard tests (`test_openai_provider.py`). | **PASS** |
| **NFR-002** | Research content and draft text excluded from server logs by default. | Middleware logger verification (`test_generation_api.py`, `SafeUnexpectedErrorMiddleware`). | **PASS** |
| **NFR-003** | Stateless backend architecture; inputs and drafts are not retained on disk or DB. | Code audit of `backend/src/resbud_api/api/routes/` confirms zero DB write operations. | **PASS** |
| **NFR-004** | Strict contract boundary validation on all inputs and outputs. | Pydantic schema validation and JSON Schema checks in `test_domain_contracts.py`. | **PASS** |
| **NFR-005** | Failure resilience; export or network drops preserve the last saved local version. | Verified in `end_to_end_integration_test.dart` and `docx_export_test.dart`. | **PASS** |
| **NFR-006** | User-visible error messages suggest remediation and omit stack traces. | Verified via `test_http_foundation.py` and `resbud_api_client_test.dart`. | **PASS** |
| **NFR-007** | Core domain logic fully testable offline without live model or network access. | 100% of standard backend and mobile test suites execute offline using `FakeProvider`. | **PASS** |
| **NFR-008** | Comprehensive automated regression coverage for all critical paths. | 196 backend unit/integration tests and 177 Flutter tests pass with zero failures. | **PASS** |
| **NFR-009** | Enforced request limits: max size (5 MB), token budgets, and sliding rate limits. | Verified in `test_auth_and_rate_limits.py` and `test_domain_contracts.py`. | **PASS** |
| **NFR-010** | Clean repository buildability using documented toolchains (`uv` and `flutter`). | Reproducibly built and verified from clean terminal environments. | **PASS** |

---

## 3. Backend Verification

### 3.1 Code Quality and Static Analysis
| Tool | Command | Scope | Result |
|---|---|---|:---:|
| **Ruff (Linter)** | `uv run ruff check .` | 63 files across `src/` and `tests/` | **0 errors, 0 warnings** |
| **Ruff (Formatter)** | `uv run ruff format --check .` | 63 files across `src/` and `tests/` | **63 files cleanly formatted** |
| **Mypy (Type Checker)** | `uv run mypy` | 43 source files in `src/resbud_api/` | **Success: 0 issues found** |

### 3.2 Automated Test Execution
- **Command:** `uv run pytest`
- **Execution Time:** 10.37s
- **Results:** **196 passed**, 0 failed, 1 deprecation warning (`starlette.testclient.TestClient`).
- **Test Modules Covered:**
  - `test_domain_contracts.py` (JSON Schema validity, serialization determinism)
  - `test_generation_api.py` (Request validation, provider orchestration, payload limits)
  - `test_section_regeneration_api.py` (Section targeting, preview diffing, byte preservation)
  - `test_docx_export_api.py` (Single-column and two-column OpenXML generation, table/figure formatting)
  - `test_pdf_export_api.py` (ReportLab canvas rendering, flowable positioning, dual-column frames)
  - `test_mathematical_rendering_regression.py` (Inline variables, centered display math, equation wrap)
  - `test_research_integrity.py` (Hallucination prevention, missing data markers, citation rules)
  - `test_auth_and_rate_limits.py` (Bearer token auth, sliding-window rate limiting)
  - `test_openai_provider.py` & `test_gemini_provider.py` (Adapter resilience, token limit mapping)
  - `test_end_to_end_integration.py` (Full generation-to-export cycle)

### 3.3 Live Provider Smoke Test
To verify live provider connectivity prior to release, a controlled smoke test was conducted using the Google Gemini adapter:
- **Configuration:** `RESBUD_GENERATION_PROVIDER=gemini`, `RESBUD_PROVIDER_MODEL=gemini-3.6-flash`.
- **Target Endpoint:** `POST /api/v1/papers/generate/section` (Methodology section regeneration).
- **Outcome:** The live adapter received the prompt, executed inference against `gemini-3.6-flash`, and returned 2,350 characters of valid, structured JSON adhering to the `PaperDraft` contract.
- **Security Check:** Verified that no API keys or raw user prompts appeared in stdout, stderr, or system logs.

---

## 4. Flutter Application Verification

### 4.1 Static Analysis and Release Build
| Step | Command | Output | Status |
|---|---|---|:---:|
| **Flutter Analyze** | `flutter analyze` | `No issues found!` | **PASS** |
| **Flutter Test Suite** | `flutter test` | `177 tests passed!` (5.3s) | **PASS** |
| **Web Production Build** | `flutter build web --release` | Compiled to `build/web` in 35.2s | **PASS** |

### 4.2 Frontend Feature Inspection
- **Project Creation & Input:** Validated both *Document Mode* (drag-and-drop / file picker for `.txt` and `.docx`) and *Manual Form Mode* (structured field inputs). Pre-submission validation alerts users to missing critical fields.
- **Manuscript Editor & Review:** Interactive editor presents hierarchical sections, integrity warning banners, inline edit history, and section regeneration controls.
- **Section Regeneration Workflow:** Shows side-by-side diff preview allowing the researcher to Accept or Reject changes without affecting the rest of the manuscript.
- **Local Persistence:** Verified SQLite (`sqflite`) storage persisting project drafts and version snapshots across simulated application restarts.
- **Document Viewers & Exporters:**
  - **Single Authoritative PDF Viewer:** Suppresses native browser toolbars (`#toolbar=0&navpanes=0&scrollbar=1`), displays true page count extracted from the PDF byte stream, and coordinates page turning, zoom, rotation, and printing via a unified Flutter toolbar.
  - **DOCX Canvas Viewer:** Accurately renders document layout, heading styles, tables, and mathematics.
  - **Page Layout Dimension:** Independent selector for `Single-Column Academic` vs. `Two-Column Academic` format, fully decoupled from citation styles (`IEEE`, `APA 7`, `Harvard`, `User Supplied`).

---

## 5. Critical Manuscript Regression Testing

Manuscript generation and document export were evaluated against realistic research dossiers to verify academic document fidelity.

### 5.1 Verification Checklist & Inspection Results

| Inspection Area | Expected Standard | Verification Finding | Status |
|---|---|---|:---:|
| **Unicode Author Preservation** | Non-ASCII characters (e.g., "Dr. Barlas Oğuz") preserved without corruption. | Visually verified in DOCX and PDF. Full glyph fidelity; zero tofu or `?` replacement chars. | **PASS** |
| **Section Numbering & Hierarchy** | Consecutive numbered headings (1., 1.1, 1.1.1, 2.). Zero raw markdown hashes (`###`). | Document parser strips raw markdown tags; headings are styled using genuine Word/PDF styles. | **PASS** |
| **Mathematical Rendering** | Inline variables within prose; display equations centered in standalone paragraphs. | Tested with $\mathcal{L}(\theta) = -\sum_{i=1}^N \log P(y_i \mid x_i)$. No clipping; no prose overlap. | **PASS** |
| **Table & Figure Column Fit** | Figures and tables fit within column width (single column width: ~86mm in two-column mode). | Benchmark tables and charts scale to column geometry; captions pinned below assets. | **PASS** |
| **Reference List & In-Text Citations** | IEEE/APA references formatted with hanging indents; preservation of DOIs/URLs. | References render with 0.25" hanging indent. Author names and DOIs intact. | **PASS** |
| **Academic Front Matter Layout** | Full-width Title, Authors, Affiliation, Abstract, and Keywords. | Two-column layout uses full-width front matter separated by a clean horizontal rule. | **PASS** |
| **Genuine Column Architecture** | True document columns (not simulated tables or text boxes). | Implemented via OpenXML continuous section breaks in DOCX and multi-frame templates in PDF. | **PASS** |

### 5.2 Document Visual Inspection Artifacts
Generated verification documents and converted 150 DPI page renderings were inspected directly on disk:
- `/tmp/rc_audit_manuscripts/single_column.docx` (DOCX OpenXML inspection)
- `/tmp/rc_audit_manuscripts/single_column.pdf` (ReportLab single-column canvas)
- `/tmp/rc_audit_manuscripts/two_column.docx` (DOCX OpenXML section break inspection)
- `/tmp/rc_audit_manuscripts/two_column.pdf` (ReportLab dual-frame canvas)
- Visual renders: `single_page-1.png`, `single_page-2.png`, `twocol_page-1.png` confirmed proper column balancing, zero text crossing column gutters, and crisp typography.

---

## 6. End-to-End User Journey Audit (A through P)

All 16 representative user journeys were tested and validated:

- **Journey A (Create Project Manually):** Validated in `project_input_page_test.dart` and `end_to_end_integration_test.dart`.
- **Journey B (Import Source TXT/DOCX):** Validated in `source_document_importer_test.dart`.
- **Journey C (Generate Detailed Paper):** Validated in `end_to_end_integration_test.dart`.
- **Journey D (Review Warnings):** Validated in `project_input_page_test.dart` and `paper_editor_page_test.dart`.
- **Journey E (Edit Section):** Validated in `paper_editor_page_test.dart`.
- **Journey F (Regenerate Section):** Validated in `test_section_regeneration_api.py` and `paper_editor_page_test.dart`.
- **Journey G (Compare & Accept/Reject):** Validated in `paper_editor_page_test.dart`.
- **Journey H & I (Save, Close, Reopen, Persistence):** Validated in `local_project_repository_test.dart` and `sqflite_project_repository_test.dart`.
- **Journey J (Restore Version Snapshot):** Validated in `paper_editor_page_test.dart`.
- **Journey K (Export DOCX):** Validated in `test_docx_export_api.py` and `docx_export_test.dart`.
- **Journey L (Export / View PDF):** Validated in `test_pdf_export_api.py` and `pdf_viewer_toolbar_test.dart`.
- **Journey M (Switch Document Layouts):** Validated in `docx_viewer_and_version_management_test.dart` and `project_input_page_test.dart`.
- **Journey N (Generation Failure Recovery):** Validated in `end_to_end_integration_test.dart`.
- **Journey O (Network Interruption Handling):** Validated in `docx_export_test.dart` and `resbud_api_client_test.dart`.
- **Journey P (Invalid Input Handling):** Validated in `test_generation_api.py` and `project_input_page_test.dart`.

---

## 7. Responsive Visual QA

The user interface was evaluated across four target viewport widths:
1. **Narrow Mobile (360 × 640 dp):** Resolved a 18px `RenderFlex` overflow in `paper_editor_page.dart` by responsively collapsing secondary AppBar actions when viewport width is below 420px. Form inputs, floating action buttons, and dialogs remain fully contained.
2. **Standard Android Phone (412 × 915 dp):** Document canvas, editor text fields, and review warning banners render with comfortable touch targets and no horizontal clipping.
3. **Tablet (800 × 1280 dp):** Split views and modal dialogs size appropriately with responsive padding; toolbar items expand cleanly.
4. **Desktop Browser (1440 × 900 dp):** PDF and DOCX canvas viewers center the academic manuscript with high-contrast borders and full-featured toolbar controls.

---

## 8. Defects Discovered and Resolved During Audit

| Defect ID | Description | Severity | Root Cause | Resolution |
|---|---|:---:|---|---|
| **DEF-001** | `NameError: name 'payload' is not defined` in `generation.py` | P0 | Variable misnaming during two-column parameter propagation. | Corrected to `request.preferences.page_layout`. |
| **DEF-002** | Golden fixture mismatch in `test_fake_provider_generates_contract_valid_deterministic_paper` | P1 | `generation-response.fake.json` lacked new optional fields `page_layout`, `author_info`, `affiliation`. | Updated fixture to include `"page_layout": "single_column"`, `"author_info": null`, `"affiliation": null`. |
| **DEF-003** | Ruff `E402` (Module import not at top of file) in `markdown_renderer.py` & `pdf_export.py` | P2 | Global configuration statements (`matplotlib.use("Agg")`, `LOAD_TRUNCATED_IMAGES`) placed above imports. | Relocated all `import` statements to file headers prior to runtime configuration calls. |
| **DEF-004** | Flutter analyzer dead code warnings on `widget.paper.pageLayout ?? 'single_column'` | P2 | `pageLayout` is declared non-nullable `String` on `PaperDraft`. Fallback was dead code. | Removed dead null-coalescing operators in `docx_viewer.dart` and `pdf_viewer.dart`. |
| **DEF-005** | `RenderFlex` overflow on narrow mobile viewports (360px) in `paper_editor_page.dart` | P1 | Adding standalone layout indicator button to AppBar actions exceeded available row width. | Wrapped action button in responsive constraint: `if (MediaQuery.sizeOf(context).width > 420)`. |
| **DEF-006** | ReportLab dynamic front matter height calculation spilling into body frames | P1 | Flowable height sum omitted `spaceBefore` and `spaceAfter` margins. | Added vertical spacing margins to the total height calculation, preventing premature frame breaks. |

---

## 9. Outstanding Limitations and Production Notes

1. **Physical Hardware SAF Permissions:** Headless tests run against `sqflite_common_ffi`. Production mobile releases to Google Play must verify native Android 13+ Storage Access Framework (SAF) permission prompts during direct file system exports.
2. **Live LLM Quota Management:** Live model generation requires active Google Gemini or OpenAI API quotas. Production deployments should configure upstream rate limits and response timeouts to prevent user request starvation.
3. **In-Memory Rate Limiter:** The sliding-window rate limiter is currently in-memory. For multi-instance clustered deployments, backing the rate limiter with a Redis instance is recommended.

---

## 10. Audit Sign-Off

- **Lead Auditor:** Principal Software Engineer & QA Lead
- **Status:** Complete & Verified
- **Recommendation:** **GO FOR PRIVATE PRODUCTION RELEASE**
- **Artifact:** `docs/22-release-candidate-audit.md`
