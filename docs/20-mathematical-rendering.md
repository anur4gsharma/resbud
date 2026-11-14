# Architectural Specification: Mathematical Rendering & Equation Pipeline

## 1. Executive Summary & Design Rule

This document specifies the end-to-end mathematical rendering architecture for Resbud manuscripts across Markdown AST parsing, DOCX native equation compilation, PDF generation, and Flutter in-app reading/editing interfaces.

**Academic Mathematical Formatting Rule:**
> **Big Equations (Display Math):** Standalone formulas, multiline expressions, and explicit display math (`$$...$$`, `\[...\]`, `\begin{equation|align|aligned|gather|matrix|pmatrix|bmatrix|vmatrix|cases}...`) are rendered as dedicated display equations, horizontally centered on their own separate line with appropriate vertical spacing.
>
> **Inline Mathematical Expressions:** Variables, symbols, indices, and short formulas (`$x$`, `$c \in \mathcal{C}$`, `\(O(n \log n)\)`, `$k \ge 1$`, `$\alpha_i + \beta_j \le \lambda$`, `($P$)`) remain inline within the paragraph prose. They must never start an arbitrary new line or fragment sentences.

---

## 2. Document AST & Mathematical Representation

Mathematical content is structured cleanly between block-level and inline AST representations:

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


@dataclass
class InlineSpan:
    kind: Literal["text", "bold", "italic", "bold_italic", "code", "math", "link"]
    content: str
    target: str | None = None
