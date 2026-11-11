"""Regression test suite for academic mathematical rendering, equation parsing, and document export.

Validates the 12 representative mathematical fixtures across PaperDraft models,
Markdown parsing, DOCX OMML compilation, and PDF flowable generation.
"""

from __future__ import annotations

import io
import zipfile

import pypdf

from resbud_api.domain.models import PaperDraft, PaperSection
from resbud_api.services.docx_export import export_paper_docx
from resbud_api.services.markdown_renderer import (
    CodeBlock,
    MathBlock,
    parse_inline_spans,
    parse_markdown_blocks,
)
from resbud_api.services.pdf_export import export_paper_pdf


def test_fixture_1_inline_expression_parsing() -> None:
    text = r"The equivalence of mass and energy is given by \(E = mc^2\)."
    spans = parse_inline_spans(text)
    math_spans = [s for s in spans if s.kind == "math"]
    assert len(math_spans) == 1
    assert math_spans[0].content == "E = mc^2"


def test_fixture_2_fraction_and_display_math() -> None:
    text = r"$$\frac{a+b}{c}$$"
    blocks = parse_markdown_blocks(text)
    assert len(blocks) == 1
    assert isinstance(blocks[0], MathBlock)
    assert blocks[0].latex == r"\frac{a+b}{c}"


def test_fixture_3_summation_parsing() -> None:
    text = r"\[ \sum_{i=1}^{n} i = \frac{n(n+1)}{2} \]"
    blocks = parse_markdown_blocks(text)
    assert len(blocks) == 1
    assert isinstance(blocks[0], MathBlock)
    assert r"\sum_{i=1}^{n} i" in blocks[0].latex


def test_fixture_4_integral_parsing() -> None:
    text = r"We evaluate $\int_0^\infty e^{-x} dx = 1$ in closed form."
    spans = parse_inline_spans(text)
    math_spans = [s for s in spans if s.kind == "math"]
    assert len(math_spans) == 1
    assert math_spans[0].content == r"\int_0^\infty e^{-x} dx = 1"


def test_fixture_5_greek_letters() -> None:
    text = r"Hyperparameters include $\alpha, \beta, \lambda, \theta$ for regularization."
    spans = parse_inline_spans(text)
    math_spans = [s for s in spans if s.kind == "math"]
    assert len(math_spans) == 1
    assert math_spans[0].content == r"\alpha, \beta, \lambda, \theta"


def test_fixture_6_subscripts_and_superscripts() -> None:
    text = r"Let $x_i^2$ represent the quadratic feature term."
    spans = parse_inline_spans(text)
    math_spans = [s for s in spans if s.kind == "math"]
    assert len(math_spans) == 1
    assert math_spans[0].content == "x_i^2"


def test_fixture_7_square_root() -> None:
    text = r"Distance metric: $\sqrt{x^2+y^2}$."
    spans = parse_inline_spans(text)
    math_spans = [s for s in spans if s.kind == "math"]
    assert len(math_spans) == 1
    assert math_spans[0].content == r"\sqrt{x^2+y^2}"


def test_fixture_8_matrix_environment_parsing() -> None:
    text = "\\begin{pmatrix}\na & b \\\\\nc & d\n\\end{pmatrix}"
    blocks = parse_markdown_blocks(text)
    assert len(blocks) == 1
    assert isinstance(blocks[0], MathBlock)
    assert r"\begin{pmatrix}" in blocks[0].latex


def test_fixture_9_aligned_equation_parsing() -> None:
    text = "\\begin{aligned}\na &= b + c \\\\\nd &= e - f\n\\end{aligned}"
    blocks = parse_markdown_blocks(text)
    assert len(blocks) == 1
    assert isinstance(blocks[0], MathBlock)
    assert r"\begin{aligned}" in blocks[0].latex


def test_fixture_10_ordinary_paragraph_with_embedded_math() -> None:
    text = r"In asymptotic analysis, the algorithm runs in \(O(n \log n)\) time under condition $k \ge 1$."
    spans = parse_inline_spans(text)
    kinds = [s.kind for s in spans]
    assert kinds.count("math") == 2
    assert spans[0].kind == "text"
    assert "In asymptotic analysis" in spans[0].content


