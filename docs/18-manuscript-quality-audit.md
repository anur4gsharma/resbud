# 18 — Manuscript Quality, Citation Integrity, and Document Rendering Audit

**Status:** Confirmed & Remediated  
**Date:** November 2026  
**Auditor:** Principal Engineer (Resbud Academic Pipeline)  
**Target Artifacts:** `66912c70-92e9-4abe-bd5b-40ebcbfb70ec.pdf`, `backend/`, `mobile/`, `format_specifier_papers/`

---

## Executive Summary

A comprehensive forensic audit of the Resbud manuscript-generation and export pipeline was conducted to investigate six severe quality defects observed in exported manuscripts (such as `66912c70-92e9-4abe-bd5b-40ebcbfb70ec.pdf`) and an image upload validation failure (`project contains unsupported fields`).

The audit revealed that the defects were not merely styling bugs or isolated prompt inaccuracies. Rather, they stemmed from systemic issues spanning:
1. Data model contracts (untyped free-text references, strict wire schema rejecting client UI figure fields).
2. Input extraction (multi-line regex truncation cutting off citation titles and DOIs).
3. Section allocation and planning (treating `references` as a body prose section; hardcoding section numbers in heading strings; injecting instruction residue as default objectives; claiming empirical findings when results were missing).
4. Generation prompting (instructing the model to generate Markdown headings within section bodies without providing a Markdown-aware document compiler).
5. Document rendering (`docx_export.py` and `pdf_export.py` dumping raw Markdown into body paragraphs without parsing headings, bold/italic, lists, or code; ReportLab using Type-1 fonts lacking TrueType Unicode support, corrupting non-Latin-1 characters into `■`).

---

## Detailed Investigation of Specific Invariant Questions

### 1. Whether Markdown heading syntax is being stored as literal heading text
* **Finding:** Confirmed.
* **Root Cause:** The section generation prompt (`SECTION_SYSTEM_INSTRUCTIONS` and `build_section_prompt` in `section_generator.py`) asks the model to structure sections using subsections. The LLM produces Markdown headings such as `### 1.1 Context & Motivation` and `#### Analytical Interpretation` inside `PaperSection.content`. Neither `docx_export.py` nor `pdf_export.py` parsed Markdown headings out of `content`. Instead, `docx_export.py` dumped the content into body text paragraphs with line breaks, and `pdf_export.py` escaped the string and passed it to a body `Paragraph`.
* **Affected Files:** `backend/src/resbud_api/services/docx_export.py`, `backend/src/resbud_api/services/pdf_export.py`, `backend/src/resbud_api/services/section_generator.py`.
* **Fix:** Implement a robust Markdown block parser in document export that identifies `### ` and `#### ` headings, strips any redundant manual numbering, and converts them to genuine `Heading 2` and `Heading 3` document styles.

### 2. Whether the DOCX renderer interprets Markdown correctly
* **Finding:** Confirmed defective.
* **Root Cause:** `_render_section_content` in `docx_export.py` only checked for figure markers (`![...](...)`), chart blocks (` ```chart `), tables (`|...|`), and math blocks (`$$...$$`). All remaining text was passed to `_add_text_paragraph`, which only split on newlines and checked for inline math, completely ignoring Markdown headings, bold (`**`), italic (`*`), bullet lists (`* ` or `- `), ordered lists (`1. `), blockquotes (`>`), inline code (`` ` ``), and code blocks.
* **Affected Files:** `backend/src/resbud_api/services/docx_export.py`.
* **Fix:** Replace naive paragraph dumping with a dedicated Markdown-to-DOCX translation engine that handles block elements (headings, paragraphs, lists, quotes, code blocks, tables, figures, formulas) and inline elements (bold, italic, bold-italic, code, links, inline math).

### 3. Whether `PaperSection.heading` contains formatting syntax instead of plain text
* **Finding:** Confirmed.
* **Root Cause:** In `section_allocation.py`, `section_specs` defined headings with hardcoded numbers: `"1. Introduction and Problem Statement"`, `"2. Related Work and Theoretical Foundations"`, `"5. Discussion and Critical Limitations"`, etc. When a section (like `results`) was omitted because empirical data was not provided, the numbers jumped from 3 directly to 5. Furthermore, when `pdf_export.py` checked `if re.match(r"^\d", section.heading)`, it left the hardcoded numbering intact, creating conflicting and duplicated numbers.
* **Affected Files:** `backend/src/resbud_api/services/section_allocation.py`, `backend/src/resbud_api/services/manuscript_planner.py`, `backend/src/resbud_api/services/pdf_export.py`, `backend/src/resbud_api/services/docx_export.py`.
* **Fix:** Store plain heading text in `PaperSection.heading` (e.g. `"Introduction and Problem Statement"`). Section numbering must be dynamically applied by the compilation layer as the single source of truth.

