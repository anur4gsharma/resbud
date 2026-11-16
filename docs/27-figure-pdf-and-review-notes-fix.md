# Resbud Release Report: Figure-Aware PDF Export, Optional Review Notes, Full Regression & Signed APK

**Document Reference**: `docs/27-figure-pdf-and-review-notes-fix.md`  
**Date**: November 16, 2026  
**Status**: Production Ready & Verified  
**Target Deliverable**: Universal Android Release APK (`releases/android/Resbud-release.apk`)  
**Production Backend**: `https://resbud-api.onrender.com`  

---

## 1. Executive Summary

This production release resolves two critical manuscript export defects in Resbud and delivers a fully tested, signed Android release APK:

1. **Figure-Aware PDF Export**: Fixed failure when research figures/images are attached to manuscripts. Previously, embedding figures caused ReportLab line-wrapping hangs, unsupported image format crashes (WebP/GIF), and transparency errors. Built an in-memory image normalization pipeline (`image_processor.py`) supporting PNG, JPG, JPEG, WebP, GIF (first-frame policy), and BMP with EXIF correction, aspect ratio preservation, and orphan-preventing `KeepTogether` flowables.
2. **Optional Editorial Review Notes & Placeholders**: Added a user-facing preference (`"Include review notes appendix in exported document"`, default: **UNCHECKED**) across both DOCX and PDF export flows. When unchecked, bracketed AI/editorial placeholders (e.g. `[Note: ...]`, `[Methodological Scope Note: ...]`) are cleanly scrubbed from prose while strictly preserving academic citations (`[1]`, `[1-3]`), mathematical intervals (`[0, 1]`), and factual research disclosures. When checked, unresolved notes are formatted into a dedicated `"Author Review Notes"` appendix at the end of the document. Mobile manuscript review warnings remain 100% accessible in the application interface.
3. **Comprehensive Regression & Release Verification**:
   - Backend test suite: **205 passed** in 10.39s (100% passing, up from 197).
   - Flutter test suite: **188 passed** in 32s (100% passing).
   - Static analysis: `ruff` 0 errors, `mypy` 0 errors across 42 source files, `flutter analyze` 0 issues.
   - Production API: Live on Render (`https://resbud-api.onrender.com/health/live` and `/health/ready` verified).
   - Universal Signed APK: Built and verified with Android `apksigner` using production keystore.

---

## 2. Root Cause Analysis: Figure-Aware PDF Export Defect

### 2.1 The Symptoms
Users reported that research images could be uploaded successfully in the mobile interface, but downloading the generated PDF failed or timed out whenever figures were attached.

### 2.2 Root Causes Identified
1. **ReportLab Base64 Paragraph Freezing**:
   In `markdown_renderer.py`, `parse_markdown_blocks` accumulated sequential non-blank lines into a single `ParagraphBlock`. When markdown contained an attached figure like `![Figure 1: Chart](data:image/png;base64,iVBOR...)` adjacent to prose without double newlines, the entire 500,000+ character base64 URI was ingested into the `ParagraphBlock`. When ReportLab attempted to wrap this monolithic character string into lines inside `ParagraphStyle`, the line-breaking algorithm hung in an infinite/exponential loop, causing request timeouts (HTTP 504) and client failures.
2. **Unsupported Document Formats in ReportLab**:
   ReportLab's native `Image` flowable does not support WebP, animated GIFs, or palette-based images, raising `UnrecognizedImageError` or crashing during PDF serialization.
3. **Alpha Channel & Transparency Artifacts**:
   Transparent PNGs and RGBA images caused rendering corruption or black background boxes when placed directly onto document pages without flattening against a white canvas.
4. **Mobile Layout Constraint Spill**:
   Adding extra export menu items to the mobile AppBar caused horizontal flex overflow on 360x640 mobile viewports, breaking responsive layout contracts.

---

## 3. Engineering Implementation

### 3.1 In-Memory Image Normalization Pipeline (`image_processor.py`)
To ensure robust, zero-retention document rendering:
- **Format Normalization**: Pillow (`PIL.Image`) decodes all incoming image streams (PNG, JPG, WebP, GIF, BMP).
- **Animated GIF Handling**: First-frame extraction policy (`image.seek(0)`) cleanly extracts static representations of animated figures.
- **Orientation Normalization**: `ImageOps.exif_transpose` automatically corrects orientation based on camera EXIF tags.
- **Transparency Flattening**: RGBA and palette-with-transparency images are composited over a solid white background canvas (`#FFFFFF`) to prevent black box artifacts in PDF and DOCX.
- **Dimension & Aspect Ratio Budgeting**: Max width/height bounded to 1600px with Lanczos resampling, preserving the exact original aspect ratio without distortion or page overflow.
- **Document-Ready Output**: Encoded to high-quality JPEG (quality=92) in-memory bytes.
- **Stateless Architecture**: No file is written to backend disk, and arbitrary URL fetching is rejected.