```

### Critical AST Properties:
1. **Inline Math Preservation:** `ParagraphBlock` contains `InlineSpan(kind="math", content=clean)` for all inline variables and formulas, keeping paragraphs unbroken and grammatically intact.
2. **Dedicated Display Blocks:** Only big display equations (`$$...$$`, `\[...\]`, LaTeX environments, or standalone formulas) are lifted into standalone `EquationBlockNode` elements.
3. **Immutability of Source:** Original LaTeX is strictly preserved in `latex`. Editing a section in Flutter preserves the exact source for future re-renders.

---

## 3. Paragraph Splitting & Prose Boundary Formatting

When a paragraph contains one or more display equations, `extract_equation_blocks_from_paragraph` partitions the text around the display equations while leaving inline math intact inside the prose blocks:

### Transformation Rules:
1. **Preceding Prose Cleaning:**
   - Trailing commas or semicolons attached to an introductory clause are stripped.
   - Introduction clauses ending with verbs/prepositions (e.g., `calculated as`, `defined as`, `expressed as`) are normalized to `calculated as follows:`.
   - Intro phrases ending in `is`, `given by`, `satisfies`, or `minimizes the loss` receive a trailing colon `:`.
2. **Standalone Equation Extraction:**
   - Outer delimiters (`$$`, `\[`) are stripped while preserving complete LaTeX commands, matrices, and symbols.
   - Verified against `MathTextParser` and `latex2mathml` converters.
3. **Subsequent Prose Cleaning:**
   - Leading commas and semicolons are stripped.
   - Continuation prose (e.g., `where $q$ represents the query vector`) flows naturally without artificial forced capitalization.

---

## 4. DOCX Export Requirements (Native Word OMML)

1. **Inline Math:** Rendered as inline `<m:oMath>` OpenXML runs within the paragraph run stream.
2. **Display Equations:** Every display equation occupies its own paragraph, horizontally centered (`WD_ALIGN_PARAGRAPH.CENTER`) with `Pt(8)` vertical margins before and after.
3. **Native OMML:** Converted via `latex2mathml` and `mathml2omml` into native `<m:oMath>` OpenXML structures.
4. **Warning Semantics:** If an expression contains invalid syntax or unsupported macros (e.g. `\unsupportedmacro{x}`), the original LaTeX is displayed centered with an explicit red warning run: `[Warning: Unsupported mathematical syntax]`.

---

## 5. PDF Export Requirements (ReportLab Flowables)

1. **Inline Math:** Rendered as crisp inline `<img>` tags (`valign="-2"`) embedded directly inside ReportLab `Paragraph` flowables at 300 DPI.
2. **Standalone Display Flowables:** Big equations are rasterized at **300 DPI** via `matplotlib` mathtext and placed in a centered `RLImage` flowable bounded by `Spacer(1, 6)` top and bottom.
3. **Proportional Scaling:** Long equations approaching the physical page width (460 pt printable width) are scaled proportionally to prevent margin clipping.
4. **Matrix Support:** Matrix environments (`pmatrix`, `bmatrix`, `matrix`) are rendered as centered, bordered ReportLab `Table` flowables.
5. **Warning Semantics:** Erroneous or unsupported formulas produce a visible warning paragraph (`styles["MathBlock"]`) preserving source and highlighting syntax issues.

---

## 6. Flutter Reading Canvas & Editor Experience

1. **`DocxDocumentCanvas`:**
   - Employs `_splitAndRenderParagraphWithEquations` to separate paragraphs containing big equations into prose widgets and centered equation widgets (`_buildMathEquationBlock`).
   - Inline math expressions inside prose are rendered seamlessly using `WidgetSpan(alignment: PlaceholderAlignment.middle, child: Math.tex(..., mathStyle: MathStyle.text))`.
   - Big equations are rendered with `MathStyle.display` on their own line with `Padding(vertical: 12.0 * zoom)`.
2. **`PaperEditorPage`:**
   - Preserves raw editable LaTeX source during typing and saving.
   - Full manuscript preview tab immediately renders equations using the dual inline/block canvas.

---

## 7. Verification Against Test Fixtures

| Fixture # | Description | Syntax | AST Node Representation | DOCX & PDF Output |
| :---: | :--- | :--- | :--- | :--- |
| **1** | Display fraction in sentence | `calculated as $$\cos(q,d) = \frac{q \cdot d}{\|q\| \|d\|}$$, where $q$...` | Pre-Paragraph, `EquationBlockNode`, Post-Paragraph (with inline `$q$`) | Centered standalone OMML & 300 DPI image |
| **2** | Summation between prose | `$$\sum_{i=1}^{n} i = \frac{n(n+1)}{2}$$` | `EquationBlockNode(display_type="display")` | Centered standalone OMML & flowable |
| **3** | Display integral | `\[ \int_0^\infty e^{-x} dx = 1 \]` | `EquationBlockNode(display_type="display")` | Centered standalone OMML & flowable |
| **4** | Inline math in paragraph | `\(O(n \log n)\)` and `$k \ge 1$` | Single `ParagraphBlock` with inline math spans | Inline OMML & inline 300 DPI images in paragraph |
| **5** | Greek letters & subscripts | `$\alpha_i + \beta_j \le \lambda$` | Single `ParagraphBlock` with inline math span | Inline Greek symbols without line breaks |
| **6** | Matrix environment | `\begin{pmatrix} a & b \\ c & d \end{pmatrix}` | `EquationBlockNode(display_type="environment")` | Centered native OMML matrix & PDF Table |
| **7** | Aligned multi-line | `\begin{aligned} a &= b + c \\ d &= e - f \end{aligned}` | `EquationBlockNode(display_type="environment")` | Normalized centered OMML & flowable |
| **8** | Long equation | Loss function exceeding 100 chars | `EquationBlockNode` | Centered equation scaled to margins |
| **9** | Literal LaTeX in code block | `` `\frac{a}{b}` `` | `CodeBlock` / `InlineSpan(kind="code")` | Monospace code text, no equation block |
| **10** | Currency signs | `$50 and $100` | `ParagraphBlock` (kind="text") | Plain currency text preserved |
| **11** | Technical backslashes & escaped dollars | `C:\Users\docs` & `\$75` | `ParagraphBlock` (kind="text") | Plain text preserved |
| **12** | Unsupported LaTeX command | `$$\unsupportedmacro{x}$$` | `EquationBlockNode(rendering_status="warning")` | Visible warning run + LaTeX source |
| **Real Paper** | Real prose from foundation paper | Likelihood loss & KL divergence | `EquationBlockNode` + prose with inline KL | Centered display equation + inline prose |
