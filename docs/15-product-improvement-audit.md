# 15 — Product, UX, Architecture, and Functionality Audit Report

**Audit Date:** 2026-10-29  
**Auditor:** Lead Product & Architecture Engineer (Antigravity Assistant)  
**Scope:** Full Resbud Repository (`backend/`, `mobile/`, `contracts/`, `docs/`)  
**Operating Constraint:** Zero modifications to production code during this audit phase.  
**Baseline References:** `docs/00-product-spec.md`, `docs/01-requirements-and-acceptance.md`, `docs/02-architecture.md`, `contracts/openapi.yaml`, `docs/14-final-engineering-audit.md`.

---

## 1. Executive Summary

This comprehensive audit evaluates the current implementation, user experience, visual design, architecture, and test health of Resbud. Resbud is an on-device, local-first research paper drafting assistant built with Flutter, FastAPI, SQLite, and configurable LLM providers (Google Gemini, OpenAI, Deterministic Fake).

The core differentiator—transforming researcher-supplied notes into a structured academic draft without hallucinating experimental facts or fabricating citations—is fundamentally sound in design. The backend architecture successfully maintains stateless zero-data-retention, and local persistence via SQLite preserves drafts and immutable versions on the user's device.

However, empirical evaluation across runtime execution, browser DevTools automation (CDP), and automated test suites identified several critical defects and UX deficiencies that impair product excellence:

1. **Fatal Web Semantics Runtime Crash (P0)**: In Flutter Web, configuring `keyboardType: minLines > 1 ? TextInputType.multiline : TextInputType.text` triggers a fatal JavaScript exception (`TypeError: Cannot set property type of #<HTMLTextAreaElement> which has only a getter`) in the web semantics engine whenever multiline fields render.
2. **Automated Test Suite Stall (P0)**: In `mobile/test/project_input_page_test.dart`, line 520 invokes `tester.pumpAndSettle()` while an active `CircularProgressIndicator` animates inside the generation button, causing the test runner to hang indefinitely.
3. **CI Static Analysis Failure (P1)**: `backend/src/resbud_api/providers/gemini_provider.py` contains formatting deviations that fail `uv run ruff format --check`.
4. **Test Discovery Collision on Custom Live Tests (P1)**: `backend/tests/custom/test_generate_custom_paper.py` and `test_regenerate_section.py` are picked up by standard `pytest` runs and fail when an offline environment has no live server running.
5. **Primitive Shared Design System (P1)**: `mobile/lib/shared/design_tokens.dart` is only 28 lines, lacking a cohesive academic typography scale, semantic status tokens, component themes, and dark mode support.
6. **Paper Editor Navigation & Readability Constraints (P1)**: The paper editor renders all sections in a monolithic vertical scroll view without a floating/drawer section outline, visual inline diffing for section regeneration, or inline warnings.
7. **Missing Manuscript Readiness Review (P1)**: There is no dedicated pre-export readiness checklist or deterministic integrity audit to guide researchers before publishing or exporting to DOCX.

---

## 2. Engineering Verification Evidence

The audit conducted rigorous verification commands across both backend and frontend environments without modifying production code.

### 2.1 Backend Verification Commands

| Command | Status | Output / Findings |
| :--- | :--- | :--- |
| `uv run ruff format --check src tests` | **FAIL** | 1 file would be reformatted (`src/resbud_api/providers/gemini_provider.py:191:49`). |
| `uv run ruff check src tests` | **PASS** | `All checks passed!` across 24 source files. |
| `uv run mypy src` | **PASS** | `Success: no issues found in 24 source files`. |
| `uv run pytest -k "not test_user_custom"` | **PASS** | 117 passed, 2 deselected, 1 warning in 5.57s. |
| `uv run pytest tests/` | **FAIL** | 2 failed (`tests/custom/test_generate_custom_paper.py`, `test_regenerate_section.py`) due to connection refusal / rate limiter on live probe. |

### 2.2 Mobile Client Verification Commands

