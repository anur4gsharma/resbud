# 04 — Evaluation Protocol and Measured Results

This document establishes the repeatable evaluation protocol, fixture definitions, execution commands, and verified results for the Resbud system. 

In strict adherence to academic rigor:
> **All numbers and test counts in this document reflect actual observed test outputs in this repository. No unrun evaluations, synthetic user-study scores, or fabricated benchmarks are presented.**

---

## 1. Automated Test Suite Metrics

All tests execute completely offline without requiring network access, token expenditures, or cloud credentials.

| Test Suite | Framework | Scope / Coverage | Tests Executed | Passed | Failed | Execution Time |
|---|---|---|---|---|---|---|
| **Backend Unit & API** | `pytest` 8.4.2 (Python 3.14) | Domain contracts, integrity guards, routes, auth, rate limits, docx export, settings | 105 | 105 | 0 | 1.36s |
| **Mobile Client** | `flutter_test` (Dart 3.11) | SQLite repositories, migrations, importers, page widgets, UX polish, vertical slices | 111 | 111 | 0 | 10.8s |
| **Backend Static Analysis** | `ruff` (linter & formatter) | Code style, import sorting, syntax rules | 36 files | 36 clean | 0 | 0.08s |
| **Backend Type Checker** | `mypy` (strict mode) | Strict type annotations across all source modules | 23 modules | 23 clean | 0 | 0.62s |
| **Mobile Static Analysis** | `flutter analyze` | Dart static analysis, deprecations, null-safety | Whole project | 0 issues | 0 | 0.5s |
| **Total Automated Tests** | — | — | **216** | **216** | **0** | **~13s total** |

---

## 2. Deterministic AI Evaluation Fixtures (`v1`)

The repository includes a versioned deterministic evaluation suite located at `backend/tests/evaluation/v1/manifest.json`. Each test profile is executed against the fake provider and integrity pipeline by `test_ai_evaluation_set.py`.

### 2.1 Profile Catalog and Observed Behavior

| Case ID | Input Characteristics | Expected Invariant | Measured Result | Status |
|---|---|---|---|---|
| **`complete-input`** | Full method, results (91% accuracy), limitations, and references provided. | Schema valid; no `MISSING_RESULTS` or `MISSING_METHOD` warnings. | 0 forbidden warnings emitted; references preserved. | **PASSED** |
| **`missing-results`** | Results explicitly marked `unknown` with null details. | Mandatory `MISSING_RESULTS` warning; results section flagged as needing user data. | `MISSING_RESULTS` emitted; placeholder preserved. | **PASSED** |
| **`missing-methods`** | Methodology marked `unknown` with null description. | Mandatory `MISSING_METHOD` warning; methodology flagged. | `MISSING_METHOD` emitted. | **PASSED** |
| **`conflicting-claims`** | Project context states 91% accuracy; draft text mentions 87%. | Mandatory `INPUT_CONFLICT` warning; system refuses to arbitrarily select one value. | `INPUT_CONFLICT` emitted. | **PASSED** |
| **`incomplete-reference`** | Supplied reference contains placeholder (`TBD: verify venue`). | Mandatory `REFERENCE_INCOMPLETE` warning; reference retained without fabrication. | `REFERENCE_INCOMPLETE` emitted; reference kept. | **PASSED** |
| **`non-experimental-research`** | Methodology is conceptual; results marked `not_applicable`. | No missing results warning; clean conceptual structure generated. | No `MISSING_RESULTS` warning; valid schema. | **PASSED** |
| **`unusual-academic-structure`** | Custom section IDs (`case_study_context`, `ethics_notes`); specialized chemical term `β-lactam`. | Custom IDs and non-ASCII character preserved in generated paper. | All section IDs and unicode characters preserved. | **PASSED** |

---

## 3. Repeatable Command Execution Protocol

To reproduce these results independently from a clean checkout:

### Step 1: Run Backend Tests and Type Checks
```bash
cd backend
.venv/bin/ruff format --check src tests
.venv/bin/ruff check src tests
.venv/bin/mypy src
../backend/.venv/bin/python -m pytest tests/ -v
```
**Expected Outcome**: 105 passed, 0 failures.

### Step 2: Run Mobile Client Tests and Static Analysis
```bash
cd mobile
flutter pub get
flutter analyze
flutter test
```
**Expected Outcome**: No issues found! 111 passed, 0 failures.

### Step 3: Run Full Vertical Slice Integration Suite
```bash
# Backend end-to-end integration:
backend/.venv/bin/python -m pytest backend/tests/test_end_to_end_integration.py -v
# Mobile end-to-end integration:
cd mobile && flutter test test/end_to_end_integration_test.dart
```
**Expected Outcome**: All vertical lifecycle steps (creation, import, generation, isolated section regeneration, persistence, and DOCX export) pass with zero assertions failing.

---

## 4. Status of Deferred / Unrun Evaluations

To ensure absolute academic honesty, the following evaluations are explicitly labeled as **unrun / future work**:

1. **Human Double-Blind Writing Study**:
   - *Status*: **UNRUN**.
   - *Reason*: Conducting a statistically significant double-blind human evaluation requires Institutional Review Board (IRB) approval, a cohort of 50+ researchers, and a 6-month study window.
2. **Real Provider Token Cost and Latency Benchmark**:
   - *Status*: **PARTIALLY VERIFIED VIA MOCK ADAPTER**.
   - *Reason*: Routine CI runs against the offline `FakeProvider`. While the `OpenAIProvider` network adapter is tested with mocked responses and token/timeout bounds in `test_openai_provider.py`, large-scale production token cost benchmarks against live OpenAI models require paid API credits and remain an operational evaluation.
3. **Automated Citation Fact-Checking Benchmark**:
   - *Status*: **DEFERRED BY DESIGN**.
   - *Reason*: Resbud intentionally avoids claiming automated scientific truth verification. It guarantees that user-provided citations are preserved and missing citations are flagged, but does not benchmark against external citation graphs.
