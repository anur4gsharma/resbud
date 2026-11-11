"""Regression test suite for academic mathematical rendering, equation parsing, and document export.

Validates the mandatory block-level mathematical equation policy across:
- All 12 representative mathematical fixtures.
- Real manuscript prose from 'Training Foundation Models with a Single Algorithm.pdf'.
- PaperDraft models, Markdown AST parsing (EquationBlockNode vs ParagraphBlock).
- DOCX OMML compilation with centered equation paragraphs.
- PDF flowables with centered scaling and visible warnings for unsupported commands.
"""

from __future__ import annotations

import io
import zipfile

import pypdf

from resbud_api.domain.models import PaperDraft, PaperSection
from resbud_api.services.docx_export import export_paper_docx
from resbud_api.services.markdown_renderer import (
    CodeBlock,
    EquationBlockNode,
    ParagraphBlock,
    parse_markdown_blocks,
)
from resbud_api.services.pdf_export import export_paper_pdf


def test_fixture_1_inline_fraction_extracted_to_block_equation() -> None:
    text = r"The cosine similarity between two vectors is calculated as \(cos(q,d) = \frac{q \cdot d}{||q|| ||d||}\), where q represents the query vector."
    blocks = parse_markdown_blocks(text)
    assert len(blocks) == 3
    assert isinstance(blocks[0], ParagraphBlock)
    assert "The cosine similarity between two vectors is calculated as follows:" in "".join(
        s.content for s in blocks[0].spans
    )
    assert all(s.kind != "math" for s in blocks[0].spans)

    assert isinstance(blocks[1], EquationBlockNode)
    assert r"\frac{q \cdot d}{||q|| ||d||}" in blocks[1].latex
    assert blocks[1].display_type == "extracted_inline"
    assert blocks[1].rendering_status == "ok"

    assert isinstance(blocks[2], ParagraphBlock)
    assert "Here, q represents the query vector." in "".join(s.content for s in blocks[2].spans)
    assert all(s.kind != "math" for s in blocks[2].spans)


def test_fixture_2_summation_embedded_between_prose_sentences() -> None:
    text = (
        r"We compute the arithmetic series as follows: "
        r"$$\sum_{i=1}^{n} i = \frac{n(n+1)}{2}$$"
        r", where n denotes the total number of terms."
    )
    blocks = parse_markdown_blocks(text)
    eq_blocks = [b for b in blocks if isinstance(b, EquationBlockNode)]
    prose_blocks = [b for b in blocks if isinstance(b, ParagraphBlock)]

    assert len(eq_blocks) == 1
    assert r"\sum_{i=1}^{n} i" in eq_blocks[0].latex
    assert len(prose_blocks) == 2
    for pb in prose_blocks:
        assert all(s.kind != "math" for s in pb.spans)


def test_fixture_3_display_integral() -> None:
    text = r"\[ \int_0^\infty e^{-x} dx = 1 \]"
    blocks = parse_markdown_blocks(text)
    assert len(blocks) == 1
    assert isinstance(blocks[0], EquationBlockNode)
    assert r"\int_0^\infty e^{-x} dx = 1" in blocks[0].latex
    assert blocks[0].display_type == "display"


def test_fixture_4_multiple_equations_in_same_paragraph() -> None:
    text = r"In asymptotic analysis, the algorithm runs in \(O(n \log n)\) time under condition $k \ge 1$."
    blocks = parse_markdown_blocks(text)
    eq_blocks = [b for b in blocks if isinstance(b, EquationBlockNode)]
    prose_blocks = [b for b in blocks if isinstance(b, ParagraphBlock)]

    assert len(eq_blocks) == 2
    assert eq_blocks[0].latex == r"O(n \log n)"
    assert eq_blocks[1].latex == r"k \ge 1"

    assert len(prose_blocks) == 2
    assert "In asymptotic analysis" in "".join(s.content for s in prose_blocks[0].spans)
    for pb in prose_blocks:
        assert all(s.kind != "math" for s in pb.spans)


def test_fixture_5_greek_letters_and_subscripts() -> None:
    text = r"The model regularization is governed by $\alpha_i + \beta_j \le \lambda$."
    blocks = parse_markdown_blocks(text)
    eq_blocks = [b for b in blocks if isinstance(b, EquationBlockNode)]
    assert len(eq_blocks) == 1
    assert eq_blocks[0].latex == r"\alpha_i + \beta_j \le \lambda"


def test_fixture_6_matrix_environment_parsing() -> None:
    text = "\\begin{pmatrix}\na & b \\\\\nc & d\n\\end{pmatrix}"
    blocks = parse_markdown_blocks(text)
    assert len(blocks) == 1
    assert isinstance(blocks[0], EquationBlockNode)
    assert r"\begin{pmatrix}" in blocks[0].latex
    assert blocks[0].display_type == "environment"


def test_fixture_7_aligned_multiline_expression() -> None:
    text = "\\begin{aligned}\na &= b + c \\\\\nd &= e - f\n\\end{aligned}"
    blocks = parse_markdown_blocks(text)
    assert len(blocks) == 1
    assert isinstance(blocks[0], EquationBlockNode)
    assert r"\begin{aligned}" in blocks[0].latex
    assert blocks[0].display_type == "environment"


def test_fixture_8_long_equation_approaching_page_width() -> None:
    long_eq = (
        r"\[ \mathcal{L}_{\text{total}}(\theta; x, y) = "
        r"-\sum_{i=1}^{N} \left[ y_i \log \hat{y}_i + (1 - y_i)\log(1 - \hat{y}_i) \right] "
        r"+ \frac{\lambda}{2} \|\theta\|_2^2 + \gamma \sum_{j=1}^{M} |\theta_j| \]"
    )
    blocks = parse_markdown_blocks(long_eq)
    assert len(blocks) == 1
    assert isinstance(blocks[0], EquationBlockNode)
    assert len(blocks[0].latex) > 100


