# Architectural Specification: Mandatory Block-Level Mathematical Rendering & Equation Pipeline

## 1. Executive Summary & Mandatory Design Rule

This document specifies the end-to-end mathematical rendering architecture for Resbud manuscripts across Markdown AST parsing, DOCX native equation compilation, PDF generation, and Flutter in-app reading/editing interfaces.

**Mandatory Academic Formatting Rule:**
> Every mathematical expression must be rendered as a standalone display equation, occupying its own separate paragraph and line. Inline mathematical rendering must not be used anywhere in the final manuscript.
> 
> Surrounding prose originally containing embedded equations is automatically split into preceding and subsequent paragraphs with preserved grammar, punctuation, and academic meaning.

---

## 2. Document AST & Block-Level Math Representation

To eliminate text-equation overlaps and ensure consistent typographics across Word, PDF, and Flutter, mathematical content is isolated into explicit block-level AST nodes:

```python
@dataclass
class EquationBlockNode:
    latex: str  # Original LaTeX source (without outer delimiters)
    display_type: Literal["display", "extracted_inline", "environment"] = "display"
    equation_id: str | None = None
    normalized_latex: str | None = None
    rendering_status: Literal["ok", "warning", "error"] = "ok"
    validation_error: str | None = None


# Backward-compatible alias
MathBlock = EquationBlockNode
```

### Critical AST Properties:
1. **Paragraph Separation:** `ParagraphBlock` contains only pure prose spans (`text`, `bold`, `italic`, `code`, `link`). No `kind="math"` spans are embedded inside paragraphs.
2. **Dedicated Blocks:** All equations—whether originally written in display delimiters (`$$`, `\[`), environments (`\begin{equation}`, `\begin{pmatrix}`), or embedded inline (`\(...\)`, `$x+y$`)—are lifted into standalone `EquationBlockNode` elements.
3. **Immutability of Source:** Original LaTeX is strictly preserved in `latex`. Editing a section in Flutter preserves the exact source for future re-renders.

---

## 3. Paragraph Splitting & Prose Boundary Formatting

When a paragraph contains one or more mathematical expressions, `extract_equation_blocks_from_paragraph` parses and partitions the text into alternating prose and equation blocks:

### Grammar Transformation Rules:
1. **Preceding Prose Cleaning:**
   - Trailing commas or semicolons are stripped.
   - Introduction clauses ending with verbs/prepositions (e.g., `calculated as`, `defined as`, `expressed as`) are normalized to `calculated as follows:`.
   - Intro phrases ending in `is`, `given by`, `satisfies`, or `minimizes the loss` are formatted with a trailing colon `:`.
   - Sentences lacking terminal punctuation receive a colon `:` to introduce the block equation.
2. **Standalone Equation Extraction:**
   - Outer delimiters (`$$`, `\[`, `\(`, `$`) are stripped while preserving complete LaTeX commands, matrices, and symbols.
   - Verified against `MathTextParser` and `latex2mathml` converters.
3. **Subsequent Prose Cleaning:**
   - Leading commas and semicolons are stripped.
   - Transitional words such as `where` are normalized to `Here, ` (e.g., `where q is query` $\to$ `Here, q represents query`).
   - `in which` and `with` clauses are capitalized as independent sentence starters.
   - Leading lowercase letters are capitalized to ensure valid grammatical sentences.

### Real Research Prose Example:
**Input (from `format_specifier_papers/Training Foundation Models with a Single Algorithm.pdf`):**
> "Maximum likelihood estimation minimizes the loss \(L(\theta;\rho\circ\mu) := -\mathbb{E}_{x\sim\rho} \mathbb{E}_{y\sim\mu(\cdot|x)}[\log\pi_\theta(y|x)]\), where x is the prompt and y is completion."

**Transformed Document Blocks:**
1. **ParagraphBlock:** "Maximum likelihood estimation minimizes the loss:"
2. **EquationBlockNode:** `L(\theta;\rho\circ\mu) := -\mathbb{E}_{x\sim\rho} \mathbb{E}_{y\sim\mu(\cdot|x)}[\log\pi_\theta(y|x)]`
3. **ParagraphBlock:** "Here, x is the prompt and y is completion."

---

## 4. DOCX Export Requirements (Native Word OMML)

