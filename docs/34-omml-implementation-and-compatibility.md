# Resbud — OMML Implementation & Office Math Compatibility Specification

**Document Version:** 1.0.0  
**Status:** Approved & Implemented  
**Date:** 2026-11-16  
**Branch:** `fix/native-word-equations`  
**Reference Standards:** ISO/IEC 29500-1 (Office Open XML — WordprocessingML & Office Math Markup Language)  

---

## 1. Executive Summary

Resbud previously employed an approximation approach for exported DOCX mathematics: mathematical expressions were either emitted as plain LaTeX strings or visually styled text runs. While the Flutter mobile client rendered equations visually using `flutter_math_fork`, exported Word documents did not contain genuine, editable Microsoft Word equations. When researchers opened manuscripts in Microsoft Word, equations were not recognized as native equation objects, preventing formula modification, symbol insertion, or style adaptation.

This implementation replaces that legacy mechanism with a robust, production-grade **Office Math Markup Language (OMML)** pipeline:
1. **Mathematical Representation:** Mathematical formulas are authored and stored as LaTeX syntax.
2. **Intermediate Representation:** A canonical mathematical Abstract Syntax Tree (AST) parses and classifies equations strictly by author intent (`$...$` / `\(...\)` for inline prose, `$$...$$` / `\[...\]` for display blocks).
3. **Conversion Pipeline:** LaTeX $\to$ MathML (via `latex2mathml`) $\to$ ISO/IEC 29500-1 OMML (via `mathml2omml-as` and custom post-processing).
4. **DOCX Embedding:** Real `<m:oMath>` nodes are attached into paragraph prose runs (`<w:p>`), while `<m:oMathPara>` display containers are centered in dedicated paragraphs. Zero raster images (PNG, JPEG), zero SVG files, and zero raw LaTeX strings are emitted into `word/document.xml`.
5. **Mobile DOCX Viewer Integration:** Resbud's mobile DOCX canvas integrates an in-memory OMML DOM parser (`omml_parser.dart`) that decompresses the `.docx` archive and translates native `<m:oMath>` and `<m:oMathPara>` structures into Flutter Math representations without losing typesetting fidelity.

---

## 2. Complete Architecture Pipeline

```
  +--------------------------------------------------------------+
  |              Author / LLM Generation Input                   |
  |  (Markdown prose containing LaTeX inline $...$ & display $$) |
  +------------------------------+-------------------------------+
                                 |
                                 v
  +--------------------------------------------------------------+
  |                 Markdown AST Parsing Layer                   |
  |   - Explicit delimiter precedence (inline vs display)        |
  |   - Prose segmentation into TextRunNode & MathNode           |
  |   - Verbatim code fence isolation (```latex preservation)    |
  +------------------------------+-------------------------------+
                                 |
                                 v
  +--------------------------------------------------------------+
  |                  LaTeX Sanitization Layer                    |
  |   - Multi-line align/gather environments -> matrix arrays    |
  |   - Operator normalization (\operatorname -> \text)          |
  |   - Ampersand entity escaping to prevent XML SAX failure     |
  +------------------------------+-------------------------------+
                                 |
                                 v
  +--------------------------------------------------------------+
  |                   MathML Conversion Layer                    |
  |         latex2mathml.converter.convert(sanitized_latex)      |
  +------------------------------+-------------------------------+
                                 |
                                 v
  +--------------------------------------------------------------+
  |                    OMML Conversion Layer                     |
  |         mathml2omml.convert(mathml_xml_string)               |
  |   - Strips extraneous XML declarations & standalone wrappers |
  |   - Post-processes root tag (<m:oMath> or <m:oMathPara>)     |
  |   - Injects center paragraph justification for display math  |
  +------------------------------+-------------------------------+
                                 |
                                 v
  +--------------------------------------------------------------+
  |                WordprocessingML DOM Injection                |
  |  - Inline:  <w:p> ... <w:r>text</w:r> <m:oMath>...</m:oMath> |
  |  - Display: <w:p><m:oMathPara><m:jc val="center"/>...</m:... |
  +--------------------------------------------------------------+