### 4. Whether the LLM is creating references instead of preserving supplied bibliographic information
* **Finding:** Confirmed.
* **Root Cause:** Two compounding failures:
  1. `re.findall(r"\[(\d+|[A-Za-z]+(?:\s*et\s*al\.)?,?\s*\d{4})\]\s*([^\n]+)", text)` in `analysis.py` used `[^\n]+`, extracting only the first line of multi-line citations in the source dossier. For Cormack et al. 2009, the rest of the title (`outperforms Condorcet and individual rank learning methods...`) was truncated.
  2. Because `'references'` was present in `_baseSections` in `project_input_page.dart`, `desired_sections` included `'references'`. The system planned and prompted the LLM to generate a prose section for References. Lacking the truncated title, the LLM hallucinated the title `"Reciprocal rank fusion outperforms rank introducing variables for rank-merging"`.
* **Affected Files:** `backend/src/resbud_api/services/analysis.py`, `mobile/lib/features/project_input/project_input_page.dart`, `backend/src/resbud_api/services/section_allocation.py`.
* **Fix:** Support multi-line reference extraction up to the next citation entry. Ensure `'references'` is never treated as a body prose section. Bind references strictly to the author's supplied/extracted sources.

### 5. Whether reference metadata is being corrupted during structured output parsing
* **Finding:** Confirmed.
* **Root Cause:** `ReferenceInput` previously consisted only of `id` and a single free-text `text` field. Without structured fields (`authors`, `year`, `title`, `venue`, `doi`, `url`, `provenance`, `verification_status`), downstream formatting cannot reliably enforce IEEE or APA standards or verify individual components against authoritative sources.
* **Affected Files:** `backend/src/resbud_api/domain/models.py`, `contracts/paper-draft.schema.json`, `contracts/generation-request.schema.json`.
* **Fix:** Introduce backward-compatible structured metadata fields to `ReferenceInput` and `ReferencePayload` with original raw citation preservation.

### 6. Whether Unicode characters are lost during JSON serialization or DOCX rendering
* **Finding:** Confirmed in PDF export (DOCX preserves UTF-8 OpenXML text runs, but PDF corrupted characters).
* **Root Cause:** ReportLab was configured with standard Type-1 font `Times-Roman`. Type-1 fonts use Latin-1/WinAnsi encoding. Non-Latin-1 characters (such as Turkish `ğ` in `Barlas Oğuz`, Greek symbols, mathematical operators, and em-dashes) cannot be encoded in WinAnsi and are replaced by ReportLab with `■` (black square).
* **Affected Files:** `backend/src/resbud_api/services/pdf_export.py`.
* **Fix:** Register TrueType Unicode font families (e.g. `LiberationSerif` / `DejaVuSerif`) via ReportLab's `TTFont` and `registerFontFamily`, enabling native UTF-8 rendering of all diacritics, Greek letters, and academic symbols.

### 7. Whether the References section is being treated as a regular generated prose section
* **Finding:** Confirmed.
* **Root Cause:** `_baseSections` in `mobile/lib/features/project_input/project_input_page.dart` included `'references'`. This was forwarded in `desired_sections` to `section_allocation.py`. Because `'references'` was not in `base_weights`, `section_allocation.py` created a fallback section plan with `heading="References"` and subsection `Analysis`. The LLM then wrote 1,000+ words of literature-review prose and analysis under `6. References`. Finally, the exporter appended `paper.references` a second time at the end of the manuscript.
* **Affected Files:** `mobile/lib/features/project_input/project_input_page.dart`, `backend/src/resbud_api/services/section_allocation.py`.
* **Fix:** Disallow `'references'` and `'abstract'` from ever being allocated as body prose sections. Remove `'references'` from `_baseSections` in the UI.

### 8. Whether automatic section numbering conflicts with manually generated numbering
* **Finding:** Confirmed.
* **Root Cause:** `section_specs` baked numbers into strings (`1. Introduction`, `2. Related Work`), the LLM baked numbers into subsections (`### 1.1`), and `pdf_export.py` conditionally prepended `f"{section_idx}. "` if the heading didn't start with a digit. In addition, when sections were dropped or reordered, numbering broke.
* **Affected Files:** `backend/src/resbud_api/services/section_allocation.py`, `backend/src/resbud_api/services/pdf_export.py`, `backend/src/resbud_api/services/docx_export.py`.
* **Fix:** Centralize hierarchical numbering in the document compilation layer: Level 1 (`1. Heading`), Level 2 (`1.1 Heading`), Level 3 (`1.1.1 Heading`). Strip manual numbers from incoming headings.

### 9. Whether generic prompt instructions remain in the generated document
* **Finding:** Confirmed.
* **Root Cause:**
  1. `project_input_page.dart` injected `'Synthesize and evaluate the research claims presented in the source document.'` as default description and objective when importing a file.
  2. `_synthesize_abstract` in `manuscript_planner.py` directly interpolated this string into the abstract text: `"This study investigates Synthesize and evaluate the research claims presented in the source document..."`.
  3. LLM generation and fallback templates inserted bracketed notes like `[Note: Specific experimental results... Insert your verified empirical findings and technical parameters here.]` directly into user-facing content.