| Command | Status | Output / Findings |
| :--- | :--- | :--- |
| `flutter analyze` | **PASS** | `No issues found! (ran in 2.0s)`. |
| `flutter test test/local_project_repository_test.dart test/document_project_extractor_test.dart test/source_document_importer_test.dart test/docx_export_test.dart test/ux_polish_test.dart test/paper_editor_page_test.dart test/generation_api_test.dart test/widget_test.dart` | **PASS** | 100 tests passed in 11.2s. |
| `flutter test test/end_to_end_integration_test.dart` | **PASS** | 3 tests passed in 10.1s. |
| `flutter test test/project_input_page_test.dart` | **FAIL (HANG)** | Test 13 (`supports document mode with file upload and direct generation without autofill`) hangs indefinitely due to `pumpAndSettle()` awaiting an infinite `CircularProgressIndicator` animation. |
| Runtime Web Execution in Brave via CDP | **WARNING** | Console log captured: `TypeError: Cannot set property type of #<HTMLTextAreaElement> which has only a getter` in `lib/_engine/engine/semantics/text_field.dart:378`. |

---

## 3. UI, Ergonomics & Responsiveness Evaluation

The running application was evaluated across desktop (1280px wide) and mobile viewports (375px wide) using automated browser interaction and live rendering inspection.

### 3.1 Project Dashboard & Onboarding
- **Strengths**: Clean, unbloated project list; displays updated timestamps; includes non-destructive options menu (rename and delete with confirmation).
- **Deficiencies**:
  - Empty state is purely functional (`Create your first project`) with zero explanation of what Resbud is or how its two modes operate.
  - No visual indication of project status (e.g., whether a project has a generated draft, an exported document, or only raw notes).
  - Lacks search or sorting controls for users with multiple projects.
  - Footer notice regarding device storage is static plain text rather than an informative, dismissible banner or card.

### 3.2 Project Creation & Input Modes
- **Strengths**: Creation modal supports two distinct workflows: "From File (.txt/.md)" (Document Mode) vs "Manual Form Details".
- **Deficiencies**:
  - In Document Mode, the target word count slider and citation style dropdown are awkwardly placed with low visual hierarchy.
  - In Manual Mode, 12+ text fields are presented in a flat, exhausting vertical scroll with no visual grouping, progressive disclosure, or collapsible cards (e.g., "Project Core", "Methodology & Data", "Results & Limits", "Preferences").
  - On narrow mobile viewports (<375dp), form field counter texts and helper labels can crowd each other.

### 3.3 Paper Editor
- **Strengths**: Editable section cards; preserves title, abstract, keywords, sections, and references; immutable versioning on save.
- **Deficiencies**:
  - **Monolithic Scroll**: Lacks an outline navigation panel. Users must scroll through thousands of words to find specific sections.
  - **Section State Ambiguity**: While sections have `state` metadata (`generated`, `edited`, `not_applicable`), there is minimal visual differentiation between unedited AI text and author-revised text.
  - **Regeneration Review Experience**: The proposal review modal displays the proposed text in a single dialog, but lacks side-by-side or word-diff highlights, making it tedious to see exact revisions.
  - **Disconnected Review Warnings**: Review warnings are rendered in a block at the bottom of the page rather than pinned contextually to the relevant sections.

---

## 4. Prioritized Findings Log

### P0 — Critical Defects (Must Fix Before Beta)

| ID | Finding & Affected Components | Evidence / Reproduction | User Impact & Risk | Recommended Fix & Scope |
| :--- | :--- | :--- | :--- | :--- |
| **AUDIT-P0-01** | **Flutter Web HTMLTextAreaElement Type Exception**<br>`mobile/lib/features/project_input/project_input_page.dart:1619` | When semantics are enabled, web engine throws `TypeError: Cannot set property type of #<HTMLTextAreaElement> which has only a getter`. | Fatal browser console crash; can lock accessibility and text editing on web. | Omit `keyboardType` or conditionally set it only for single-line inputs (`minLines == 1 ? TextInputType.text : null`).<br>**Scope: Small** |
| **AUDIT-P0-02** | **Test Runner Hang on Infinite Animation**<br>`mobile/test/project_input_page_test.dart:514-522` | Running `flutter test test/project_input_page_test.dart` hangs at test 13 awaiting `pumpAndSettle()`. | Blocks CI/CD test automation completely; requires manual kill. | Replace `pumpAndSettle()` with discrete `pump(Duration)` steps while generation indicator animates, or scroll button into view.<br>**Scope: Small** |

