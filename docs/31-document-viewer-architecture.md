# Resbud Document Viewer Architecture & Engine Evaluation

**Document Version:** 1.0  
**Status:** Approved  
**Date:** 2026-11-16  
**Audience:** Principal Flutter Engineers, Document Rendering Specialists, UX Architects

---

## 1. Executive Summary

Resbud produces academic research manuscripts formatted according to IEEE and general scientific standards in two primary document formats: **DOCX (Microsoft Word)** and **PDF (Portable Document Format)**.

Prior to this architecture update, document previewing on mobile suffered from:
1. **Fallback Degradation**: The PDF viewer on mobile and desktop did not render real PDF binaries, falling back to a simplistic widget canvas.
2. **Defective Layout & Spacing**: Two-column academic papers partitioned sections naively, leaving the right column on page 1 completely empty when only the introduction was present.
3. **Raw Markdown Leakage**: Subheadings in section markdown (e.g. `### Context & Motivation`) were unparsed and displayed literally on the reading canvas.
4. **Poor Mobile Readability**: Defaulting to fixed 40% zoom rendered academic text microscopic on smartphone viewports (360–412 pt width), requiring cumbersome manual pinch gestures.
5. **Cluttered Controls**: Multiple stacked toolbars consumed valuable vertical screen space, reducing the active reading area.

This document establishes the architecture for Resbud's production document viewer suite:
- **PDF Engine**: **`pdfrx`** (PDFium-powered, hardware-accelerated, cross-platform with WASM web support).
- **DOCX Engine**: **`docx_file_viewer`** (OpenXML native widget tree) paired with Resbud's **Enhanced Academic Document Canvas** (supporting live in-memory LaTeX equations, citations, and dynamic two-column column-balancing).
- **Unified Mobile Reading Interface**: Mobile-first compact chrome, fit-to-width auto-scaling, one-touch fullscreen, and responsive navigation.

---

## 2. PDF Rendering Engine Evaluation

### 2.1 Candidate Comparison Matrix

| Evaluation Criteria | `pdfrx` (Selected) | `pdfx` | `syncfusion_flutter_pdfviewer` | `flutter_pdfview` |
|---|---|---|---|---|
| **Underlying Engine** | Google PDFium (Native C++ / WebAssembly) | PDFium (Android/Win), PDFKit (Apple), PDF.js (Web) | Syncfusion Custom Native Renderer | Android `PdfView` / iOS `WKWebView` |
| **Open Source License** | **MIT** (Permissive, commercial-friendly) | BSD-3-Clause | Commercial / Community (Strict revenue limits <$1M) | Apache 2.0 |
| **Active Maintenance** | Very High (v2.12+, regular releases) | Moderate (Infrequent updates) | High (Proprietary vendor) | Low (Stale repository) |
| **Platform Parity** | Android, iOS, Web, macOS, Linux, Windows | Android, iOS, Web, macOS, Linux, Windows | Android, iOS, Web, macOS, Windows | Android, iOS only |
| **Vector Sharpness** | Native PDFium rasterization at device DPI | Mixed by platform | Native vector | Native webview raster |
| **Fit-to-Width Mobile** | Native delegate (`PdfViewerSizeDelegate`) | Manual matrix calculation | Built-in | Limited |
| **Pinch & Double-Tap Zoom** | Built-in physics & gesture delegate | Built-in interactive viewer | Built-in | OS default |
| **Text Selection & Search** | Full text extraction & `PdfTextSearcher` | Basic text selection | Search & highlight | No search API |
| **Page Layout Modes** | Vertical continuous, horizontal, grid | Page-by-page or continuous | Continuous or single | Page-by-page |
| **Memory Management** | `PdfImageCacheBudget` (Tiled lazy rendering) | Basic page cache | Good memory cache | System webview memory |
| **Offline Functionality** | **100% Offline** (Zero network dependencies)| 100% Offline | 100% Offline | 100% Offline |

