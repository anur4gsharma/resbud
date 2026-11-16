"""Comprehensive Mathematical Regression Test Suite for Native Word Equations (OMML).

Verifies the 20 mathematical test cases across the complete document lifecycle:
LaTeX input -> Parsing -> Internal representation -> DOCX export -> OpenXML inspection.
Rejects tests that merely check for substrings or pass via raster equation images.
"""

from __future__ import annotations

import io
import xml.etree.ElementTree as ET
import zipfile

from resbud_api.domain.models import PaperDraft, PaperSection
from resbud_api.services.docx_export import export_paper_docx
from resbud_api.services.markdown_renderer import (
    parse_markdown_blocks,
)
from resbud_api.services.math_omml import (
    latex_to_omml_xml,
)
from resbud_api.services.pdf_export import export_paper_pdf

MATH_NS = {"m": "http://schemas.openxmlformats.org/officeDocument/2006/math"}
W_NS = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}


def _build_comprehensive_math_paper(layout: str = "single_column") -> PaperDraft:
    """Build manuscript containing all 20 canonical mathematical regression constructs."""
    content = (
        # 16. Equations inside long paragraphs with 1, 2, 3, 4, 5, 6
        r"In modern algorithmic information retrieval, the ranking function relies on key statistical signals. "
        r"Specifically, we define the query term variable $x$ and term importance parameter $\alpha \in [0, 1]$. "
        r"For each document $d$, the frequency of term $i$ is denoted by subscript $x_i$, with quadratic scaling "
        r"superscript $x^2$. Normalized frequency uses inline fraction $\frac{a}{b}$, while user intent is captured "
        r"by inline probability notation $P(\mathbf{s} \mid \mathbf{e})$ across all indexed tokens."
        "\n\n"
        # 7. Display fraction
        r"The normalized inverse length ratio is expressed as a display fraction:"
        "\n\n"
        r"$$\frac{a + b}{c + d}$$"
        "\n\n"
        # 8. BM25 scoring function
        r"The complete Okapi BM25 scoring function is formulated as follows:"
        "\n\n"
        r"$$\text{BM25}(D, Q) = \sum_{i=1}^{N} \text{IDF}(q_i) \cdot \frac{f(q_i, D) \cdot (k_1 + 1)}{f(q_i, D) + k_1 \cdot (1 - b + b \cdot \frac{|D|}{\text{avgdl}})}$$"
        "\n\n"
        # 9. Cosine similarity
        r"Vector space semantic similarity between dense embeddings uses cosine similarity:"
        "\n\n"
        r"$$\cos(\theta) = \frac{\mathbf{A} \cdot \mathbf{B}}{\|\mathbf{A}\| \|\mathbf{B}\|}$$"
        "\n\n"
        # 10. Reciprocal Rank Fusion
        r"Reciprocal Rank Fusion (RRF) combines reciprocal ranks across disparate rankers:"
        "\n\n"
        r"$$\text{RRF}(d) = \sum_{m \in M} \frac{1}{k + r_m(d)}$$"
        "\n\n"
        # 11. Summation with limits
        r"The arithmetic sequence sum with explicit index boundaries satisfies:"
        "\n\n"
        r"$$\sum_{i=1}^{n} i = \frac{n(n+1)}{2}$$"
        "\n\n"
        # 12. Integral
        r"Continuous energy distribution over infinite domains evaluates to:"
        "\n\n"
        r"$$\int_{0}^{\infty} e^{-x^2} dx = \frac{\sqrt{\pi}}{2}$$"
        "\n\n"
        # 13. Matrix
        r"Stabilizer code syndrome transformations employ unitary matrices:"
        "\n\n"
        r"$$\begin{pmatrix} 1 & 0 \\ 0 & 1 \end{pmatrix}$$"
        "\n\n"
        # 14. Piecewise expression (cases)
        r"The rectified activation and penalty piecewise threshold function is given by:"
        "\n\n"
        r"$$\begin{cases} x & \text{if } x > 0 \\ -x & \text{otherwise} \end{cases}$$"
        "\n\n"
        # 15. Aligned multi-line equations
        r"Multi-stage derivation of the error bound follows:"
        "\n\n"
        r"$$\begin{align} a &= b + c \\ d &= e + f \end{align}$$"
        "\n\n"
        # 18. Equations next to tables and figures
        r"| Metric | Formula | Target |"
        "\n"
        r"| --- | --- | --- |"
        "\n"
        r"| Precision | $P = \frac{TP}{TP + FP}$ | > 95% |"
        "\n"
        r"| Recall | $R = \frac{TP}{TP + FN}$ | > 90% |"
        "\n\n"
        r"![Figure 1: Mathematical Architecture Diagram](schema_math_diagram)"
        "\n\n"
        # 19. Literal LaTeX inside code blocks (must NOT be parsed as math)
        r"Code snippets demonstrate verbatim LaTeX formatting:"
        "\n\n"
        r"```latex"
        "\n"
        r"\newcommand{\bm25}{\sum_{i=1}^n \text{IDF}}"
        "\n"
        r"```"
        "\n\n"
        # 20. Unsupported / malformed mathematical syntax
        r"Resilient handling of malformed math:"
        "\n\n"
        r"$$\frac{unbalanced_left{}$$"
    )

    return PaperDraft(
        schema_version=1,
        title="Comprehensive Evaluation of Native OMML Word Mathematics",
        abstract="This paper validates the complete mathematical rendering lifecycle from LaTeX to native Word OMML equations.",
        keywords=["Mathematics", "OMML", "WordprocessingML", "LaTeX", "ReportLab"],
        author_info="Resbud Document Engineering Team",
        affiliation="Resbud Automated Publishing Lab",
        page_layout=layout,
        sections=[
            PaperSection(
                id="sec1",
                heading="1. Mathematical Formulation & Architecture",
                content=content,
                state="draft",
            )
        ],
        references=[],
        review_warnings=[],
    )