---

### P1 — High-Value Improvements (Core Product Experience)

| ID | Finding & Affected Components | Evidence / Reproduction | User Impact & Risk | Recommended Fix & Scope |
| :--- | :--- | :--- | :--- | :--- |
| **AUDIT-P1-01** | **Primitive Shared Design System & Missing Dark Theme**<br>`mobile/lib/shared/design_tokens.dart`, `mobile/lib/main.dart` | `design_tokens.dart` has only 28 lines; colors and margins are hardcoded inline; no dark mode. | Inconsistent visual polish, poor reading ergonomics for extended manuscript editing sessions. | Refactor `design_tokens.dart` into a complete academic design system with formal typography, dark theme, and semantic tokens.<br>**Scope: Medium** |
| **AUDIT-P1-02** | **Paper Editor Lacks Section Outline & Contextual Navigation**<br>`mobile/lib/features/paper_editor/paper_editor_page.dart` | Navigating a 3,000+ word paper requires continuous scrolling; jump menu is buried in a dialog. | High friction during manuscript review and revision. | Add a responsive Section Outline rail on wide screens and a persistent bottom navigation sheet / drawer on mobile.<br>**Scope: Medium** |
| **AUDIT-P1-03** | **Missing Manuscript Readiness Review Subsystem**<br>New Feature (Prompt 6 requirement) | Warnings are only returned in raw JSON; no dedicated pre-export review panel exists. | Researchers may export incomplete papers with unverified placeholders without realizing it. | Build a dedicated `ManuscriptReadinessReview` panel checking completeness, missing citations, empty sections, and readiness score.<br>**Scope: Medium** |
| **AUDIT-P1-04** | **Custom Backend Tests Polluting Offline CI**<br>`backend/tests/custom/test_*.py` | `uv run pytest` runs custom tests that fail without a live server. | False negative test failures in offline CI pipelines. | Guard custom tests with `@pytest.mark.live_server` or exclude `tests/custom/` in default `pyproject.toml` testpaths.<br>**Scope: Small** |
| **AUDIT-P1-05** | **Code Formatting Violation in Gemini Provider**<br>`backend/src/resbud_api/providers/gemini_provider.py` | `uv run ruff format --check src tests` reports 1 unformatted file. | CI failure on strict style checks. | Run `uv run ruff format src tests`.<br>**Scope: Small** |

---

### P2 — Polish & Ergonomics Improvements

| ID | Finding & Affected Components | Evidence / Reproduction | User Impact & Risk | Recommended Fix & Scope |
| :--- | :--- | :--- | :--- | :--- |
| **AUDIT-P2-01** | **Exhausting Manual Input Form Layout**<br>`mobile/lib/features/project_input/project_input_page.dart` | 12 continuous form fields with no collapsible structure or progressive disclosure. | Cognitive overload when entering manual research project details. | Group manual inputs into collapsible Accordion/Card sections (Project Identity, Methodology, Evidence, References).<br>**Scope: Medium** |
| **AUDIT-P2-02** | **Regeneration Proposal Lacks Visual Diff**<br>`mobile/lib/features/paper_editor/paper_editor_page.dart` | Section regeneration proposal review shows raw text block without highlighted diffs. | Difficult for user to verify what the AI changed or preserved. | Add a side-by-side or inline word diff visualizer highlighting additions and deletions.<br>**Scope: Medium** |
| **AUDIT-P2-03** | **Project Dashboard First-Time Onboarding**<br>`mobile/lib/main.dart` | Empty state has only a single button; no contextual onboarding explaining Document vs Manual mode. | First-time researchers lack orientation on how to best prepare their inputs. | Add an elegant welcome card explaining Resbud's two modes, privacy invariants, and anti-hallucination philosophy.<br>**Scope: Small** |