```

---

## 3. Canonical Mathematical AST Specification

Located in `backend/src/resbud_api/services/math_omml.py`:

```python
class MathNodeBase(ABC):
    latex: str
    mathml: str | None = None
    omml: str | None = None
    equation_number: str | None = None
    equation_label: str | None = None
    rendering_status: Literal["ok", "warning", "error"] = "ok"
    validation_warning: str | None = None

class InlineMathNode(MathNodeBase):
    """Inline equation embedded directly within sentence prose runs."""
    display_type: Literal["inline"] = "inline"

class DisplayMathNode(MathNodeBase):
    """Display equation occupying a dedicated centered block paragraph."""
    display_type: Literal["display"] = "display"

class TextRunNode:
    """Prose segment within a paragraph."""
    content: str
    bold: bool = False
    italic: bool = False
    code: bool = False

class ParagraphNode:
    """Mixed paragraph holding ordered prose runs and inline equations."""
    runs: list[TextRunNode | InlineMathNode]
    style: str = "Normal"
```

### Delimiter Precedence Rules

Resbud strictly differentiates between inline and display equations according to explicit syntax rules:

1. **Inline Math (`InlineMathNode`):** Delimited by `$...$` or `\(...\)`.
   - Never split prose into separate paragraphs.
   - Remains adjacent to preceding and succeeding punctuation (e.g. `query term variable $x$ and parameter $\alpha \in [0, 1]$.`).
   - Single variables (`$x$`), subscripted variables (`$x_i$`), Greek symbols (`$\alpha$`), and even fractions (`$\frac{a}{b}$`) stay inline when delimited by single `$`.
2. **Display Math (`DisplayMathNode`):** Delimited by `$$...$$` or `\[...\]`.
   - Occupies its own standalone Word paragraph.
   - Enclosed within `<m:oMathPara>` with `<m:jc m:val="center"/>`.
   - Supports multi-line alignments, integrals, and matrices.
3. **Verbatim Code Fence Isolation:**
   - Any LaTeX markup occurring inside ` ```latex ... ``` ` or inline backticks `` `\newcommand{...}` `` is preserved as raw monospace text runs. The OMML tokenizer explicitly ignores fenced blocks.

---

## 4. OMML XML Element Mapping & WordprocessingML Structure

The generated DOCX `word/document.xml` adheres strictly to the ISO/IEC 29500-1 schema namespace:
`xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"`

### Structure Comparison

| Mathematical Construct | LaTeX Input | OMML Structure | WordprocessingML XML |
|---|---|---|---|
| **Inline Variable** | `$x$` | `<m:oMath><m:r><m:t>x</m:t></m:r></m:oMath>` | Inline inside `<w:p>` run stream |
| **Greek Letter** | `$\alpha$` | `<m:oMath><m:r><m:t>α</m:t></m:r></m:oMath>` | Inline inside `<w:p>` run stream |
| **Subscript** | `$x_i$` | `<m:sSub><m:e><m:r><m:t>x</m:t></m:r></m:e><m:sub><m:r><m:t>i</m:t></m:r></m:sub></m:sSub>` | Word Subscript Object |
| **Superscript** | `$x^2$` | `<m:sSup><m:e><m:r><m:t>x</m:t></m:r></m:e><m:sup><m:r><m:t>2</m:t></m:r></m:sup></m:sSup>` | Word Superscript Object |
| **Fraction** | `\frac{a}{b}` | `<m:f><m:num><m:r><m:t>a</m:t></m:r></m:num><m:den><m:r><m:t>b</m:t></m:r></m:den></m:f>` | Word Fraction Object |
| **Radical / Sqrt** | `\sqrt{x^2+y^2}` | `<m:rad><m:radPr><m:degHide m:val="on"/></m:radPr><m:e>...</m:e></m:rad>` | Word Radical Object |
| **N-ary Summation** | `\sum_{i=1}^{n}` | `<m:nary><m:naryPr><m:chr m:val="∑"/></m:naryPr><m:sub>...</m:sub><m:sup>...</m:sup><m:e>...</m:e></m:nary>` | Word N-ary Summation Object |
| **N-ary Integral** | `\int_{0}^{\infty}` | `<m:nary><m:naryPr><m:chr m:val="∫"/></m:naryPr><m:sub>...</m:sub><m:sup>...</m:sup><m:e>...</m:e></m:nary>` | Word Integral Object |
| **Delimiters / Parens** | `\begin{pmatrix}...` | `<m:d><m:dPr><m:begChr m:val="("/><m:endChr m:val=")"/></m:dPr><m:e>...</m:e></m:d>` | Word Delimiter Object |
| **Matrix** | `\begin{pmatrix}1&0\\0&1\end{pmatrix}` | `<m:m><m:mr><m:e>...</m:e></m:mr></m:m>` | Word Matrix Object |
| **Piecewise Cases** | `\begin{cases}x&\text{if }...` | `<m:d><m:dPr><m:begChr m:val="{"/><m:endChr m:val=""/></m:dPr><m:e><m:eqArr>...</m:eqArr></m:e></m:d>` | Word Equation Array |

