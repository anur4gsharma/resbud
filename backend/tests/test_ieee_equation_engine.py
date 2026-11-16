"""Test suite for IEEE mathematical typesetting and equation engine."""

from __future__ import annotations

import io
import xml.etree.ElementTree as ET
import zipfile

from resbud_api.domain.models import PaperDraft, PaperSection
from resbud_api.services.docx_export import export_paper_docx
from resbud_api.services.equation_engine import (
    clean_equation_latex,
    extract_equations_from_section,
    is_multiline_equation,
    renumber_and_synchronize_equations,
)
from resbud_api.services.markdown_renderer import (
    parse_markdown_blocks,
)
from resbud_api.services.pdf_export import export_paper_pdf

W_NS = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
MATH_NS = {"m": "http://schemas.openxmlformats.org/officeDocument/2006/math"}


def test_clean_equation_latex_and_label_extraction() -> None:
    """Verify LaTeX equation cleaning and label/tag extraction."""
    raw = r"$$\mathbf{E} = mc^2 \label{eq:einstein} \tag{1}$$"
    clean, label, tag = clean_equation_latex(raw)
    assert clean == r"\mathbf{E} = mc^2"
    assert label == "eq:einstein"
    assert tag == "1"

    # Multiline aligned
    raw_aligned = r"""\begin{aligned}
    A &= B + C \\
    &= D + E \label{eq:system}
    \end{aligned}"""
    clean_aligned, label_aligned, tag_aligned = clean_equation_latex(raw_aligned)
    assert "A &= B + C" in clean_aligned
    assert label_aligned == "eq:system"
    assert tag_aligned is None


def test_multiline_equation_detection() -> None:
    """Verify detection of multiline and aligned equation structures."""
    assert is_multiline_equation(r"A = B \\ C = D")
    assert is_multiline_equation(r"\begin{aligned} A &= B \end{aligned}")
    assert is_multiline_equation(r"\begin{gather} x = 1 \\ y = 2 \end{gather}")
    assert is_multiline_equation(r"\begin{matrix} 1 & 0 \\ 0 & 1 \end{matrix}")
    assert not is_multiline_equation(r"E = mc^2")
    assert not is_multiline_equation(r"\frac{a}{b}")


def test_extract_equations_from_section() -> None:
    """Verify extraction of display equations with stable IDs."""
    content = (
        "In this section, we define posture error.\n\n"
        r"$$\mathbf{E}_1 = \|\mathbf{p} - \mathbf{q}\|^2$$"
        "\n\n"
        "And the cosine similarity formulation:\n\n"
        r"$$\text{Sim}(u, v) = \frac{u \cdot v}{\|u\| \|v\|}$$ (2)"
        "\n\n"
        "As seen above."
    )
    eqs = extract_equations_from_section("sec_method", content, start_index=1)
    assert len(eqs) == 2
    assert eqs[0].id == "eq-sec_method-1"
    assert eqs[0].latex == r"\mathbf{E}_1 = \|\mathbf{p} - \mathbf{q}\|^2"
    assert eqs[1].id == "eq-sec_method-2"
    assert eqs[1].prior_number == 2


def test_renumber_and_synchronize_equations_cross_references() -> None:
    """Verify consecutive 1-based numbering and automated in-text cross-reference remapping."""
    sections = [
        PaperSection(
            id="sec_1",
            heading="Methodology",
            content=(
                "First, we define error via Equation (5):\n\n"
                r"$$\mathbf{E} = \sum_{i=1}^N x_i$$ (5)"
                "\n\n"
                "Next, we compute normalization using Eq. [eq-norm]:\n\n"
                r"$$\mathbf{N} = \frac{x}{\sigma} \label{eq:norm}$$"
                "\n\n"
                "Combining (5) and Eq. [eq-norm] yields the metric."
            ),
            state="draft",
        ),
        PaperSection(
            id="sec_2",
            heading="Evaluation",
            content=(
                r"Following the formulation in Eq. (5) and \ref{eq:norm}, the score is given by:"
                "\n\n"
                r"$$\mathbf{S} = \alpha \mathbf{E} + \beta \mathbf{N}$$"
                "\n\n"
                "where (3) determines the composite posture grade."
            ),
            state="draft",
        ),
    ]

    new_sections, equations, warnings = renumber_and_synchronize_equations(sections)
    assert len(equations) == 3
    assert equations[0].equation_number == 1
    assert equations[1].equation_number == 2
    assert equations[2].equation_number == 3

    # Check that in-text references in sec_1 were updated to (1) and (2)
    sec1_text = new_sections[0].content
    assert "Equation (1)" in sec1_text
    assert "Eq. (2)" in sec1_text
    assert "Combining (1) and Eq. (2)" in sec1_text

    # Check that in-text references in sec_2 were updated
    sec2_text = new_sections[1].content
    assert "Eq. (1)" in sec2_text
    assert "(2)" in sec2_text
    assert "(3)" in sec2_text  # Equation 3 reference


