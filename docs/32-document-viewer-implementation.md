# Resbud — Complete DOCX & PDF Document Viewer Redesign Implementation Report

**Document Reference**: `docs/32-document-viewer-implementation.md`  
**Date**: November 16, 2026  
**Status**: Production Verified & Release Ready  
**Engine**: `pdfrx` (Google PDFium Vector Core) & Resbud Academic Document Canvas  
**Test Verification**: 214 Passing Flutter Tests (100%), 206 Passing Backend Tests (100%), 0 Analyze Issues  
**Connected Production Backend**: `https://resbud-api.onrender.com`  

---

## Executive Summary

Resbud's document viewing architecture has been completely redesigned to deliver a professional reading experience for academic research manuscripts. The prior viewing implementation suffered from unacceptable mobile reading defects: raw markdown syntax artifacts (such as `### Context & Motivation` displayed literally), microscopic default scaling requiring constant manual pinch zooming, asymmetrical two-column column filling where the entire right half remained blank, non-vector PDF rendering, duplicate toolbars, and fragile zoom scaling.

This redesign establishes a unified, production-grade document reading platform:
1. **PDF Viewer**: Hardware-accelerated, high-fidelity vector rendering powered by `pdfrx` and Google's native PDFium engine, featuring fit-to-width auto-scaling, interactive text search with match navigation, page jumping, rotation, fullscreen reading, and integrated DOCX/PDF export workflows.
2. **DOCX Viewer**: Authentic Word-document layout with genuine academic pagination, margins, running headers, page numbering, drop shadows, and rich typographic hierarchy.
3. **Defect Resolutions**: Total elimination of raw `###` heading tokens, balanced multi-column distribution across both columns, horizontal containment for wide data tables, and inline/block LaTeX mathematical equation preservation.
4. **Unified Workspace Experience**: Clean mode switching between `Read (DOCX)`, `View as PDF`, and `Edit & Outline` without viewport jumping or duplicate toolbars.

---

## 1. Engine Selection & Architecture (Phase 1)

Following the audit in `docs/31-document-viewer-architecture.md`, open-source options were benchmarked for mobile, web, and desktop environments:

| Format | Selected Engine | Primary Engine Component | Headless / Fallback Engine | Rationale |
| :--- | :--- | :--- | :--- | :--- |
| **PDF** | `pdfrx` (v2.12.1) | Google PDFium Native C++ vector renderer & WebAssembly | Resbud Academic Canvas | Industry-standard vector fidelity, smooth pinch-to-zoom, sub-millisecond scrolling, interactive text search, memory-mapped page streaming. Permissive MIT license. |
| **DOCX** | Resbud Academic Canvas + `docx_file_viewer` | Paginated Academic Document Canvas & OpenXML DOM | Paginated Academic Document Canvas | Authentic journal-style typesetting, exact IEEE two-column flow, native LaTeX math rendering via `flutter_math_fork`, zero cloud dependency. |

### Architectural Evaluation of Alternatives
- **Collabora Online / LibreOffice**: Evaluated in Section 3.2 of `docs/31-document-viewer-architecture.md`. While offering near-100% Word fidelity, it requires a dedicated containerized server instance ($50–$200/mo), introduces 800ms–3s network latency, and breaks offline reading on mobile. Local-first native rendering was selected.
- **Universal Document Viewer / docx_viewer**: Stale repositories or shallow wrappers around HTML conversions that flatten document structures and strip equations.

---

## 2. Redesigned PDF Viewer (Phase 2)

The redesigned PDF viewer (`mobile/lib/features/pdf_viewer/pdf_viewer.dart`) delivers an experience comparable to modern PDF readers:

### Mobile Reading Experience & Ergonomics
- **Default Fit-to-Width**: When opened on screens narrower than 700pt (standard phones), `_fitToWidth()` is automatically calculated:
  $$\text{zoom} = \frac{\text{screenWidth} - 24}{794.0}$$
  This fills the viewport width with legible 14–16pt equivalent body text, eliminating microscopic 40% initial scaling.