### 2.2 Selected PDF Engine: `pdfrx`

`pdfrx` was selected because:
1. **Identical Rendering Fidelity Across Platforms**: By standardizing on Google's PDFium across Android, iOS, Desktop, and Web (compiled to WebAssembly), PDF rendering is byte-accurate and visually identical across every platform.
2. **Device Pixel Density Awareness**: It automatically renders pages scaled to the target device's physical pixel ratio (e.g., 2.75x or 3.0x on modern AMOLED displays), eliminating pixelation and blur.
3. **Memory Safety**: Uses tiled sub-page rendering and `PdfImageCacheBudget` to discard off-screen high-resolution page buffers, allowing smooth reading of multi-page documents on constrained Android devices without Out-Of-Memory (OOM) crashes.
4. **Permissive License**: MIT licensing allows unrestricted integration into open-source and commercial distributions without licensing fees or compliance audits.

---

## 3. DOCX Rendering Engine Evaluation

### 3.1 Candidate Comparison Matrix

| Evaluation Criteria | `docx_file_viewer` (Selected) | `docx_viewer_plus` | Collabora Online (LibreOffice) | Enhanced Resbud Canvas (Selected Hybrid) |
|---|---|---|---|---|
| **Architecture** | Pure Flutter OpenXML parser & widgets | Flutter rich-text editor hybrid | Cloud/Server WOPI iframe container | Paginated Flutter academic canvas |
| **License** | **MIT** | MIT | Affero GPL v3 (Copyleft) | Proprietary / Resbud MIT |
| **Offline Support** | **100% Offline** | 100% Offline | **Requires running cloud server** | **100% Offline** |
| **Latency** | Instant (local widget build) | Instant | 800ms–3s network round-trip | Instant (zero network, live draft) |
| **Server Overhead** | Zero | Zero | High (200MB+ RAM per document session) | Zero |
| **OpenXML Elements** | Paragraphs, tables, lists, images, borders | Text, basic tables, editor styling | Full Word fidelity | Headings, KaTeX equations, tables, figures, citations |
| **LaTeX Equations** | Basic text fallback | Basic text fallback | MathML converter | **Native KaTeX (`flutter_math_fork`)** |
| **Two-Column Academic** | Continuous width | Editor width | Full two-column sections | **True balanced column layout** |

### 3.2 Architectural Evaluation of Collabora Online

Collabora Online (built on LibreOffice Core) provides near-100% rendering fidelity with Microsoft Office. However, for a mobile-first, local-first application like Resbud, it introduces unacceptable trade-offs:
- **Destroys Offline Capability**: Users reading papers in transit, field work, or airplanes would have non-functional viewers.
- **Resource Prohibitive**: Hosting a containerized LibreOffice instance requires dedicated server infrastructure ($50–$200/month on Render/AWS) and consumes 150–300 MiB RAM per active document.
- **Latency**: Converting and streaming document viewports over mobile networks introduces jarring latency compared to 60fps local Flutter rendering.

### 3.3 Selected DOCX Strategy: Dual-Engine Architecture

To deliver both Word OpenXML file viewing and real-time academic draft previewing, Resbud implements a **Dual-Engine Architecture**:
1. **OpenXML File Viewer (`docx_file_viewer`)**:
   - Used when reading exported or uploaded `.docx` binary files.
   - Parses the document zip structure (`word/document.xml`, `word/styles.xml`, `word/media/`).
   - Renders tables, lists, images, and styling as native Flutter widgets with search, zoom, and text selection.
2. **Enhanced Resbud Academic Document Canvas**:
   - Used for immediate, zero-latency in-memory preview of generated research drafts before and after export.
   - Native support for LaTeX mathematical expressions (`flutter_math_fork`).
   - Proper markdown subheading parsing (eliminating raw `###`).
   - Symmetrically balanced two-column academic flow.
   - Precise 1-inch margins, Times New Roman typography, and publication-standard running headers/footers.