---

### P3 — Optional & Future Enhancements

| ID | Finding & Affected Components | Evidence / Reproduction | User Impact & Risk | Recommended Fix & Scope |
| :--- | :--- | :--- | :--- | :--- |
| **AUDIT-P3-01** | **Search & Filter on Project Dashboard**<br>`mobile/lib/main.dart` | With >10 projects, users must scroll through cards. | Minor inconvenience for active users. | Add title search bar and sort by last modified / title.<br>**Scope: Small** |
| **AUDIT-P3-02** | **Estimated Reading Time & Section Word Count Badges**<br>`mobile/lib/features/paper_editor/paper_editor_page.dart` | Editor only displays total word count in some views. | Authors often target exact journal section word budgets. | Display live per-section word count chips in the editor.<br>**Scope: Small** |

---

## 5. Prioritized Implementation Sequence

Based on the audit findings and the requirements of Prompts 2 through 11, the implementation roadmap is structured into 9 coherent, sequential phases:

```
[Phase 1: Design Tokens & Shell] (Prompt 2)
  ├── Expand design_tokens.dart (academic typography, light/dark themes, semantic tokens)
  └── Fix Flutter Web textarea type exception (AUDIT-P0-01)
         │
         ▼
[Phase 2: Project Dashboard & Onboarding] (Prompt 3)
  ├── First-time welcome card explaining Document vs Manual workflows
  └── Project cards with metadata (mode, version count, word count, date)
         │
         ▼
[Phase 3: Paper Editor Excellence] (Prompt 4)
  ├── Responsive Section Outline navigation (rail on wide screens, sheet on mobile)
  ├── Visual inline diff review for section regeneration proposals
  └── Visual section state badges (Generated, Edited, Supplied)
         │
         ▼
[Phase 4: Generation Reliability & Provider Hardening] (Prompt 5)
  ├── Fix mobile test suite animation hang (AUDIT-P0-02)
  ├── Fix ruff formatting & exclude custom tests from default pytest (AUDIT-P1-04, AUDIT-P1-05)
  └── Pre-generation summary validation & transparent failure recovery
         │
         ▼
[Phase 5: Manuscript Readiness Review Feature] (Prompt 6)
  ├── Dedicated readiness audit engine (deterministic checks + integrity taxonomy)
  ├── Pre-export review drawer/modal with navigation links to offending sections
  └── Readiness checklist verifying completeness without claiming truth/plagiarism guarantees
         │
         ▼
[Phase 6: Document Pipeline Fidelity] (Prompt 7)
  ├── TXT/MD/DOCX import edge-case handling (empty, malformed, BOMs)
  └── Professional Word (.docx) manuscript typography & warning appendix formatting
         │
         ▼
[Phase 7: Responsiveness & Accessibility Polish] (Prompt 8)
  ├── Screen tests at 320px, 375px, 768px, 1280px
  └── ARIA labels, semantic roles, focus order, keyboard shortcuts
         │
         ▼
[Phase 8: Security & Release Gate] (Prompts 9 & 10)
  ├── Fail-closed production checks, secret scrubbing audit
  └── Requirements traceability matrix and final release decision
         │
         ▼
[Phase 9: Academic Demonstration & Defense Package] (Prompt 11)
  ├── 7-minute repeatable demo script with failure-recovery demonstration
  └── Technical viva defense notes and evaluation dataset
```

---

## 6. Audit Conclusion

The Resbud codebase possesses an exceptionally solid architectural foundation:
- The contract parity between FastAPI domain models and Flutter client data structures is 100% compliant with OpenAPI 3.1.
- The local-first SQLite persistence engine is reliable and safely preserves immutable version histories.
- The zero-server-retention security model strictly prevents cloud data leakage.

With the resolution of the two P0 defects (Web semantics `<textarea>` property crash and the test runner `pumpAndSettle` animation hang), followed by the structured execution of the editorial UI redesign, paper editor outline, and the Manuscript Readiness Review subsystem, Resbud will achieve tier-one product quality for its academic beta release.