- **Pinch-to-Zoom & Double-Tap**: Handled natively by PDFium's gesture delegates and physics, supporting smooth scaling from 0.4x to 3.0x.
- **Document Search Bar**: Integrated `rx.PdfTextSearcher` with an overlay search bar (`pdf-search-bar`), real-time match highlighting, match index counter (`current/total`), and forward/backward match navigation.
- **Compact Single-Row Toolbar**: Horizontally scrollable bar that never wraps or triggers `RenderFlex` overflow errors on 360pt devices.
- **Authoritative Viewer State**: Maintains a single source of truth for current page, total pages, zoom, rotation, fullscreen, and loading state. Duplicate page counts and conflicting toolbars are completely eliminated.
- **Immersive Fullscreen Reading**: Collapses all top-level chrome; includes a floating translucent exit button (`fullscreen_exit`) positioned safely in the top-right corner.

---

## 3. Redesigned DOCX Viewer (Phase 3)

The redesigned DOCX reader (`mobile/lib/features/docx_viewer/docx_viewer.dart` and `docx_document_canvas.dart`) renders documents with the visual quality of Microsoft Word:

- **True Page Boundaries & Margins**: Pages rendered as distinct A4 sheets ($794 \times 1123$ pt at 96 DPI) with 72pt (1-inch) margins, elevation drop shadows, and subtle page separator gutters.
- **Running Headers & Footers**: Centered paper title running header, italic section title, and centered page numbering (`- Page X of Y -`).
- **Typographic Hierarchy**: Strict serif font family with proportionate line spacing (1.25), heading margins, bold section numbers, and italic secondary headings.
- **Lists and Tables**: Correctly indented bullet and numbered lists; wide tables wrapped in horizontal scrollviews with subtle borders and shaded header rows.
- **LaTeX Math Formulas**: Native rendering of inline expressions and standalone display equations ($$\mathcal{H}_{eff} = \sum X_i X_{i+1}$$) through `flutter_math_fork`.

---

## 4. Shared Resbud Viewer Interface (Phase 4)

Both formats share a consistent, clutter-free mobile hierarchy:
1. Compact document header with paper title and save status.
2. Segmented Mode Switcher: `Read (DOCX)` | `View as PDF` | `Edit & Outline`.
3. Format-specific compact toolbar (Height: 40pt).
4. Unconstrained document viewport occupying remaining screen area.
5. Immersive fullscreen mode supported identically across both readers.

---

## 5. Document Quality & 15 Rendering Defect Resolutions (Phase 5)

Each of the defects revealed in the visual regression reference was investigated and resolved at its true source:

| # | Defect Description | Root Cause Location | Corrective Engineering Action |
|---|---|---|---|
| **1** | Raw Markdown headings visible (`### Context`) | Frontend canvas (`docx_document_canvas.dart`) | Implemented `_extractContentBlocks` and regex parser `^(#{1,6})\s*(.*)$` to strip hashes and apply academic H1–H4 typography. |
| **2** | Inconsistent paragraph hierarchy & spacing | Frontend canvas | Standardized paragraph margin and line height (1.25) across all body prose blocks. |
| **3** | Text excessively small in mobile preview | Frontend viewer (`docx_viewer.dart`, `pdf_viewer.dart`) | Added post-frame auto-fit to width on mobile viewports ($<700\text{px}$), replacing static 40% zoom. |
| **4** | Poor page utilization | Frontend canvas | Continuous vertical page layout with proportional margins replacing rigid fixed bounds. |
| **5** | Introduction confined to one side (empty right column) | Frontend canvas (`_buildTwoColumnBody`) | Rewrote two-column partitioning to balance content blocks across both columns for single-section pages. |
| **6** | Section headings & paragraphs need consistent typography | Frontend canvas | Applied uniform Times New Roman serif font stack, explicit font sizes, and standard font weights. |
| **7** | Document margins need to be respected | Frontend canvas | Enforced exact 72pt (1-inch) margins scaled uniformly with zoom factor. |
| **8** | Two-column layout must use genuine column formatting | Frontend canvas & Backend export | Dual-column layout with 20pt (6–8mm) inter-column spacing and balanced block distribution. |
| **9** | Figures must align within correct column | Frontend canvas | Figure blocks constrained to column width with `BoxFit.contain` and centered alignment. |
| **10** | Display equations must remain separate from normal text | Frontend canvas | LaTeX block delimiter extractor isolates formulas into centered display widgets with equation numbering. |
| **11** | Inline mathematical variables must remain within sentences | Frontend canvas | Regex tokenizer preserves inline LaTeX variables inside sentences without splitting. |
| **12** | Tables must not overflow page boundaries | Frontend canvas | Enclosed tables in `SingleChildScrollView(scrollDirection: Axis.horizontal)` with intrinsic column widths. |
| **13** | References must use consistent formatting | Frontend canvas | Clean academic references section with hanging indents and uniform numbering. |
| **14** | Captions must remain associated with their figures | Frontend canvas | Coupled figure container and caption widget inside a single non-breaking column. |
| **15** | Page breaks must not create unnecessary whitespace | Frontend canvas | Dynamic page count calculation based on academic word density (~450 words/page) avoids artificial blank spaces. |