---

## 5. Verification & Test Suite Matrix

The comprehensive test suite in `backend/tests/test_native_omml_equations.py` validates all 20 canonical mathematical requirements:

| # | Regression Construct | Test Type | Status | Validation Result |
|---|---|---|---|---|
| 1 | Single variable `$x$` inline | AST + DOCX XML | **PASSED** | Stays in continuous prose, `<m:oMath>` run |
| 2 | Greek letter `$\alpha$` inline | AST + DOCX XML | **PASSED** | Emits `α` in `<m:oMath>` run |
| 3 | Subscript `$x_i$` | AST + DOCX XML | **PASSED** | Emits `<m:sSub>` |
| 4 | Superscript `$x^2$` | AST + DOCX XML | **PASSED** | Emits `<m:sSup>` |
| 5 | Fraction inline `$\frac{a}{b}$` | AST + DOCX XML | **PASSED** | Emits `<m:f>` without line break |
| 6 | Inline probability notation `$P(\mathbf{s} \mid \mathbf{e})$` | AST + DOCX XML | **PASSED** | Emits upright font / delimiters |
| 7 | Display fraction `$$\frac{a+b}{c+d}$$` | AST + DOCX XML | **PASSED** | Emits centered `<m:oMathPara>` |
| 8 | Complex BM25 scoring function | AST + DOCX XML | **PASSED** | Nested `<m:f>`, `<m:nary>`, `<m:d>` |
| 9 | Cosine similarity equation | AST + DOCX XML | **PASSED** | Bold vectors, norms, center paragraph |
| 10 | Reciprocal Rank Fusion formula | AST + DOCX XML | **PASSED** | Emits `<m:nary>` and fractions |
| 11 | Summation with upper/lower limits | AST + DOCX XML | **PASSED** | Emits `<m:sub>`, `<m:sup>`, `<m:e>` |
| 12 | Integral over infinite domain | AST + DOCX XML | **PASSED** | Emits `<m:nary>` with limits $0$ to $\infty$ |
| 13 | Matrix $\begin{pmatrix} 1 & 0 \\ 0 & 1 \end{pmatrix}$ | AST + DOCX XML | **PASSED** | Emits `<m:m>` with 2 rows and columns |
| 14 | Piecewise function (`cases`) | AST + DOCX XML | **PASSED** | Transformed to open brace delimiter + matrix |
| 15 | Multi-line aligned equation (`align`) | AST + DOCX XML | **PASSED** | Transformed to matrix without raw `&` |
| 16 | Mixed paragraph with multiple formulas | AST + DOCX XML | **PASSED** | 4+ `<m:oMath>` in 1 paragraph, zero `<m:oMathPara>` |
| 17 | Two-column academic layout | DOCX Layout XML | **PASSED** | Multi-column section contains OMML nodes |
| 18 | Formulas adjacent to tables and figures | DOCX Section XML | **PASSED** | Table cells and captions preserve math |
| 19 | Literal LaTeX code block | Markdown AST | **PASSED** | Monospace Consolas run, zero OMML parsing |
| 20 | Malformed / invalid LaTeX fallback | Exception Handler | **PASSED** | Resilient italic OMML fallback, no crash |

