# Resbud Native Word Mathematical Typesetting Architecture (OMML)

**Document Version:** 1.0  
**Status:** Approved Architectural Specification  
**Date:** 2026-11-16  
**Audience:** Principal Document Engineers, Python DOCX Engineers, Flutter Engineers, Mathematical Typesetting Specialists  

---

## 1. Executive Summary

Resbud produces academic research manuscripts in **Microsoft Word (.docx)** and **Portable Document Format (.pdf)**. Academic papers heavily feature mathematical formulation, ranging from single inline scalar variables ($x$, $\alpha$, $k_1$) to complex multi-line derivations, matrix transformations, and piece-wise loss functions (e.g., BM25 scoring, surface code Hamiltonians, reciprocal rank fusion).

Previously, Resbud's mathematical rendering relied on visual approximations:
- In mobile Flutter previews, `flutter_math_fork` rendered KaTeX widgets on a custom document canvas.
- In PDF export, display formulas were rendered as in-memory raster images (matplotlib PNG at 250–300 DPI) or wrapped in italic HTML tags, while inline formulas were merely formatted in italic prose strings (`<i>\alpha</i>`).
- In DOCX export, basic formulas were partially converted to raw `<m:oMath>` tags via `math2docx`, but display equations lacked the mandatory `<m:oMathPara>` container, alignment tokens (`&`, `&=`) crashed XML parsers, and failed expressions degraded to raw italic text runs with visible red warning banners. Furthermore, imported DOCX documents had their OMML equations discarded by the mobile viewer.

This architecture specification establishes the replacement of visual approximations with **native Office Math Markup Language (OMML)** objects:
1. **Authoritative Output**: Mathematical expressions in exported DOCX files are genuine, editable Microsoft Word equations conforming to ISO/IEC 29500-1 (WordprocessingML).
2. **Word Equation Editor Compatibility**: Users opening Resbud DOCX files in Microsoft Word can click any equation, edit symbols, alter fractions, and modify formulas using Word's built-in equation ribbon editor.
3. **Canonical Multi-Stage Pipeline**: LaTeX authoring syntax $\to$ Structured Mathematical Representation $\to$ MathML Intermediate XML $\to$ Validated Word OMML (`<m:oMath>` and `<m:oMathPara>`).
4. **Strict Inline vs. Display Preservation**: Inline variables remain within continuous paragraph prose runs without line breaks; display equations occupy dedicated centered equation paragraphs.
5. **Bidirectional OMML Viewer Parsing**: Resbud's mobile DOCX viewer natively recognizes and parses `<m:oMath>` and `<m:oMathPara>` from DOCX archives.

---

## 2. Audit of Existing Implementation (Phase 1 Findings)

### 2.1 Audit Query Responses

| # | Audit Investigation Question | Finding & Architectural Analysis |
|---|---|---|
| **1** | **How LaTeX currently enters Resbud** | LaTeX enters through two pathways: (1) LLM manuscript generation (`resbud_api.services.section_generator`) via prompt contracts instructing models to output standard LaTeX delimiters (`$...$`, `$$...$$`, `\(...\)`, `\[...\]`, `\begin{equation}`); (2) user manual edits within the mobile paper editor or JSON payload imports. |
| **2** | **Where formulas are represented as strings** | Formulas exist as raw markdown strings across `PaperSection.content` (in both FastAPI backend models and Flutter Dart models), SQLite `projects.sections` JSON column, section regeneration requests, and export request payloads. |
| **3** | **How inline and display equations are classified** | Previously determined by regex matching in `markdown_renderer.py` and `docx_document_canvas.dart`. However, a flawed heuristic (`is_big_equation`) mistakenly classified inline math containing `\sum`, `\int`, `\frac` as display math, breaking sentences into fragmented paragraph chunks. |
| **4** | **How `flutter_math_fork` is used** | Used strictly as a client-side visual widget renderer in `DocxDocumentCanvas`: `_buildMathEquationBlock` renders display formulas via `Math.tex(..., mathStyle: MathStyle.display)`, and `_renderInlineSpans` renders inline variables as `WidgetSpan(child: Math.tex(..., mathStyle: MathStyle.text))`. |
| **5** | **Storage format: images, widgets, or plain strings** | At rest in SQLite and API contracts, equations are plain strings. In Flutter memory, they are `flutter_math_fork` AST widgets. In PDF exports, block math was rasterized to temporary PNGs. In DOCX, equations were partially converted to XML nodes or fallback plain text runs. |
| **6** | **Whether DOCX exporter creates actual OMML elements** | Partially. `math2docx.add_math(p, clean_latex)` appended `<m:oMath>` into `<w:p>`. However: (a) display equations completely lacked `<m:oMathPara>`, so Word treated them as inline equations; (b) align/matrix environments failed during XML parsing and fell back to raw italic text; (c) equation numbering was unlinked. |
| **7** | **Whether DOCX viewer can parse existing OMML elements** | **No**. The mobile viewer rendered only `PaperDraftPayload` strings. When loading or previewing a `.docx` file, it had no parser for `m:oMath` or `m:oMathPara` in `word/document.xml`. |
| **8** | **Whether PDF export uses a separate math implementation** | **Yes**. `pdf_export.py` maintained a separate pipeline: inline math was formatted as `<i>` text, while block math was plotted to matplotlib figures, exported to temporary 250 DPI PNGs, and inserted as ReportLab `Image` flowables. |

