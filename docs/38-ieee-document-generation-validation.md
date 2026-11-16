# 38 — IEEE Document Generation, Mathematical Typesetting, and End-to-End Validation Report

## 1. Executive Summary

This engineering document certifies the production implementation and comprehensive end-to-end validation of Resbud's predefined **IEEE Conference Research Paper** format (`ieee_conference`), integrating the native Office Math Markup Language (OMML) equation pipeline, automated sequential equation numbering, multi-column collision-free layout, and synchronized in-text cross-referencing.

The implementation was constructed to replicate the structural, visual, and mathematical fidelity of the reference manuscript `ASEP 2 RP.docx` without relying on raster screenshots, SVG approximations, or ordinary LaTeX strings.

---

## 2. Mathematical Typesetting and Native OMML Architecture

### 2.1 The Conversion Pipeline
Resbud implements a lossless, bidirectional mathematical pipeline:
$$\text{LaTeX Math} \longrightarrow \text{W3C MathML} \longrightarrow \text{ISO/IEC 29500-1 Native OMML}$$

1. **LaTeX Sanitization (`math_omml.py` & `equation_engine.py`)**:
   - Delimiters (`$$`, `\[`, `\(`, `$`) are stripped.
   - LaTeX labels (`\label{...}`) and tags (`\tag{...}`) are extracted and decoupled from the inner mathematical syntax to prevent visual collisions.
   - Multiline and aligned environments (`aligned`, `align`, `gather`, `matrix`, `cases`, `split`, `multline`) are mapped into structured matrix environments.
   - Spacing commands (`\quad`, `\qquad`, `\,`) and bold math operators (`\boldsymbol`, `\mathbf`, `\bm`) are normalized to standard MathML constructs.
2. **MathML to OMML Transpilation**:
   - `latex2mathml` translates LaTeX trees into valid W3C MathML.
   - `mathml2omml` converts MathML nodes into Microsoft Word Office Math Markup Language (`<m:oMath>` and `<m:oMathPara>`).
3. **Word Compatibility**:
   - Microsoft Word recognizes the generated equations as genuine, native equation objects.
   - Users can click on any formula, edit symbols, alter limits, and format operators using Word's built-in Equation Editor.

---

## 3. IEEE Equation Numbering and Column Layout

### 3.1 The Equation Numbering Engine (`equation_engine.py`)
- **Automated Consecutive Numbering**: Display equations are automatically indexed across all sections in document order ($1, 2, 3, \dots, N$). The language model is never burdened with manually maintaining equation counters.
- **Stable Equation Identifiers**: Equations possess stable internal identifiers (e.g., explicit labels `eq:norm` or positional hashes `eq-sec-1`).
- **Renumbering Resilience**: If an equation is inserted, moved, or deleted, `renumber_and_synchronize_equations` re-indexes all equations and recalculates downstream identifiers.
- **In-Text Cross-Referencing**:
  - References such as `Equation (5)`, `Eq. (5)`, `(5)`, `Eq. [eq-norm]`, and `\ref{eq:norm}` are automatically resolved to their final sequential equation numbers: `Equation (1)`, `Eq. (2)`, `(1)`.

### 3.2 Collision-Free OpenXML Table Geometry
In Microsoft Word (.docx), tab-stop margins inside paragraphs can be unpredictable when an equation is wide or when viewed in different Word viewers. To guarantee rock-solid layout:
- **1-Row, 2-Cell Borderless Table (`_render_numbered_equation_to_docx`)**:
  - Table borders are set to `none` (`<w:tblBorders><w:top w:val="none"/>...</w:tblBorders>`).
  - Table alignment is centered (`<w:jc w:val="center"/>`).
  - **Cell 1 (Math Formula)**:
    - Width: 3.0 inches (IEEE two-column) / 5.8 inches (single-column).
    - Paragraph alignment: CENTER.
    - Vertical cell alignment: CENTER (`<w:vAlign w:val="center"/>`).
    - Contains native `<m:oMathPara>` and `<m:oMath>`.
  - **Cell 2 (Equation Number)**:
    - Width: 0.5 inches (IEEE two-column) / 0.7 inches (single-column).
    - Paragraph alignment: RIGHT.
    - Vertical cell alignment: CENTER (`<w:vAlign w:val="center"/>`).
    - Contains run with formatted text `(N)` in Times New Roman, 10 pt.
- **Collision Prevention**: Because the mathematical expression and the equation number occupy separate table columns, long equations wrap or scroll horizontally within their cell boundary without overlapping, clipping, or displacing the right-aligned equation number.

### 3.3 ReportLab PDF Equation Flowables
In ReportLab PDF generation:
- The LaTeX formula is rendered into high-DPI vector flowables with alpha transparency.
- When an equation number `(N)` is present, a 1-row, 2-column ReportLab `Table` is constructed with widths `[max_width - 36.0, 36.0]` and borderless styling, pinning `(N)` to the exact column margin while keeping the equation centered.