1. **Dedicated Word Paragraphs:** Every equation occupies its own paragraph, horizontally centered (`WD_ALIGN_PARAGRAPH.CENTER`) with `Pt(8)` vertical margins before and after.
2. **Native OMML:** Converted via `latex2mathml` and `mathml2omml` into native `<m:oMath>` OpenXML structures.
3. **Warning Semantics:** If an expression contains invalid syntax or unsupported macros (e.g. `\unsupportedmacro{x}`), the original LaTeX is displayed centered with an explicit red warning run: `[Warning: Unsupported mathematical syntax]`.

---

## 5. PDF Export Requirements (ReportLab Flowables)

1. **Standalone Centered Flowables:** Every equation is rasterized at **300 DPI** via `matplotlib` mathtext and placed in a centered `RLImage` flowable bounded by `Spacer(1, 6)` top and bottom.
2. **Proportional Scaling:** Long equations approaching the physical page width (460 pt printable width) are scaled proportionally to prevent margin clipping.
3. **Matrix Support:** Matrix environments (`pmatrix`, `bmatrix`, `matrix`) are rendered as centered, bordered ReportLab `Table` flowables.
4. **Warning Semantics:** Erroneous or unsupported formulas produce a visible warning paragraph (`styles["MathBlock"]`) preserving source and highlighting syntax issues.

---

## 6. Flutter Reading Canvas & Editor Experience

1. **`DocxDocumentCanvas`:**
   - Employs `_splitAndRenderParagraphWithEquations` to expand paragraphs into separate prose widgets (`_buildProseParagraph`) and centered equation widgets (`_buildMathEquationBlock`).
   - Every equation is rendered with `MathStyle.display` on its own line with `Padding(vertical: 12.0 * zoom)`.
   - No inline `WidgetSpan(Math.tex)` exists inside body text runs.
2. **`PaperEditorPage`:**
   - Preserves raw editable LaTeX source during typing and saving.
   - Full manuscript preview tab immediately renders equations using the block-level canvas.

---

## 7. Verification Against the 12 Test Fixtures & Uploaded Paper

All fixtures are covered in `backend/tests/test_mathematical_rendering_regression.py` and `mobile/test/pdf_viewer_toolbar_test.dart`:

| Fixture # | Description | Syntax | AST Node Representation | DOCX & PDF Output |
| :---: | :--- | :--- | :--- | :--- |
| **1** | Inline fraction in sentence | `calculated as \(cos(q,d) = \frac{q \cdot d}{||q|| ||d||}\)` | Pre-Paragraph, `EquationBlockNode`, Post-Paragraph | Centered standalone OMML & 300 DPI image |
| **2** | Summation between prose | `$$\sum_{i=1}^{n} i = \frac{n(n+1)}{2}$$` | `EquationBlockNode(display_type="display")` | Centered standalone OMML & flowable |
| **3** | Display integral | `\[ \int_0^\infty e^{-x} dx = 1 \]` | `EquationBlockNode(display_type="display")` | Centered standalone OMML & flowable |
| **4** | Multiple equations in paragraph | `\(O(n \log n)\)` and `$k \ge 1$` | Split into alternating prose & EquationBlockNodes | Two separate centered equation paragraphs |
| **5** | Greek letters & subscripts | `$\alpha_i + \beta_j \le \lambda$` | `EquationBlockNode` | Centered native Greek symbols |
| **6** | Matrix environment | `\begin{pmatrix} a & b \\ c & d \end{pmatrix}` | `EquationBlockNode(display_type="environment")` | Centered native OMML matrix & PDF Table |
| **7** | Aligned multi-line | `\begin{aligned} a &= b + c \\ d &= e - f \end{aligned}` | `EquationBlockNode(display_type="environment")` | Normalized centered OMML & flowable |
| **8** | Long equation | Loss function exceeding 100 chars | `EquationBlockNode` | Centered equation scaled to margins |
| **9** | Literal LaTeX in code block | `` `\frac{a}{b}` `` | `CodeBlock` / `InlineSpan(kind="code")` | Monospace code text, no equation block |
| **10** | Currency signs | `$50 and $100` | `ParagraphBlock` (kind="text") | Plain currency text preserved |
| **11** | Technical backslashes & escaped dollars | `C:\Users\docs` & `\$75` | `ParagraphBlock` (kind="text") | Plain text preserved |
| **12** | Unsupported LaTeX command | `\(\unsupportedmacro{x}\)` | `EquationBlockNode(rendering_status="warning")` | Visible warning run + LaTeX source |
| **Real Paper** | Real prose from foundation paper | Likelihood loss & KL divergence | `EquationBlockNode` + split prose paragraphs | Centered equations with clean prose boundaries |