def test_fixture_11_code_block_preserves_raw_latex() -> None:
    text = "```latex\n\\int_0^1 f(x)dx\n```"
    blocks = parse_markdown_blocks(text)
    assert len(blocks) == 1
    assert isinstance(blocks[0], CodeBlock)
    assert blocks[0].code == r"\int_0^1 f(x)dx"

    inline_text = r"Use `\frac{a}{b}` to create fractions in LaTeX."
    inline_spans = parse_inline_spans(inline_text)
    code_spans = [s for s in inline_spans if s.kind == "code"]
    math_spans = [s for s in inline_spans if s.kind == "math"]
    assert len(code_spans) == 1
    assert code_spans[0].content == r"\frac{a}{b}"
    assert len(math_spans) == 0


def test_fixture_12_non_math_backslashes_and_currency() -> None:
    # Technical backslash identifiers
    text = r"File path: C:\Users\docs\paper.pdf is located on drive C:."
    spans = parse_inline_spans(text)
    assert all(s.kind == "text" for s in spans)
    assert "".join(s.content for s in spans) == text

    # Currency strings must not be parsed as math
    currency_text = "The conference registration fee was $50 and workshop was $100."
    currency_spans = parse_inline_spans(currency_text)
    math_spans = [s for s in currency_spans if s.kind == "math"]
    assert len(math_spans) == 0
    assert "$50" in "".join(s.content for s in currency_spans)
    assert "$100" in "".join(s.content for s in currency_spans)

    # Escaped dollar signs
    escaped = r"Total cost is \$75 per participant."
    escaped_spans = parse_inline_spans(escaped)
    assert all(s.kind == "text" for s in escaped_spans)
    assert "".join(s.content for s in escaped_spans) == "Total cost is $75 per participant."


def test_docx_export_produces_native_omml_equations() -> None:
    draft = PaperDraft(
        title="Mathematical Foundations in Modern Computing",
        abstract=r"We review \(E = mc^2\) and evaluate fractions \(\frac{a+b}{c}\).",
        keywords=["Mathematics", "OMML", "Word Export"],
        schema_version=1,
        sections=[
            PaperSection(
                id="s1",
                heading="Mathematical Formulation",
                state="draft",
                content=(
                    r"The foundational mass-energy relation is \(E = mc^2\)."
                    "\n\n"
                    r"$$\sum_{i=1}^{n} i = \frac{n(n+1)}{2}$$"
                    "\n\n"
                    r"Distance metric satisfies $\sqrt{x^2+y^2}$."
                    "\n\n"
                    "\\begin{aligned}\na &= b + c \\\\\nd &= e - f\n\\end{aligned}"
                ),
            )
        ],
        references=[],
        review_warnings=[],
    )

    docx_bytes = export_paper_docx(draft)
    assert len(docx_bytes) > 1000

    # Unzip document.xml and verify native Office Math Markup Language (m:oMath)
    with zipfile.ZipFile(io.BytesIO(docx_bytes)) as zf:
        xml_content = zf.read("word/document.xml").decode("utf-8")
        assert "m:oMath" in xml_content
        # Ensure raw unrendered LaTeX markup does not leak as plain body text
        assert r"\begin{aligned}" not in xml_content


def test_pdf_export_renders_math_flowables_without_raw_latex_leakage() -> None:
    draft = PaperDraft(
        title="Empirical Evaluation of Mathematical Rendering",
        abstract=r"Testing PDF equation compilation for \(\int_0^\infty e^{-x} dx\).",
        keywords=["PDF", "Mathtext", "Rendering"],
        schema_version=1,
        sections=[
            PaperSection(
                id="s1",
                heading="Formulas & Analysis",
                state="draft",
                content=(
                    r"The relation \(E = mc^2\) is derived."
                    "\n\n"
                    r"$$\frac{a+b}{c}$$"
                    "\n\n"
                    r"$$\sum_{i=1}^{n} i$$"
                ),
            )
        ],
        references=[],
        review_warnings=[],
    )

    pdf_bytes = export_paper_pdf(draft)
    assert len(pdf_bytes) > 1000

    reader = pypdf.PdfReader(io.BytesIO(pdf_bytes))
    assert len(reader.pages) >= 1
    page_text = reader.pages[0].extract_text() or ""

    # Verify that raw LaTeX commands like \frac{a+b}{c} are NOT displayed as literal text
    assert r"\frac{a+b}{c}" not in page_text
    assert r"$$\frac" not in page_text