def test_omml_xml_generation_for_core_constructs() -> None:
    """Verify individual mathematical constructs generate valid OMML XML nodes."""
    test_cases = [
        # (name, latex, is_display)
        ("1. inline var", "x", False),
        ("2. greek", r"\alpha", False),
        ("3. subscript", "x_i", False),
        ("4. superscript", "x^2", False),
        ("5. inline frac", r"\frac{a}{b}", False),
        ("6. prob notation", r"P(\mathbf{s} \mid \mathbf{e})", False),
        ("7. display frac", r"\frac{a + b}{c + d}", True),
        (
            "8. BM25",
            r"\text{BM25}(D, Q) = \sum_{i=1}^{N} \text{IDF}(q_i) \cdot \frac{f(q_i, D) \cdot (k_1 + 1)}{f(q_i, D) + k_1 \cdot (1 - b + b \cdot \frac{|D|}{\text{avgdl}})}",
            True,
        ),
        (
            "9. Cosine",
            r"\cos(\theta) = \frac{\mathbf{A} \cdot \mathbf{B}}{\|\mathbf{A}\| \|\mathbf{B}\|}",
            True,
        ),
        ("10. RRF", r"\text{RRF}(d) = \sum_{m \in M} \frac{1}{k + r_m(d)}", True),
        ("11. Sum limits", r"\sum_{i=1}^{n} i = \frac{n(n+1)}{2}", True),
        ("12. Integral", r"\int_{0}^{\infty} e^{-x^2} dx = \frac{\sqrt{\pi}}{2}", True),
        ("13. Matrix", r"\begin{pmatrix} 1 & 0 \\ 0 & 1 \end{pmatrix}", True),
        (
            "14. Cases",
            r"\begin{cases} x & \text{if } x > 0 \\ -x & \text{otherwise} \end{cases}",
            True,
        ),
        ("15. Align", r"\begin{align} a &= b + c \\ d &= e + f \end{align}", True),
    ]

    for name, formula, is_display in test_cases:
        xml_str, status, _ = latex_to_omml_xml(formula, is_display=is_display)
        assert status in ("ok", "warning"), f"Failed on {name}"
        root = ET.fromstring(xml_str)
        expected_tag = f"{{{MATH_NS['m']}}}" + ("oMathPara" if is_display else "oMath")
        assert root.tag == expected_tag, f"Expected {expected_tag}, got {root.tag} for {name}"
        if is_display:
            omaths = root.findall("./m:oMath", MATH_NS)
            assert len(omaths) == 1, f"Missing inner oMath in oMathPara for {name}"


def test_docx_export_contains_genuine_omml_and_zero_equation_images() -> None:
    """Rigorous acceptance test: unzips exported DOCX and verifies genuine OMML elements."""
    paper = _build_comprehensive_math_paper(layout="single_column")
    docx_bytes = export_paper_docx(paper, layout="single_column")

    assert len(docx_bytes) > 1000, "DOCX payload empty"

    with zipfile.ZipFile(io.BytesIO(docx_bytes)) as z:
        # Check that NO equation images were created in word/media/
        media_files = [f for f in z.namelist() if f.startswith("word/media/")]
        for mf in media_files:
            assert not mf.endswith((".png", ".jpg", ".jpeg", ".svg")) or "math" not in mf.lower(), (
                f"Equation was incorrectly rendered as a raster image: {mf}"
            )

        # Inspect word/document.xml
        doc_xml = z.read("word/document.xml").decode("utf-8")
        root = ET.fromstring(doc_xml)

        omaths = root.findall(".//m:oMath", MATH_NS)
        omathparas = root.findall(".//m:oMathPara", MATH_NS)

        # Must find genuine OMML elements
        assert len(omaths) >= 10, f"Expected at least 10 oMath elements, found {len(omaths)}"
        assert len(omathparas) >= 5, (
            f"Expected at least 5 oMathPara display elements, found {len(omathparas)}"
        )

        # Verify display oMathPara has centered alignment
        jc_elements = root.findall(".//m:oMathPara/m:oMathParaPr/m:jc", MATH_NS)
        assert len(jc_elements) >= 5, "Missing centered justification in oMathParaPr"
        for jc in jc_elements:
            assert (
                jc.attrib.get(f"{{{MATH_NS['m']}}}val") == "center"
                or jc.attrib.get("val") == "center"
            )