---

## 6. Mobile DOCX Viewer Integration

The Flutter mobile application (`mobile/lib/features/docx_viewer/omml_parser.dart`) provides native OMML parsing directly from document archives:

1. **In-Memory Unzipping:** The viewer uses `archive: ^4.0.9` to read `word/document.xml` from `.docx` bytes in memory without touching disk storage.
2. **Recursive OMML DOM Parsing:**
   - Detects `<m:oMath>` and `<m:oMathPara>`.
   - Recursively converts `<m:f>`, `<m:sSup>`, `<m:sSub>`, `<m:sSubSup>`, `<m:rad>`, `<m:nary>`, `<m:d>`, and `<m:m>` into clean LaTeX strings.
3. **Canvas Rendering:** Passes the parsed LaTeX expressions directly to `flutter_math_fork` via `DocxDocumentCanvas`, providing responsive vector formula typesetting on mobile viewports.
4. **Fallback Handling:** If a file is an older plaintext or markdown file rather than an OOXML zip package, the viewer gracefully falls back to inline Markdown regex tokenization.

---

## 7. Office Math Compatibility Notes

### Microsoft Word (Windows & macOS)
- Equations created via `<m:oMath>` and `<m:oMathPara>` are detected as **first-class native equation objects**.
- When clicked in Microsoft Word, Word activates the **Equation Tools / Design** ribbon.
- The equation can be edited using the built-in Math keyboard, converted to Linear (UnicodeMath / LaTeX) format, or saved to the Equation Gallery.
- Font styling automatically matches Word's default math typography (*Cambria Math*), ensuring visual consistency with the rest of the manuscript.

### LibreOffice Writer & Google Docs
- LibreOffice Writer (v7.0+) converts OOXML OMML elements into native *StarMath* formulas upon opening.
- Google Docs automatically converts OMML elements into Google Docs equation objects when imported.

### Automated Testing & Headless Verification
- In headless Linux environments (CI/CD servers), interactive desktop Microsoft Word is not installed.
- Structural verification is achieved by unzipping the `.docx` archive and validating that `word/document.xml` conforms strictly to the Microsoft OMML XML namespace and schema definitions.
- Automated tests verify the complete absence of raster screenshot images (`.png`, `.jpg`) or `<w:drawing>` equation approximations.

---

## 8. Sample Output Documents

The verification script generates canonical manuscripts in `docs/generated_verification/`:
- `docs/generated_verification/math_omml_manuscript.docx` (Single-column layout with all 20 test cases).
- `docs/generated_verification/math_omml_manuscript.pdf` (High-quality vector PDF export with Mathtext engine).
- `docs/generated_verification/math_omml_manuscript_two_column.docx` (Two-column IEEE/ACM academic layout).
- `docs/generated_verification/math_omml_manuscript_two_column.pdf` (Two-column PDF export).

---

## 9. Known Limitations & Future Roadmap

1. **Equation Numbering:** Currently, display equations are centered. Future iterations can add tab-aligned right-justified equation numbers `(1)` within WordprocessingML table or tab-stop wrappers.
2. **Cross-Referencing:** Referencing equations by `\label{eq:bm25}` and `\ref{eq:bm25}` can be enhanced to generate Word Bookmarks (`<w:bookmarkStart>`) and Field Codes (`<w:fldSimple w:instr="REF eq:bm25">`).
3. **Specialized Matrix Accents:** Extremely rare TeX macro packages (e.g. `xy-pic`, commutative diagrams) are not supported by MathML and fall back to resilient text representation.