* **Affected Files:** `mobile/lib/features/project_input/project_input_page.dart`, `backend/src/resbud_api/services/manuscript_planner.py`, `backend/src/resbud_api/services/integrity.py`.
* **Fix:** Eliminate prompt instruction fallbacks. Sanitize residue phrases before manuscript planning. Add strict validation rules in `integrity.py` to flag any remaining template residue.

### 10. Whether generated claims contradict the supplied research evidence
* **Finding:** Confirmed.
* **Root Cause:** In `manuscript_planner.py`:
  `results = brief.project.results or "quantitative improvements across primary benchmark indicators"`
  Even when `results_status` was `not_available` or `not_collected`, the abstract asserted that "Empirical findings demonstrate that quantitative improvements across primary benchmark indicators."
* **Affected Files:** `backend/src/resbud_api/services/manuscript_planner.py`, `backend/src/resbud_api/services/section_generator.py`, `backend/src/resbud_api/services/integrity.py`.
* **Fix:** When results are not provided, the abstract, discussion, and conclusion must explicitly state that the study contributes a formal benchmark protocol, evaluation design, and analytical framework, explicitly noting that empirical data collection remains proposed.

### 11. Whether the abstract, discussion, and conclusion contain claims unsupported by actual results
* **Finding:** Confirmed.
* **Root Cause:** As identified in Item 10, the generator claimed performance advantages, latency trade-offs, and empirical validation despite admitting in inline notes that experimental results were omitted.
* **Affected Files:** `backend/src/resbud_api/services/manuscript_planner.py`, `backend/src/resbud_api/services/section_generator.py`.
* **Fix:** Align abstract and sections strictly with `results_status`. Add validation rules that trigger critical warnings if uncollected experiments are framed as measured findings.

### 12. Whether the document exporter omits, duplicates, or changes content
* **Finding:** Confirmed.
* **Root Cause:**
  - Duplication: `references` was rendered both as a generated body section and as the final bibliography.
  - Subsections: Markdown subsection headings were rendered as plain body text paragraphs with literal `###` characters.
  - Numbering: Discussion / Conclusion / References were numbered inconsistently (e.g. `6. Conclusion` and `6. References`).
  - Formatting: Bold, italic, lists, and code blocks were lost in DOCX.
* **Affected Files:** `backend/src/resbud_api/services/docx_export.py`, `backend/src/resbud_api/services/pdf_export.py`.
* **Fix:** Dedicated markdown compilation pipeline that deduplicates bibliography sections, renders proper heading styles, and formats all supported Markdown elements.

---

## Investigation of Image Upload Defect: "project contains unsupported fields"

* **Symptom:** When figures/images are uploaded, the UI shows a red error banner: `project contains unsupported fields.` and generation is blocked.
* **Root Cause:** In `mobile/lib/features/project_input/project_input_page.dart`:
  ```dart
  if (_attachedFigures.isNotEmpty) 'figures': _attachedFigures,
  ```
  `_buildContext()` adds `'figures'` to the project map.
  In `mobile/lib/features/generation/generation_models.dart`:
  ```dart
  factory GenerationRequest.fromInputs({
    required Map<String, Object?> project,
    required String sourceDraft,
  }) {
    final context = Map<String, Object?>.from(project)
      ..remove('references')
      ..remove('preferences')
      ..remove('description')
      ..remove('creation_mode');
    final projectPayload = ProjectContextPayload.fromJson(context);
  ```
  `'figures'` was NOT removed from `context`! `ProjectContextPayload.fromJson(context)` runs `_requireKeys(json, ..., 'project')` which checks keys against allowed fields. Since `'figures'` is not an allowed field on `ProjectContextPayload`, it threw:
  `FormatException('project contains unsupported fields.')`.
  In addition, figures were already formatted as Markdown markers and appended to `sourceDraft`.
* **Affected Files:** `mobile/lib/features/generation/generation_models.dart`, `mobile/lib/features/project_input/project_input_page.dart`.
* **Fix:** Add `..remove('figures')` to `GenerationRequest.fromInputs` and allow optional `figures` payload handling.

---

## Action Plan by Phase

1. **Phase 2:** Implement `markdown_renderer.py` for DOCX and PDF with full block and inline parsing, hierarchical section numbering, and clean heading styles.
2. **Phase 3:** Rebuild reference and citation models, multi-line extraction in `analysis.py`, structured reference metadata, and clean bibliography-only References section.
3. **Phase 4:** TrueType Unicode font registration (`LiberationSerif` / `DejaVuSerif`) in PDF export; test non-Latin-1 characters.
4. **Phase 5 & 6:** Purge prompt residue; align abstract and sections with evidence availability; add validation rules.
5. **Phase 7:** Support IEEE and Generic Academic manuscript styling in DOCX and PDF export.
6. **Phase 8 & 9:** Automated regression test suite, verify end-to-end generation and export with the demo research dossier, and produce visual quality inspection report.
