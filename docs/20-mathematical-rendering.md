# Architectural Specification: Academic Mathematical Rendering & Equation Pipeline

## 1. Executive Summary

This document specifies the end-to-end mathematical rendering architecture for Resbud manuscripts across Markdown parsing, DOCX native equation compilation, PDF generation, and Flutter in-app reading/editing interfaces.

Prior to this overhaul, mathematical expressions suffered from severe pipeline failures:
1. **ReportLab PDF Leaks:** Mathematical expressions were rendered as raw italicized LaTeX code (e.g. `<i>\frac{a+b}{c}</i>`), forcing users to read unprocessed TeX markup in compiled PDFs.
2. **DOCX Equation Degradation:** Word exports relied on unhandled conversions that threw XML parsing errors on `aligned` environments, dropping math into plain body runs.
3. **Delimiter Collisions & Currency Corruption:** Plain dollar amounts (e.g. `$50 and $100`) were mistakenly parsed as inline mathematics, while LaTeX syntax inside code blocks was tokenized as math.
4. **Editor Disconnect:** The paper editor only showed raw input without any equation preview, and lacked baseline-aligned visual validation.

The revised architecture establishes a unified mathematical contract ensuring that equations remain editable native Word OMML in DOCX, crisp high-DPI vector/raster flowables in PDF, and interactive rendered formulas in Flutter.

---

## 2. Canonical Mathematical Syntax & Tokenization Contract

Resbud enforces standard academic LaTeX and Pandoc delimiters:

| Notation Type | Supported Delimiters | Example | Rendering Behavior |
| :--- | :--- | :--- | :--- |
| **Inline Math** | `\( ... \)` or `$ ... $` | `\(E = mc^2\)` or `$x_i^2$` | Baseline-aligned inline formula |
| **Display Math** | `\[ ... \]` or `$$ ... $$` | `\[ \sum_{i=1}^n i = \frac{n(n+1)}{2} \]` | Centered display block with Pt(8) margins |
| **Block Environments** | `\begin{equation}...\end{equation}`, `\begin{align}...\end{align}`, `\begin{aligned}...\end{aligned}`, `\begin{pmatrix}...\end{pmatrix}`, `\begin{matrix}...\end{matrix}` | `\begin{pmatrix} a & b \\ c & d \end{pmatrix}` | Centered multi-line / matrix block |
| **Inline Code** | `` `...` `` | `` `\frac{a}{b}` `` | Fixed-width monospace text, math parsing suppressed |
| **Currency Values** | `$50`, `$100 USD`, `\$75` | `Registration is $50 and fee is $100.` | Retained as plain currency text |
| **Technical Paths** | `C:\Users\docs\paper.pdf` | `File is at C:\path\to\data` | Retained as plain text |

### Regex Grammar & Token Precedence

To eliminate false positives:
1. **Inline Code Precedence:** Backtick expressions `` `[^`\n]+` `` are tokenized *first*. LaTeX commands inside code blocks are preserved as literal text.
2. **Escaped Dollar Signs:** `\\\$` is explicitly captured and emitted as literal `$` text.
3. **Display Math Precedence:** Multiline `\$\$[\s\S]*?\$\$` and `\\\[[\s\S]*?\\\]` are evaluated prior to single dollar delimiters.
4. **Pandoc Dollar Rule:** Inline dollar math requires:
   ```regex
   (?<!\\)\$(?!\s)(?!\d+(?:\s|[.,;:!?]|$))((?:[^$\n\\]|\\.)+?)(?<!\s)\$(?!\d)
   ```
   - Opening `$` must not be followed by whitespace or standalone digits.
   - Closing `$` must not be preceded by whitespace or followed by digits.
   - Neither delimiter may be escaped.

---

## 3. DOCX Native Word Equation Compilation (OMML)

Word documents are one of Resbud's primary deliverable formats. Equations must remain editable native Word equations rather than low-resolution static raster screenshots.

### Compilation Pipeline

```
LaTeX String
    │
    ▼
Delimiter Stripping & Sanitization
    │
    ▼
latex2mathml (LaTeX -> MathML)
    │
    ▼
XML Ampersand & Token Cleanup (<mi>&</mi> -> stripped / matrix conversion)
    │
    ▼
mathml2omml (MathML -> OMML)
    │
    ▼
docx.oxml.parse_xml (<p xmlns:m="..."><m:oMath>...</m:oMath></p>)
    │
    ▼
