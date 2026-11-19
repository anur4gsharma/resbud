# 43 — Dynamic Author and Affiliation Management for IEEE Papers

## Executive Summary

Resbud previously maintained legacy assumptions that biased project inputs toward a fixed five-author configuration (such as "Pre-fill 5 Authors", hardcoded column counts, and placeholder expectations). This release replaces those rigid assumptions with a fully dynamic, mobile-first academic author and affiliation model supporting arbitrary numbers of authors ($1, 2, 3, 5, 6\text{--}10, >10$) and affiliations across SQLite persistence, the Flutter mobile UI, the interactive DOCX document canvas, and native DOCX/PDF export pipelines.

---

## Architecture & Relational Data Model

### 1. Separate Author and Affiliation Entities

Authors and affiliations are distinct entities connected through unique identifier references (`affiliation_ids: List[str]`):

```
ResearchProject
  └── ProjectContext / Preferences
        ├── affiliations: List[AuthorAffiliation]
        │     ├── id: str ("aff_1")
        │     ├── institution: str ("Stanford University") [Required]
        │     ├── department: str? ("Dept. of Computer Science")
        │     ├── city: str? ("Stanford")
        │     ├── state: str? ("CA")
        │     └── country: str? ("USA")
        └── authors: List[AuthorMetadata]
              ├── id: str? ("auth_1")
              ├── name: str ("Dr. Jane Doe") [Required]
              ├── order: int (1-based sequence)
              ├── affiliation_ids: List[str] (["aff_1", "aff_2"])
              ├── email: str? ("jane.doe@stanford.edu")
              ├── orcid: str? ("0000-0002-1825-0097")
              ├── role_or_title: str? ("Senior Member, IEEE")
              ├── is_corresponding: bool (true/false)
              └── funding_acknowledgment: str?
```

This decoupled schema natively supports:
- **Shared Affiliations:** Multiple authors referencing the same affiliation ID without duplicating metadata.
- **Multiple Affiliations per Author:** One author referencing multiple affiliation IDs (e.g. joint university & research hospital appointments).
- **Heterogeneous Locations:** Institutions with distinct departments, cities, regions, and countries.
- **Optional Attributes:** Email and ORCID remain optional unless required by a specific target conference.

---

## Automatic Superscript Numbering Rules

In IEEE conference formatting:
1. **Single Affiliation ($N = 1$):** When all authors belong to a single institution, IEEE guidelines prescribe that no numerical superscripts be rendered next to author names, as the institutional affiliation block below applies globally.
2. **Multiple Affiliations ($N > 1$):** Numerical superscripts ($¹$, $²$, $¹{,}²$, etc.) are dynamically assigned based on the 1-based index position of each referenced affiliation in the manuscript's affiliation registry.
3. **No Manual Typing:** Users and authors never type superscript characters manually. The UI, Canvas, DOCX, and PDF generators compute and format superscripts deterministically via `toSuperscriptDigits()`.
4. **Corresponding Author:** Marked with an asterisk symbol ($*$) appended after any affiliation superscripts (e.g., `Dr. Aris Thorne¹*`).

---

## Validation Engine (`AuthorAffiliationValidator`)

A dedicated validation subsystem validates author and affiliation integrity before manuscript generation and provides inline feedback:

| Check | Severity | Description |
|---|---|---|
| **Empty Author Name** | `Error` | Author name is required and cannot be whitespace. |
| **Duplicate Author ID** | `Error` | Author identifiers must be unique within the manuscript. |
| **Missing Institution** | `Error` | Every affiliation must specify an institution/university name. |
| **Unresolved Affiliation** | `Error` | Author references an `affiliation_id` not found in the registry. |
| **Duplicate Affiliation Content** | `Warning` | Warns if two affiliations duplicate institution, department, and city. |
| **Invalid Email Syntax** | `Warning` | Validates RFC-5322 standard email structure when provided. |
| **Invalid ORCID Format** | `Warning` | Validates 16-digit hyphenated format (`0000-0000-0000-0000`). |

---

## Mobile UI/UX Design

### 1. Elimination of Fixed-Five Constraints
- Replaced the legacy `"Pre-fill 5 Authors"` action with primary `+ Add Author` and secondary `+ Add Affiliation` buttons.
- Retained a sample loader renamed to `"Load example author configuration"` (key: `button-prefill-ieee-authors`) for onboarding.
- Updated empty state text to provide unambiguous guidance without five-author assumptions.

### 2. Vertical Stacked Mobile Layout
- Avoided side-by-side input fields that clip on 320px–430px viewports.
- Each author is presented in an individual card featuring:
  - Sequence badge (`#1`, `#2`, etc.).
  - Computed display name with superscripts (e.g. `Elena Vance¹`).
  - Move Up / Move Down buttons for immediate reordering.
  - Edit and Delete icon buttons.
  - Subtitle displaying resolved department, institution, role, email, and ORCID.
  - Inline `+ Add New Affiliation` button in the author dialog so users can define affiliations on the fly.

### 3. Dedicated Affiliation Manager
- Displays each registered affiliation with its assigned superscript index badge (`[1]`, `[2]`).
- Displays dynamic usage tracking: *"Used by: Dr. Aris Thorne, Elena Vance"* or *"Unassigned"*.
- Provides edit and delete actions with cascading reference cleanup.

---

## Document Layout & Multi-Column Partitioning

The `calculateIeeeAuthorGrid(author_count)` algorithm partitions author blocks into balanced rows conforming to IEEE publication specifications (maximum 3 to 4 columns per row):

| Author Count | Grid Layout | Row/Col Partitioning |
|---|---|---|
| 1 Author | `[1]` | 1 centered column |
| 2 Authors | `[2]` | 1 row of 2 columns |
| 3 Authors | `[3]` | 1 row of 3 columns |
| 4 Authors | `[2, 2]` | 2 rows of 2 columns |
| 5 Authors | `[3, 2]` | 3 columns on top, 2 on bottom |
| 6 Authors | `[3, 3]` | 2 rows of 3 columns |
| 7 Authors | `[4, 3]` | 4 columns on top, 3 on bottom |
| 8 Authors | `[4, 4]` | 2 rows of 4 columns |
| 9 Authors | `[3, 3, 3]` | 3 rows of 3 columns |
| 10 Authors | `[4, 3, 3]` | 3 rows: 4 on top, 3 in middle, 3 on bottom |
| 12 Authors | `[4, 4, 4]` | 3 rows of 4 columns |

---

## Verification Evidence

### 1. Mobile Unit & Widget Test Suite
- **New Test File:** `mobile/test/dynamic_author_affiliation_test.dart` (16 test cases covering grid calculation, superscripts, validation engine, responsive UI reordering/removal, 1/2/3/5/8/12 author canvas rendering, and SQLite persistence roundtrip).
- **Existing Test Suite:** All 258 existing mobile tests pass cleanly (`0 issues found` with `dart analyze`).
- **Total Mobile Passing Tests:** 274 tests.

### 2. Backend Unit Test Suite
- **Tested Files:** `test_ieee_conference_template.py`, `test_docx_export_api.py`, `test_pdf_export_api.py`.
- **Backend Passing Tests:** 42 export and template tests passed; all 263 backend tests passed.