---

## 4. Shared Mobile UX Architecture

### 4.1 Layout Hierarchy

```
+-------------------------------------------------------------+
| Top Bar: Back | Paper Title | Saved Badge | Mode Switcher  |
| [ Read (DOCX) ]  [ View as PDF ]  [ Edit & Outline ]        |
+-------------------------------------------------------------+
| Compact Format Toolbar (Height: 40pt)                       |
| [Layout: 2-Col/1-Col] [Page < 1 / 4 >] [Fit] [- 100% +] [...] |
+-------------------------------------------------------------+
|                                                             |
|                                                             |
|                DOCUMENT VIEWPORT (Maximum Area)             |
|          - Fit-to-Width by default on mobile screens        |
|          - Smooth pinch-to-zoom (0.4x to 3.0x)              |
|          - Native double-tap to zoom                        |
|          - Zero horizontal clipping                         |
|                                                             |
|                                                             |
+-------------------------------------------------------------+
```

### 4.2 Compact Control Philosophy
- **Primary Actions (Always Visible)**:
  - Page navigation (`< Page X of Y >`)
  - Fit-to-width toggle
  - Zoom controls / Zoom indicator
  - Fullscreen toggle
- **Secondary Actions (Consolidated into Overflow `...` Menu)**:
  - Download DOCX
  - Download PDF
  - Document Search
  - Print Document
  - Layout Switcher (Two-Column Academic vs Standard Single-Column)
  - Document Info / Metadata

### 4.3 Immersive Full-Screen Mode
Tapping the Fullscreen icon collapses the application header and secondary navigation, dedicating 100% of the screen real-estate to document reading. A floating translucent exit button in the top-right corner allows immediate return to standard mode.

---

## 5. Architectural Correctness for Document Defects

| Defect Identified | Root Cause | Architectural Solution |
|---|---|---|
| **Raw `###` Headings** | Viewer canvas treated markdown hashes as prose text | Parser in `DocxDocumentCanvas` recognizes `#`, `##`, `###`, `####` and maps them to academic H1/H2/H3 widgets with clean serif typography. |
| **Microscopic Default Zoom** | Fixed 40% initial zoom on 360–412pt screens | Auto-fit calculation: `zoom = (screenWidth - 24) / 794.0` ensures the document fills the viewport width with legible 14–16pt equivalent body text. |
| **Empty Right Column** | Naive partitioning split section count in half; page 1 with 1 section gave `[sec1]` left and `[]` right | Balanced column algorithm splits section content across two balanced vertical columns so both columns are utilized symmetrically. |
| **Equation Breakage** | Paragraph splitter did not handle inline `$x$` vs block `$$...$$` | Regex tokenizer preserves inline LaTeX variables inside sentences and isolates block equations into centered display blocks with equation numbering. |
| **Table Overflow** | Tables lacked constrained horizontal scrolling | Tables wrapped in `SingleChildScrollView(scrollDirection: Axis.horizontal)` with constrained column widths and clean borders. |

---

## 6. Implementation Plan & Milestones

1. **Engine Integration**:
   - Add `pdfrx: ^2.12.1` and `docx_file_viewer: ^1.0.3` to `mobile/pubspec.yaml`.
2. **PDF Viewer Overhaul**:
   - Implement `PdfViewer` with `pdfrx.PdfViewer.data`.
   - Implement compact mobile toolbar, fit-to-width default, pinch/double-tap zoom, search, and page navigation.
   - Maintain test-mode fallback for headless widget testing.
3. **DOCX Viewer Overhaul**:
   - Implement `DocxView` integration for binary `.docx` files.
   - Overhaul `DocxDocumentCanvas` with markdown heading parsing, balanced two-column layout, and KaTeX math.
4. **Shared Interface & Regression Testing**:
   - Wire unified top navigation (`Read (DOCX)`, `View as PDF`, `Edit & Outline`).
   - Run complete test suite and build signed Android release APK.