Insertion into Paragraph XML Tree (p._p.append(...))
```

### Sanitization of Aligned Environments

`latex2mathml` produces unescaped ampersands (`<mi>&</mi>`) when translating `\begin{aligned}` or `\begin{align}` environments, triggering XML syntax parse errors in downstream tools. The Resbud translation engine pre-sanitizes alignment anchors:
- `\begin{aligned}` and `\begin{align}` are normalized to `\begin{matrix}`.
- `&=` is normalized to `=`.
- Stray alignment ampersands are stripped or converted to column breaks before MathML generation.

---

## 4. ReportLab PDF High-DPI Flowable Architecture

In compiled PDF documents, raw LaTeX syntax must never leak into paragraph text.

### Display Equation Flowables

For `MathBlock`:
1. Delimiters (`$$`, `\[`, etc.) are stripped.
2. Matrix environments (`pmatrix`, `bmatrix`) are either converted to formatted ReportLab `Table` flowables or processed via mathtext.
3. Transparent in-memory PNGs are rasterized at **300 DPI** using `matplotlib` mathtext.
4. The resulting image is wrapped in a ReportLab `RLImage` flowable with exact physical dimensions in typographical points:
   $$\text{width}_{\text{pt}} = \frac{\text{width}_{\text{px}}}{\text{DPI}} \times 72$$
5. Centered display alignment (`hAlign="CENTER"`) and vertical margins (`Spacer(1, 4)`) ensure consistent academic typography.

### Inline Equation Images

For `InlineSpan(kind="math")`:
1. Expressions are converted to cached 300 DPI PNGs in a managed temporary directory.
2. The HTML stream incorporates baseline-adjusted image tags:
   ```html
   <img src="/tmp/.../math_123.png" width="45.0" height="12.5" valign="-2"/>
   ```
3. If an expression cannot be rasterized due to syntax errors, the engine falls back to styled italic text with escaped HTML entities, preventing compilation crashes.

---

## 5. Flutter Reading Canvas & Editor Mathematics Preview

### Reading Canvas (`DocxDocumentCanvas`)

`DocxDocumentCanvas` provides a high-fidelity publication view of the paper.
- Inline math is matched via `inlineTokenRegex` and rendered via `flutter_math_fork` using `Math.tex(..., mathStyle: MathStyle.text)`.
- Display equations and block environments (`\begin{equation}`, `\begin{pmatrix}`, etc.) are rendered centered with `MathStyle.display`.
- Fallbacks display the raw formula in an italicized serif run if a syntax error occurs.

### Interactive Equation Preview in Editor (`PaperEditorPage`)

To ensure researchers can verify equations while editing:
1. Each section card contains an action button: **"Preview Equations"** (`button-preview-math-${section.id}`).
2. Toggling preview mounts a live `DocxDocumentCanvas` rendering of the current section text immediately below the raw editor field.
3. Editing text in `TextFormField` preserves raw LaTeX markup with zero corruption on save, reload, and export.

---

## 6. Verification Against the 12 Test Fixtures

All 12 representative academic mathematical test fixtures are validated via automated tests in `backend/tests/test_mathematical_rendering_regression.py` and `mobile/test/pdf_viewer_toolbar_test.dart`:

| Fixture # | Description | Syntax | DOCX Output | PDF Output |
| :---: | :--- | :--- | :--- | :--- |
| **1** | Inline expression | `\(E = mc^2\)` | Native `<m:oMath>` | High-DPI inline image |
| **2** | Fraction | `\(\frac{a+b}{c}\)` | Native `<m:oMath>` fraction | High-DPI flowable |
| **3** | Summation | `\sum_{i=1}^{n} i` | Native `<m:oMath>` n-ary | High-DPI flowable |
| **4** | Integral | `\int_0^\infty e^{-x} dx` | Native `<m:oMath>` integral | High-DPI flowable |
| **5** | Greek letters | `\alpha, \beta, \lambda, \theta` | Native Greek math characters | High-DPI characters |
| **6** | Subscripts & superscripts | `x_i^2` | Native `<m:sSubSup>` | High-DPI flowable |
| **7** | Square root | `\sqrt{x^2+y^2}` | Native `<m:rad>` radical | High-DPI flowable |
| **8** | Matrix notation | `\begin{pmatrix} a & b \\ c & d \end{pmatrix}` | Native `<m:m>` matrix | Structured matrix flowable |
| **9** | Multi-line aligned | `\begin{aligned} a &= b + c \\ d &= e - f \end{aligned}` | Sanitized native OMML | Multi-line aligned flowable |
| **10** | Embedded math in prose | `Runs in \(O(n \log n)\) time` | Inlined `<m:oMath>` in run | Inline image in paragraph |
| **11** | LaTeX in code block | `` `\frac{a}{b}` `` | Plain Consolas run | Plain `<code>` block |
| **12** | Non-math backslashes & currency | `C:\Users\docs` & `$50` | Plain Times run | Plain text run |