---

## 4. End-to-End Manuscript Validation

### 4.1 Reference Manuscript Structure (`ASEP 2 RP.docx`)
The test manuscript constructed in `backend/tests/test_ieee_full_manuscript_validation.py` contains:
1. **5 Authors in Responsive Grid**:
   - Row 1: 3 authors (`Aarav Sharma`, `Diya Patel`, `Rohan Verma`).
   - Row 2: 2 authors (`Ananya Iyer`, `Dr. Rajesh Kumar`).
   - 2 Institutional Affiliations across Information Technology and Computer Science departments.
2. **IEEE Front Matter**:
   - Full-width title in Times New Roman (24 pt, bold, centered).
   - Abstract in column 1 prefixed with run-in bold italic `Abstract—`.
   - Index Terms in column 1 prefixed with run-in bold italic `Index Terms—`.
3. **Numbered Headings and Subheadings**:
   - `I. INTRODUCTION`
   - `II. RELATED WORK`
   - `III. PROPOSED SYSTEM AND METHODOLOGY`
     - `A. Anatomical Landmark Acquisition`
     - `B. Spatial Coordinate Normalization`
     - `C. Dynamic Kinematic Formulation`
   - `IV. EXPERIMENTAL EVALUATION AND RESULTS`
   - `V. CONCLUSION AND FUTURE DIRECTIONS`
4. **Mathematical Expressions**:
   - Inline math: $\mathbf{p}_i = (x_i, y_i, z_i)$, $\alpha \in [0, 1]$, $w_i$, $\mathbf{q}_i$.
   - Display equation (1): Centered posture error formula with right-aligned `(1)`.
   - Display equation (2): Multiline aligned kinematic state-space equations with right-aligned `(2)`.
5. **Multimodal Figures**:
   - `FIG-001`: Methodology pipeline flowchart (column width).
   - `FIG-002`: Algorithm topology network diagram (column width).
   - `FIG-003`: Benchmark performance curve (column width).
   - `FIG-004`: Workstation monitoring dashboard (full-width span).
6. **Numerical Results Table**:
   - 4-column academic table with formatted headers, borders, and numerical benchmark comparisons.
7. **IEEE Bibliography and In-Text Citations**:
   - IEEE numbered citations (`[1]`, `[2]`, `[3]`, `[1]–[3]`, `[4]`).
   - Unnumbered `REFERENCES` heading with small-caps styling.
   - Hanging indent citations with DOI integration.

### 4.2 Cross-Template Switching Validation
The manuscript was rendered across three distinct formats with zero formatting contamination:
1. `ieee_conference` (Two-column academic, letter geometry, 0.75" top/bottom, 0.625" left/right margins, 0.25" column gutter).
2. `default` / `single_column` (Single-column academic, 1.0" standard margins).
3. `default` / `two_column_academic` (Standard two-column academic).

All equations, figures, tables, citations, and references remained intact across every format switch.

---

## 5. Verification Artifacts

The generated verification documents are saved on disk for physical inspection:
- [ieee_conference_manuscript.docx](file:///home/anur4gsharma/college/CP/FODS/docs/generated_verification/ieee_conference_manuscript.docx) (42 KB)
- [ieee_conference_manuscript.pdf](file:///home/anur4gsharma/college/CP/FODS/docs/generated_verification/ieee_conference_manuscript.pdf) (111 KB)
- [single_column_academic_manuscript.docx](file:///home/anur4gsharma/college/CP/FODS/docs/generated_verification/single_column_academic_manuscript.docx) (41 KB)
- [single_column_academic_manuscript.pdf](file:///home/anur4gsharma/college/CP/FODS/docs/generated_verification/single_column_academic_manuscript.pdf) (110 KB)
- [two_column_academic_manuscript.docx](file:///home/anur4gsharma/college/CP/FODS/docs/generated_verification/two_column_academic_manuscript.docx) (42 KB)
- [two_column_academic_manuscript.pdf](file:///home/anur4gsharma/college/CP/FODS/docs/generated_verification/two_column_academic_manuscript.pdf) (110 KB)

---

## 7. Android Release Build & Signature Verification

- **Artifact**: `mobile/build/app/outputs/flutter-apk/app-release.apk`
- **File Size**: 83.6 MB
- **Verification Tool**: Android SDK `apksigner` (v36.0.0)
- **Signature Scheme**: APK Signature Scheme v2 (`true`)
- **Number of Signers**: 1
- **SHA-256 Checksum**:
  ```
  0f525c485386450e42d354720dfdb6a41b83f440eae2d3cfbaf1b689456f72e0
  ```


- **Backend Test Suite**: 252 passed in 14.39s (`uv run pytest`).
- **Code Quality & Typing**: 100% clean across 52 source files (`uv run ruff check` & `uv run mypy src/`).
- **Mobile Flutter Tests**: 231 passed (`flutter test`).
- **Mobile Analysis**: Clean with zero errors and zero warnings (`flutter analyze`).