### 3.2 ReportLab Flowable & Layout Integration (`markdown_renderer.py`)
- **Block Parsing Separation**: `parse_markdown_blocks` strictly breaks paragraph accumulation upon encountering `![` or `<resbud-figure>` tags. Inline data URIs are isolated into discrete `FigureBlock` nodes.
- **Orphan-Preventing Layout**: Figures and their corresponding caption paragraphs are bound together using `KeepTogether([image_flowable, caption_flowable])`, guaranteeing that captions never become separated across page boundaries.
- **Two-Column and Single-Column Compatibility**: Usable width constraints are dynamically calculated based on column width (single-column vs. IEEE two-column academic layouts).

### 3.3 Optional Review Notes & Editorial Appendix (`editorial_notes.py`)
- **Scrubbing Pipeline**: `clean_editorial_notes_from_text` extracts unresolved review/editorial bracketed notes matching patterns like `[Note: ...]`, `[Methodological Scope Note: ...]`, `[Editor's Note: ...]`, `[Clarification: ...]`, and `[Warning: ...]`.
- **False-Positive Prevention**:
  - Academic citations (`[1]`, `[1-3]`, `[1, 2, 4]`, `[Smith et al., 2020]`) are preserved intact.
  - Mathematical range intervals (`[0, 1]`, `[-1, 1]`) are preserved.
  - Factual prose disclosures (e.g., *"The experimental evaluation has not yet been conducted."*) remain in place as valid scientific text.
- **Dedicated Appendix**: When `"Include review notes appendix in exported document"` is checked (`include_review_notes_appendix=true`), notes are aggregated and appended under the heading `## Author Review Notes` at the end of the manuscript. When unchecked (default), notes are cleanly excised.
- **Research Integrity Uncompromised**: The internal `review_warnings` list on `PaperDraft` and the mobile application's Manuscript Readiness sheet remain completely intact regardless of the export checkbox.

---

## 4. Full Regression Test Results

### 4.1 Backend Test Results (pytest)
- **Total Tests**: **205 passed**, 0 failed, 1 warning (deprecation).
- **Execution Time**: 10.39s.
- **Key Suites**:
  - `tests/test_pdf_export_api.py`: PDF binary response, safe headers, WebP/GIF/PNG/BMP figure embedding, single and two-column layouts, review notes appendix enabled/disabled.
  - `tests/test_docx_export_api.py`: Re-openable DOCX, XML entity validation, figure embedding across formats, review notes appendix.
  - `tests/test_critical_manuscript_quality_regression.py`: Heading marker leaks, unicode author preservation, multiline reference extraction, hierarchical section numbering.
  - `tests/test_security_and_auth.py`: JWT validation, rate limiting, request-size boundaries (4 MiB).

### 4.2 Flutter Test Results
- **Total Tests**: **188 passed**, 0 failed.
- **Execution Time**: 32s.
- **Key Suites**:
  - `test/accessibility_and_responsiveness_test.dart`: Zero overflow across phone (360x640), tablet (768x1024), and desktop (1440x900). Accessible touch targets and dark theme contrast.
  - `test/end_to_end_integration_test.dart`: Full vertical user journey with versioning, section regeneration, error resilience, and export.
  - `test/docx_viewer_and_version_management_test.dart`: Native paginated DOCX viewer canvas, version comparison, restoring prior versions.
  - `test/source_document_importer_test.dart`: Figure extraction, PNG/JPEG import, corrupted image rejection.
  - `test/upload_first_and_clarification_test.dart`: Upload-first workflow, figure extraction, and draft generation.

### 4.3 Static Code Quality
- `ruff check src/ tests/`: 0 errors.
- `mypy src/`: 0 errors across 42 files.
- `flutter analyze`: 0 issues found.

---

## 5. Android Signed Release APK

- **Artifact Path**: `releases/android/Resbud-release.apk`
- **Backup Path**: `releases/android/Resbud-release.apk.bak`
- **Application ID**: `org.resbud.mobile`
- **File Size**: 64.7 MB (64,743,334 bytes)
- **SHA-256 Checksum**: `8c5367fffbd44525becf9c7286391a45145a35789c973f1d1bfdf1092e00f257`
- **Signing Scheme**: APK Signature Scheme v2 (`apksigner verify --verbose` verified)
- **Signer #1 DN**: `CN=Resbud Production, OU=Mobile Release, O=Resbud, C=US`
- **Signer #1 Certificate SHA-256**: `36245f00aee995e828571a6f63bea5627e3cb3846adf5a4739a3cd6a8baa70f8`
- **Target SDK**: Android 34 / Java 17 / Min SDK 21