---

## 3. Canonical Mathematical Document Model (Phase 2)

LaTeX serves as the authoring input syntax, but internal processing and document export operate on an explicit semantic tree:

```
                  +--------------------------+
                  |   LaTeX Source Input     |
                  +--------------------------+
                               |
                               v
            +--------------------------------------+
            | Canonical Math Document Model (AST)  |
            +--------------------------------------+
            | - InlineMathNode                     |
            | - DisplayMathNode                    |
            | - ParagraphNode (with TextRuns)      |
            +--------------------------------------+
                    /                      \
                   v                        v
        +--------------------+    +--------------------+
        | MathML Generator   |    | Vector/TeX Engine  |
        +--------------------+    +--------------------+
                   |                        |
                   v                        v
        +--------------------+    +--------------------+
        | OMML Transpiler    |    | High-DPI Vector    |
        | (m:oMath/oMathPara)|    | PDF Flowables      |
        +--------------------+    +--------------------+
                   |                        |
                   v                        v
        +--------------------+    +--------------------+
        | Word (.docx)       |    | Acrobat (.pdf)     |
        | Native Equations   |    | Vector Equations   |
        +--------------------+    +--------------------+
```

### 3.1 Data Structures

```python
@dataclass
class MathNodeBase:
    original_latex: str
    normalized_latex: str
    mathml: str | None = None
    omml: str | None = None
    rendering_status: Literal["ok", "warning", "error"] = "ok"
    validation_warnings: list[str] = field(default_factory=list)
    source_location: str | None = None

@dataclass
class InlineMathNode(MathNodeBase):
    """Inline equation embedded within running paragraph prose."""
    pass

@dataclass
class DisplayMathNode(MathNodeBase):
    """Standalone display equation occupying its own centered block."""
    equation_number: str | None = None
    equation_label: str | None = None
    environment: str | None = None  # equation, align, gather, cases, matrix
    is_multiline: bool = False

@dataclass
class TextRunNode:
    text: str
    bold: bool = False
    italic: bool = False
    code: bool = False

@dataclass
class ParagraphNode:
    """Paragraph container supporting mixed text runs and inline math nodes."""
    children: list[TextRunNode | InlineMathNode]
```

---

## 4. LaTeX $\to$ MathML $\to$ OMML Conversion Pipeline (Phases 3 & 4)

### 4.1 Dependency Selection & Licensing

To guarantee reproducibility, zero server licensing costs, and complete offline safety, all components use permissive open-source licenses:

| Component | Library / Package | Version | License | Evaluation Rationale |
|---|---|---|---|---|
| **LaTeX $\to$ MathML** | `latex2mathml` | `^3.81.1` | **MIT** | Pure Python, fast AST translation supporting extensive TeX tokens, zero external binaries. |
| **MathML $\to$ OMML** | `mathml2omml-as` | `^0.1.0` | **MIT / BSD** | Pure Python implementation of the W3C MathML to Office Math XML grammar. Safe and deterministic. |
| **DOCX Package Engine** | `python-docx` | `^1.2.0` | **MIT** | Low-level access to WordprocessingML `w:p`, `w:r`, and XML manipulation via `lxml`. |
| **XML Manipulation** | `lxml` | `^6.1.3` | **BSD** | C-accelerated XML validation, namespace binding, and DOM serialization. |

> [!IMPORTANT]
> **Zero Microsoft COM / Office Dependencies**:
> The conversion pipeline is 100% platform-independent and runs in headless Linux Docker containers without Microsoft Word installations, COM automation, or proprietary XSLTs.

### 4.2 WordprocessingML OMML Element Specification

Microsoft Word recognizes mathematical structures through elements in the XML namespace:
`xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"`

1. **Inline Math (`m:oMath`)**:
   Inserted directly into a `<w:p>` between `<w:r>` text runs:
   ```xml
   <w:p>
     <w:r><w:t xml:space="preserve">Let </w:t></w:r>
     <m:oMath>
       <m:r><m:rPr><m:sty m:val="i"/></m:rPr><m:t>x</m:t></m:r>
     </m:oMath>
     <w:r><w:t xml:space="preserve"> be a scalar.</w:t></w:r>
   </w:p>
   ```