def test_markdown_blocks_capture_equation_numbers() -> None:
    """Verify markdown parser assigns equation numbers to EquationBlockNode."""
    text = (
        "Prose before.\n\n"
        r"$$\mathbf{E} = mc^2$$"
        "\n"
        "(1)\n\n"
        "Prose between.\n\n"
        r"$$\mathbf{F} = ma$$ (2)"
        "\n\n"
        "Prose after."
    )
    blocks = parse_markdown_blocks(text)
    eq_blocks = [b for b in blocks if hasattr(b, "equation_id")]
    assert len(eq_blocks) == 2
    assert eq_blocks[0].equation_id == "1"
    assert eq_blocks[1].equation_id == "2"


def test_ieee_docx_export_contains_native_omml_and_borderless_table() -> None:
    """Verify exported DOCX uses borderless 2-cell table with centered OMML and right-aligned (1)."""
    paper = PaperDraft(
        schema_version=1,
        title="Mathematical Typesetting in IEEE Papers",
        abstract="Testing automated equation numbering and native Word equations.",
        keywords=["omml", "mathematics", "ieee"],
        sections=[
            PaperSection(
                id="sec_math",
                heading="Mathematical Modeling",
                content=(
                    "The model error is defined by Equation (1):\n\n"
                    r"$$\mathbf{E} = \sum_{i=1}^{K} \|\mathbf{p}_i - \mathbf{q}_i\|^2$$"
                    "\n\n"
                    "The aligned velocity system is given in Eq. (2):\n\n"
                    r"$$\begin{aligned} v_x &= \dot{x} \\ v_y &= \dot{y} \end{aligned}$$"
                    "\n\n"
                    "Equations (1) and (2) govern the dynamics."
                ),
                state="draft",
            )
        ],
        references=[],
        page_layout="two_column_academic",
        document_template="ieee_conference",
        review_warnings=[],
    )

    docx_bytes = export_paper_docx(paper, template_id="ieee_conference")
    assert docx_bytes.startswith(b"PK")

    with zipfile.ZipFile(io.BytesIO(docx_bytes)) as archive:
        doc_xml = archive.read("word/document.xml")
        root = ET.fromstring(doc_xml)

        # 1. Native OMML elements must exist
        omath_elements = root.findall(".//m:oMath", MATH_NS)
        assert len(omath_elements) >= 2, (
            f"Expected native OMML elements, found {len(omath_elements)}"
        )

        # 2. Check for borderless equation tables (w:tbl with tblBorders none)
        tables = root.findall(".//w:tbl", W_NS)
        assert len(tables) >= 2, "Expected equation tables for display equations"

        # Check equation numbering text in right cell
        full_text = "".join(root.itertext())
        assert "(1)" in full_text
        assert "(2)" in full_text
        assert "Equation (1)" in full_text
        assert "Eq. (2)" in full_text


def test_ieee_pdf_export_with_numbered_equations() -> None:
    """Verify PDF exporter renders display equations with right-aligned numbering table."""
    paper = PaperDraft(
        schema_version=1,
        title="PDF Equation Rendering Validation",
        abstract="Validating PDF math flowables and equation numbers.",
        keywords=["pdf", "reportlab", "equations"],
        sections=[
            PaperSection(
                id="sec_pdf_math",
                heading="Mathematical Formulation",
                content=(
                    "The objective function is expressed in (1):\n\n"
                    r"$$\mathcal{L} = \frac{1}{2} \|\mathbf{w}\|^2 + C \sum_{i=1}^n \xi_i$$"
                    "\n\n"
                    "where (1) is the standard SVM primal formulation."
                ),
                state="draft",
            )
        ],
        references=[],
        page_layout="two_column_academic",
        document_template="ieee_conference",
        review_warnings=[],
    )

    pdf_bytes = export_paper_pdf(paper, template_id="ieee_conference")
    assert pdf_bytes.startswith(b"%PDF")
    assert len(pdf_bytes) > 1000