def test_inline_equations_remain_inside_sentence_paragraphs() -> None:
    """Verify inline equations (e.g. x, alpha, x_i) remain in the same paragraph as surrounding prose."""
    paper = _build_comprehensive_math_paper()
    docx_bytes = export_paper_docx(paper)

    with zipfile.ZipFile(io.BytesIO(docx_bytes)) as z:
        doc_xml = z.read("word/document.xml").decode("utf-8")
        root = ET.fromstring(doc_xml)

        # Find the long introductory paragraph
        found_inline_paragraph = False
        for p in root.findall(".//w:p", W_NS):
            text_runs = "".join(t.text or "" for t in p.findall(".//w:t", W_NS))
            if "In modern algorithmic information retrieval" in text_runs:
                omaths = p.findall(".//m:oMath", MATH_NS)
                assert len(omaths) >= 4, (
                    f"Expected multiple inline oMath elements in paragraph, found {len(omaths)}"
                )
                # Must NOT contain oMathPara (which is reserved for display math)
                omathparas = p.findall(".//m:oMathPara", MATH_NS)
                assert len(omathparas) == 0, (
                    "Inline paragraph incorrectly contained oMathPara display container"
                )
                found_inline_paragraph = True
                break

        assert found_inline_paragraph, "Introductory paragraph with inline math not found in DOCX"


def test_literal_latex_inside_code_blocks_is_not_converted() -> None:
    """Verify verbatim code blocks with LaTeX commands remain code and are NOT converted to OMML."""
    code_text = "Verbatim code:\n\n```latex\n\\newcommand{\\bm25}{\\sum_{i=1}^n x_i}\n```"
    blocks = parse_markdown_blocks(code_text)
    assert any(getattr(b, "language", "") == "latex" for b in blocks), (
        "Code block not parsed correctly"
    )

    paper = PaperDraft(
        schema_version=1,
        title="Code Block Test",
        abstract="Abstract",
        keywords=["Test"],
        author_info="Author",
        affiliation="Affiliation",
        page_layout="single_column",
        sections=[PaperSection(id="s1", heading="1. Code", content=code_text, state="draft")],
        references=[],
        review_warnings=[],
    )
    docx_bytes = export_paper_docx(paper)
    with zipfile.ZipFile(io.BytesIO(docx_bytes)) as z:
        doc_xml = z.read("word/document.xml").decode("utf-8")
        root = ET.fromstring(doc_xml)
        for p in root.findall(".//w:p", W_NS):
            runs = p.findall(".//w:r", W_NS)
            for r in runs:
                fonts = r.findall(".//w:rFonts", W_NS)
                if any(f.attrib.get(f"{{{W_NS['w']}}}ascii") == "Consolas" for f in fonts):
                    t_text = "".join(t.text or "" for t in r.findall(".//w:t", W_NS))
                    if "\\newcommand" in t_text:
                        # Ensure no oMath in this code block paragraph
                        assert len(p.findall(".//m:oMath", MATH_NS)) == 0


def test_two_column_academic_layout_preserves_omml_equations() -> None:
    """Verify that two-column academic DOCX layout correctly embeds OMML equations."""
    paper = _build_comprehensive_math_paper(layout="two_column_academic")
    docx_bytes = export_paper_docx(paper, layout="two_column_academic")

    with zipfile.ZipFile(io.BytesIO(docx_bytes)) as z:
        doc_xml = z.read("word/document.xml").decode("utf-8")
        root = ET.fromstring(doc_xml)

        omaths = root.findall(".//m:oMath", MATH_NS)
        omathparas = root.findall(".//m:oMathPara", MATH_NS)

        assert len(omaths) >= 10, "Two-column layout lost oMath equations"
        assert len(omathparas) >= 5, "Two-column layout lost oMathPara display equations"


def test_unsupported_math_syntax_resilient_fallback_omml() -> None:
    """Verify that malformed LaTeX math generates resilient OMML without throwing or crashing."""
    bad_math = r"$$\frac{unbalanced_brace{x$$"
    omml_xml, status, err = latex_to_omml_xml(bad_math, is_display=True)
    assert status == "error"
    assert err is not None
    # Must still parse cleanly as XML
    root = ET.fromstring(omml_xml)
    assert root.tag == f"{{{MATH_NS['m']}}}oMathPara"
    assert len(root.findall("./m:oMath", MATH_NS)) == 1


def test_pdf_export_succeeds_with_comprehensive_mathematics() -> None:
    """Verify PDF export runs without errors on all 20 mathematical constructs."""
    paper = _build_comprehensive_math_paper(layout="single_column")
    pdf_bytes = export_paper_pdf(paper, layout="single_column")
    assert len(pdf_bytes) > 2000
    assert pdf_bytes.startswith(b"%PDF-")