2. **Display Math (`m:oMathPara`)**:
   Occupies its own `<w:p>`, wrapped in `<m:oMathPara>` with centered justification:
   ```xml
   <w:p>
     <w:pPr><w:jc w:val="center"/></w:pPr>
     <m:oMathPara>
       <m:oMathParaPr>
         <m:jc m:val="center"/>
       </m:oMathParaPr>
       <m:oMath>
         <m:f>
           <m:num><m:r><m:t>1</m:t></m:r></m:num>
           <m:den><m:r><m:t>2</m:t></m:r></m:den>
         </m:f>
       </m:oMath>
     </m:oMathPara>
   </w:p>
   ```

3. **OMML Construct Mapping**:
   - Fractions: `<m:f>` with `<m:num>` and `<m:den>`.
   - Subscripts / Superscripts: `<m:sSub>`, `<m:sSup>`, `<m:sSubSup>`.
   - Radicals / Roots: `<m:rad>` with optional `<m:deg>` and base `<m:e>`.
   - Delimiters / Parentheses: `<m:d>` with `<m:dPr>` (`m:begChr`, `m:endChr`).
   - N-ary Operators: `<m:nary>` with `<m:chr m:val="∑"/>`, limits in `<m:sub>` / `<m:sup>`.
   - Matrices: `<m:m>` with rows `<m:mr>` and cells `<m:e>`.

---

## 5. Inline vs. Display Classification Rules (Phase 5)

Strict syntactic precedence is enforced over heuristics:

1. **Explicit Delimiters**:
   - `\(...\)` $\implies$ **InlineMathNode**
   - `$...$` $\implies$ **InlineMathNode** (unless paragraph contains solely this expression)
   - `\[...\]` $\implies$ **DisplayMathNode**
   - `$$...$$` $\implies$ **DisplayMathNode**
   - `\begin{equation}...\end{equation}` $\implies$ **DisplayMathNode**
   - `\begin{align}...\end{align}` $\implies$ **DisplayMathNode**
   - `\begin{gather}...\end{gather}` $\implies$ **DisplayMathNode**

2. **Heuristic Protection**:
   - An inline expression containing `\frac`, `\sum`, or `\mathbb` **never** triggers an automatic paragraph split.
   - Expressions remain in their continuous sentence context.

---

## 6. DOCX Viewer OMML Parser Architecture (Phase 7)

For the Flutter mobile client (`mobile/lib/features/docx_viewer/`):
1. **OMML Ingestion**: When reading a `.docx` archive, `OmmlToLatexConverter` parses `word/document.xml`.
2. **Tag Translation**:
   - `<m:oMathPara>` $\to$ Transpiled into centered display math block.
   - `<m:oMath>` $\to$ Transpiled into inline math LaTeX string and passed to canvas renderer.
   - `<m:f>` $\to$ `\frac{num}{den}`
   - `<m:sSup>` $\to$ `base^{sup}`
   - `<m:sSub>` $\to$ `base_{sub}`
   - `<m:rad>` $\to$ `\sqrt[deg]{base}`
   - `<m:nary>` $\to$ `\sum_{sub}^{sup} {e}` or `\int_{sub}^{sup} {e}`
   - `<m:d>` $\to$ `\left( ... \right)`
   - `<m:m>` $\to$ `\begin{matrix} ... \end{matrix}`
3. **Seamless Canvas Display**: The parsed mathematical representation is rendered using Resbud's responsive document canvas.

---

## 7. PDF Vector Mathematics Fidelity (Phase 8)

1. PDF generation receives the identical parsed `InlineMathNode` and `DisplayMathNode` structures.
2. For inline math, LaTeX expressions are parsed into clean typographic Unicode math symbols and formatted with proper academic serif italic styles within ReportLab paragraphs.
3. For display math, expressions are rendered via Matplotlib/MathText vector rendering at 300 DPI with transparent bounding boxes, properly scaled to column width (3.2 in for two-column, 5.5 in for single-column).
4. Display equations are centered and separated by 6 pt vertical padding.

---

## 8. Editability & Verification Criteria (Phase 9 & 10)

1. **XML Validation**: Unzipping exported DOCX files must verify presence of `<m:oMath>` and `<m:oMathPara>` nodes in `word/document.xml`.
2. **Absence of Images**: Zero `image/png` or `image/svg+xml` parts for equations in the DOCX package.
3. **Microsoft Word Compatibility**: When opened in Microsoft Word, clicking any equation activates the native Word Equation ribbon editor.
4. **Automated Regression Suite**: 20 rigorous test cases verifying the full lifecycle from LaTeX input to OMML generation and round-trip.