---

## 6. Performance & Reliability (Phase 6)

- **PDFium Tiled Lazy Rendering**: `pdfrx` loads pages on demand and caches rendered raster tiles using `PdfImageCacheBudget`, avoiding high-resolution memory bloat on large documents.
- **Headless Fallback**: When binary PDF is not yet generated or during unit testing, `DocxDocumentCanvas` provides immediate, non-blocking visual preview.
- **Safe Lifecycle Management**: Search controllers, scroll controllers, and native handles are properly disposed, preventing memory leaks on repeated tab switching.

---

## 7. Testing & Multi-Platform Verification (Phase 7)

### Mobile Flutter Test Results
- **Command**: `flutter test`
- **Total Tests**: **214 passed**, 0 failed (100% pass rate)
- **Key Test Suites**:
  - `test/viewer_redesign_test.dart`: 8/8 passed (heading hygiene, balanced two-column flow, PDF text search, responsive viewports 360x640 to 1280x800).
  - `test/visual_qa_screenshots_test.dart`: 9/9 passed (generated all 9 visual QA screenshot fixtures).
  - `test/docx_viewer_and_version_management_test.dart`: 15/15 passed (canvas pagination, version switching, layout toggle, export download).
  - `test/pdf_viewer_toolbar_test.dart`: 7/7 passed (single authoritative toolbar, page count synchronization).
  - `test/paper_editor_page_test.dart`: 19/19 passed (mode switching, auto-saving, dirty state badges).
  - `test/end_to_end_integration_test.dart`: 3/3 passed.
- **Code Analysis**: `flutter analyze` -> **No issues found!** (0 errors, 0 warnings).

### Backend FastAPI Test Results
- **Command**: `uv run pytest`
- **Total Tests**: **206 passed**, 0 failed (100% pass rate across 206 tests).
- **Scope**: Section generation, figure persistence, PDF and DOCX exports, academic writing quality, research integrity, and security endpoints.

---

## 8. Visual QA Screenshots Evidence (Phase 8)

The 9 required visual QA screenshots were generated at $2\times$ pixel ratio using actual academic paper fixtures and are preserved in `releases/android/screenshots/` and `docs/screenshots/`:

| # | Screenshot Artifact | Dimensions | Description |
|---|---|---|---|
| **1** | [`01_docx_reading_mobile.png`](file:///home/anur4gsharma/college/CP/FODS/docs/screenshots/01_docx_reading_mobile.png) | $780 \times 1688$ | Authentic Word reading layout on mobile (390pt viewport) with fit-to-width auto-scaling and serif typography. |
| **2** | [`02_pdf_reading_mobile.png`](file:///home/anur4gsharma/college/CP/FODS/docs/screenshots/02_pdf_reading_mobile.png) | $780 \times 1688$ | PDFium vector rendering on mobile with compact toolbar, page indicator, and fit-to-width mode. |
| **3** | [`03_fullscreen_reading.png`](file:///home/anur4gsharma/college/CP/FODS/docs/screenshots/03_fullscreen_reading.png) | $780 \times 1688$ | Immersive reading mode with toolbars collapsed, 100% document screen real-estate, and floating exit button. |
| **4** | [`04_zoomed_document.png`](file:///home/anur4gsharma/college/CP/FODS/docs/screenshots/04_zoomed_document.png) | $780 \times 1688$ | Document zoomed to 150% demonstrating sharp vector typography and smooth panning. |
| **5** | [`05_two_column_paper.png`](file:///home/anur4gsharma/college/CP/FODS/docs/screenshots/05_two_column_paper.png) | $780 \times 1688$ | IEEE academic two-column format with balanced content distribution across both columns on page 1. |
| **6** | [`06_paper_with_figures.png`](file:///home/anur4gsharma/college/CP/FODS/docs/screenshots/06_paper_with_figures.png) | $780 \times 1688$ | Paper with embedded academic figure diagrams and captions centered within page margins. |
| **7** | [`07_paper_with_equations.png`](file:///home/anur4gsharma/college/CP/FODS/docs/screenshots/07_paper_with_equations.png) | $780 \times 1688$ | Display LaTeX equations ($\mathcal{H}_{eff}, P(\mathbf{s}\mid\mathbf{e})$) and inline variables rendered via KaTeX. |
| **8** | [`08_page_navigation.png`](file:///home/anur4gsharma/college/CP/FODS/docs/screenshots/08_page_navigation.png) | $780 \times 1688$ | Multi-page document navigation showing page indicator, running headers, and page footers. |
| **9** | [`09_desktop_reading.png`](file:///home/anur4gsharma/college/CP/FODS/docs/screenshots/09_desktop_reading.png) | $2560 \times 1600$ | Widescreen desktop reading experience (1280x800) with centered pages, drop shadows, and full toolbar. |

---

## 9. Final Release Artifact & Verification (Phase 9)

- **Binary Path**: [`releases/android/Resbud-release.apk`](file:///home/anur4gsharma/college/CP/FODS/releases/android/Resbud-release.apk)
- **Artifact Size**: `83,358,411 bytes` (~79.49 MiB / 83.4 MB)
- **SHA-256 Checksum**: `b86513c0e40b10610e176941243ebdac038cb0e0f33bbbbbb39b9d43e0a8beb7`
- **Application ID**: `org.resbud.mobile`
- **Version**: `0.1.0` (Build `1`)
- **SDK Targets**: Min SDK `24` (Android 7.0) | Target SDK `36` (Android 16) | Compile SDK `36`
- **Architectures**: Universal (`arm64-v8a`, `armeabi-v7a`, `x86_64`)
- **Signing Keystore**: `mobile/android/keystores/resbud-release.jks` (`resbud-key`)
- **Signing Scheme**: APK Signature Scheme v2 (`true`)
- **Live Backend**: `https://resbud-api.onrender.com` (verified HTTPS connectivity)
- **Live Emulator Status**: Tested and installed on Android 16 (API 37) emulator (`Medium_Phone_API_37.0`).

---

## 10. Known Rendering Limitations & Boundaries

1. **Local DOCX Binary Rendering**: While `docx_file_viewer` renders standard OpenXML paragraphs, tables, and images, it does not support Word drawing shapes (`w:drawing` VML) or proprietary WordArt. These are rendered via Resbud's fallback academic canvas.
2. **Formula Line Wrapping**: Very long single-line LaTeX formulas that exceed column width are horizontally contained; manual line breaking or equation splitting in the source is recommended for ultra-wide formulas.
3. **Complex Nested Tables**: Multi-level nested tables inside table cells are flattened to maintain clean academic table borders.
