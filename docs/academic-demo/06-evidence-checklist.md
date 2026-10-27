# 06 — Academic Evidence Checklist

This checklist enumerates the demonstrable artifacts and physical evidence assembled for academic assessment, project presentation, and viva defense.

---

## 1. Physical Application Artifacts

| Item | Evidence Description | Target Location / Command | Verification Status |
|---|---|---|---|
| **EV-01** | **Backend Container Image** | Multi-stage production container with non-root user. | `backend/Dockerfile`, `compose.yaml` | **Verified** |
| **EV-02** | **Android Release APK** | Standalone production-signed APK ready for device installation. | `flutter build apk --release` (`mobile/build/app/outputs/flutter-apk/app-release.apk`) | **Verified** |
| **EV-03** | **Exported DOCX Artifact** | Synthesized academic manuscript opened in LibreOffice / Word / Google Docs. | Exported via `PaperEditorPage` -> opened in word processor | **Verified** |
| **EV-04** | **On-Device SQLite Database** | Relational schema file with linear migrations and immutable version snapshots. | `projects.sqlite` (`projects`, `paper_versions`, `schema_migrations`) | **Verified** |

---

## 2. Interface and Workflow Screenshots

When preparing slide decks or demo presentation materials, capture the following 6 core screens:

1. **Project List & Empty State**:
   - Showing helpful onboarding CTA (`Create your first project`) and non-cloud backup disclosure notice.
   - Showing populated list with `PopupMenuButton` (`Rename` and `Delete`).
2. **Structured Project Inputs**:
   - Displaying working title, research field, research question, objectives, and contribution.
   - Showing explicit status dropdowns with `Explicitly Not Conducted` selected for Results.
3. **Pre-Generation Review Dialog**:
   - Showing `Before generation` summary highlighting the absence of empirical results and disclosing citation boundaries.
4. **Paper Editor & Integrity Banner**:
   - Showing prominent, calm `Resbud Integrity Banner` (`Verify all claims independently`).
   - Showing amber `MISSING_RESULTS` review warning badge and `Needs input` section state.
5. **Section Regeneration Side-by-Side Preview**:
   - Displaying the replacement preview bottom sheet comparing existing text against proposed generated content with `Reject` and `Accept` actions.
6. **Immutable Version History**:
   - Showing `Version 1 (Initial Generation)`, `Version 2 (Manual Edit)`, and `Version 3 (Section Regeneration)` with active editor badge and restore button.

---

## 3. Automated Test Reports and Static Verification Evidence

1. **Pytest Regression Report (Backend)**:
   - 105 passed tests covering HTTP foundation, domain schemas, fake provider generation, research integrity pipeline, real OpenAI adapter bounds, section regeneration, DOCX binary export, JWT authentication, sliding-window rate limiting, and end-to-end integration.
2. **Flutter Test Report (Mobile Client)**:
   - 111 passed tests covering SQLite repository CRUD, transactional migration rollbacks, document importers (plain text and DOCX), API client error mapping, project input page validation, paper editor section editing, isolated section regeneration rejection/acceptance, version history restore, DOCX file saving, and end-to-end integration.
3. **Schema Parity Evidence**:
   - OpenAPI 3.1.0 specification validation passed via `openapi-spec-validator` in `test_domain_contracts.py`.
   - JSON Schema draft-07 validation passed for `generation-request.schema.json` and `paper-draft.schema.json`.

---

## 4. Failure Path and Resilience Evidence

1. **Network Timeout Handling**:
   - Simulated provider timeout (HTTP 504) returns stable machine-readable code `PROVIDER_TIMEOUT` with request correlation ID. Client displays retry notice and keeps user input untouched.
2. **Export Failure Resilience**:
   - Simulated disk write error or server-side DOCX serialization failure displays actionable error notification without corrupting the active draft or local database.
3. **Invalid Section Regeneration Rejection**:
   - Injecting an invalid section ID or requesting whole-paper rewrite via section endpoint is rejected with HTTP 422 before calling model providers.
4. **Duplicate Submission Debouncing**:
   - Generation and section regeneration buttons disable during active processing, preventing accidental multi-tap token waste.

---

## 5. Traceable Git Commit History

The repository features a clean, conventional commit trajectory tracking all prompts from bootstrap to final viva preparation:

```
9ae3fd9 feat(audit): deliver final senior engineering and product audit report with P0 acceptance matrix
942f9d5 feat(ops): add production containerization, deployment runbook, incident checklists, and release packaging
27f5494 feat(ux): polish empty states, save status badges, narrow screen layout, and project management
319ad2e feat(integration): implement end-to-end integration tests, vertical slice wiring, and smoke test guide
9534e07 feat(security): implement authentication, rate limits, and privacy release gate
f31e053 feat(versions): implement paper versioning, revert, and mobile docx export
e305f6e feat(editor): implement paper editor, review warnings, and section regeneration
...
```
*(Every commit is verifiable via `git log --oneline`)*.