def test_fixture_9_code_block_preserves_raw_latex() -> None:
    text = "```latex\n\\int_0^1 f(x)dx\n```"
    blocks = parse_markdown_blocks(text)
    assert len(blocks) == 1
    assert isinstance(blocks[0], CodeBlock)
    assert blocks[0].code == r"\int_0^1 f(x)dx"

    inline_text = r"Use `\frac{a}{b}` to create fractions in LaTeX."
    blocks_inline = parse_markdown_blocks(inline_text)
    assert len(blocks_inline) == 1
    assert isinstance(blocks_inline[0], ParagraphBlock)
    code_spans = [s for s in blocks_inline[0].spans if s.kind == "code"]
    math_spans = [s for s in blocks_inline[0].spans if s.kind == "math"]
    assert len(code_spans) == 1
    assert code_spans[0].content == r"\frac{a}{b}"
    assert len(math_spans) == 0


def test_fixture_10_dollar_signs_as_currency_preserved_as_prose() -> None:
    currency_text = "The conference registration fee was $50 and workshop was $100."
    blocks = parse_markdown_blocks(currency_text)
    assert len(blocks) == 1
    assert isinstance(blocks[0], ParagraphBlock)
    full_prose = "".join(s.content for s in blocks[0].spans)
    assert "$50" in full_prose
    assert "$100" in full_prose
    assert all(s.kind != "math" for s in blocks[0].spans)


def test_fixture_11_technical_strings_with_backslashes_and_escaped_dollars() -> None:
    text = r"File path: C:\Users\docs\paper.pdf is located on drive C:."
    blocks = parse_markdown_blocks(text)
    assert len(blocks) == 1
    assert isinstance(blocks[0], ParagraphBlock)
    assert r"C:\Users\docs\paper.pdf" in "".join(s.content for s in blocks[0].spans)

    escaped = r"Total cost is \$75 per participant."
    blocks_esc = parse_markdown_blocks(escaped)
    assert len(blocks_esc) == 1
    assert isinstance(blocks_esc[0], ParagraphBlock)
    assert "Total cost is $75 per participant." in "".join(s.content for s in blocks_esc[0].spans)


def test_fixture_12_unsupported_mathematical_command_yields_warning() -> None:
    unsupported_text = r"We apply \(\unsupportedmacro{x}\) to the input sequence."
    blocks = parse_markdown_blocks(unsupported_text)
    eq_blocks = [b for b in blocks if isinstance(b, EquationBlockNode)]
    assert len(eq_blocks) == 1
    assert eq_blocks[0].rendering_status in ("warning", "error")
    assert eq_blocks[0].validation_error is not None
    assert "unsupported" in eq_blocks[0].validation_error.lower()


def test_real_manuscript_prose_from_foundation_models_paper() -> None:
    """Verifies parsing and separation of real research sentences from the uploaded manuscript:

    format_specifier_papers/Training Foundation Models with a Single Algorithm.pdf
    """
    sentence_1 = (
        r"Maximum likelihood estimation minimizes the loss "
        r"\(L(\theta;\rho\circ\mu) := -\mathbb{E}_{x\sim\rho} \mathbb{E}_{y\sim\mu(\cdot|x)}[\log\pi_\theta(y|x)]\), "
        r"where x is the prompt and y is completion."
    )
    blocks_1 = parse_markdown_blocks(sentence_1)
    assert len(blocks_1) == 3
    assert isinstance(blocks_1[0], ParagraphBlock)
    assert "Maximum likelihood estimation minimizes the loss:" in "".join(
        s.content for s in blocks_1[0].spans
    )
    assert all(s.kind != "math" for s in blocks_1[0].spans)

    assert isinstance(blocks_1[1], EquationBlockNode)
    assert r"L(\theta;\rho\circ\mu)" in blocks_1[1].latex
    assert blocks_1[1].rendering_status == "ok"

    assert isinstance(blocks_1[2], ParagraphBlock)
    assert "Here, x is the prompt and y is completion." in "".join(
        s.content for s in blocks_1[2].spans
    )
    assert all(s.kind != "math" for s in blocks_1[2].spans)

    sentence_2 = (
        r"For a fixed training data distribution, this loss differs from the expected forward KL divergence "
        r"\(E_{x\sim\rho}[\mathrm{KL}(\mu(\cdot|x) \parallel \pi_\theta(\cdot|x))]\) "
        r"only by a constant independent of \theta. Both objectives therefore have the same gradient: "
        r"\[\nabla_\theta L(\theta;\rho\circ\mu) = -\mathbb{E}_{x\sim\rho} \mathbb{E}_{y\sim\mu(\cdot|x)}[\nabla_\theta \log\pi_\theta(y|x)]\]."
    )
    blocks_2 = parse_markdown_blocks(sentence_2)
    eq_blocks_2 = [b for b in blocks_2 if isinstance(b, EquationBlockNode)]
    prose_blocks_2 = [b for b in blocks_2 if isinstance(b, ParagraphBlock)]

    assert len(eq_blocks_2) == 2
    assert "KL" in eq_blocks_2[0].latex
    assert r"\nabla_\theta" in eq_blocks_2[1].latex

    assert len(prose_blocks_2) == 2
    for pb in prose_blocks_2:
        assert all(s.kind != "math" for s in pb.spans)


def test_docx_export_produces_native_omml_equations_in_standalone_paragraphs() -> None:
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
                    r"The relation is calculated as \(E = mc^2\), where c is speed of light."
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
    # Verify split prose appears cleanly
    assert "speed of light" in page_text
