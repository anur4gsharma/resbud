"""Test suite for IEEE Conference Research Paper template formatting and export."""

from __future__ import annotations

import io
import json
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

import httpx
from fastapi import FastAPI

from resbud_api.core.settings import Settings
from resbud_api.domain.models import AuthorAffiliation, AuthorMetadata, PaperDraft, PaperSection
from resbud_api.main import create_app
from resbud_api.services.docx_export import export_paper_docx
from resbud_api.services.pdf_export import export_paper_pdf
from resbud_api.templates.ieee_conference import (
    calculate_ieee_author_grid,
    format_ieee_heading_1,
    format_ieee_heading_2,
    format_ieee_heading_3,
    int_to_letter,
    int_to_roman,
    validate_author_metadata,
)
from resbud_api.templates.registry import get_template, list_templates

FIXTURES = Path(__file__).parent / "fixtures"
PAPER_DATA = json.loads((FIXTURES / "paper-draft.valid.json").read_text())

W_NS = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
MATH_NS = {"m": "http://schemas.openxmlformats.org/officeDocument/2006/math"}


def _app() -> FastAPI:
    return create_app(Settings(environment="test", _env_file=None))


def test_ieee_template_registry() -> None:
    """Verify IEEE Conference template is registered and exposes expected configuration."""
    template = get_template("ieee_conference")
    assert template.template_id == "ieee_conference"
    assert template.display_name == "IEEE Conference Paper"
    assert template.category == "Academic Research"
    assert template.default_page_layout == "two_column_academic"
    assert template.default_citation_format == "ieee"
    assert template.default_equation_format == "omml"
    assert template.column_count == 2
    assert template.column_gap_inch == 0.25
    assert template.margins.top == 0.75
    assert template.margins.bottom == 0.75
    assert template.margins.left == 0.625
    assert template.margins.right == 0.625
    assert template.default_typography.font_family == "Times New Roman"
    assert template.default_typography.body_size_pt == 10.0

    # Default fallback
    fallback = get_template("non_existent_template")
    assert fallback.template_id == "default"

    all_templates = list_templates()
    template_ids = [t.template_id for t in all_templates]
    assert "ieee_conference" in template_ids
    assert "default" in template_ids


def test_ieee_roman_and_letter_numbering() -> None:
    """Verify Roman and alphabetical numeral conversions."""
    expected_romans = [
        (1, "I"),
        (2, "II"),
        (3, "III"),
        (4, "IV"),
        (5, "V"),
        (6, "VI"),
        (7, "VII"),
        (8, "VIII"),
        (9, "IX"),
        (10, "X"),
        (11, "XI"),
        (14, "XIV"),
        (19, "XIX"),
        (20, "XX"),
    ]
    for num, expected in expected_romans:
        assert int_to_roman(num) == expected

    expected_letters = [
        (1, "A"),
        (2, "B"),
        (3, "C"),
        (26, "Z"),
        (27, "AA"),
        (28, "AB"),
    ]
    for num, expected in expected_letters:
        assert int_to_letter(num) == expected


def test_ieee_heading_formatting() -> None:
    """Verify heading hierarchy formatting according to IEEE standard conventions."""
    # Heading 1: Roman numerals, uppercase
    assert format_ieee_heading_1(1, "Introduction") == "I. INTRODUCTION"
    assert format_ieee_heading_1(2, "Related Work") == "II. RELATED WORK"
    assert (
        format_ieee_heading_1(3, "Proposed System and Methodology")
        == "III. PROPOSED SYSTEM AND METHODOLOGY"
    )

    # Unnumbered sections
    assert format_ieee_heading_1(4, "References") == "REFERENCES"
    assert format_ieee_heading_1(5, "Reference") == "REFERENCES"
    assert format_ieee_heading_1(6, "Acknowledgment") == "ACKNOWLEDGMENT"
    assert format_ieee_heading_1(7, "acknowledgments") == "ACKNOWLEDGMENTS"

    # Heading 2: Lettered, title case
    assert format_ieee_heading_2(1, "Image Acquisition") == "A. Image Acquisition"
    assert format_ieee_heading_2(2, "Human Pose Estimation") == "B. Human Pose Estimation"

    # Heading 3: Numbered with parentheses and colon
    assert format_ieee_heading_3(1, "Camera Calibration") == "1) Camera Calibration:"
    assert format_ieee_heading_3(2, "Feature Matching") == "2) Feature Matching:"


def test_ieee_author_grid_calculations() -> None:
    """Verify author grid dimensions and row counts for 1 to 10 authors."""
    assert calculate_ieee_author_grid(1) == [1]
    assert calculate_ieee_author_grid(2) == [2]
    assert calculate_ieee_author_grid(3) == [3]
    assert calculate_ieee_author_grid(4) == [2, 2]
    # 5 authors: replicates ASEP 2 RP.docx (row 1: 3 authors, row 2: 2 authors)
    assert calculate_ieee_author_grid(5) == [3, 2]
    assert calculate_ieee_author_grid(6) == [3, 3]
    assert calculate_ieee_author_grid(7) == [4, 3]
    assert calculate_ieee_author_grid(8) == [4, 4]
    assert calculate_ieee_author_grid(9) == [3, 3, 3]
    assert calculate_ieee_author_grid(10) == [4, 3, 3]


def test_author_metadata_validation() -> None:
    """Ensure author metadata validation catches missing required fields without fabricating."""
    # Empty author list
    empty_warnings = validate_author_metadata([])
    assert len(empty_warnings) == 1
    assert "No authors supplied" in empty_warnings[0]

    # Incomplete author details
    incomplete_authors = [
        {"name": "", "institution": "Stanford University", "email": "test@stanford.edu"},
        {"name": "Jane Doe", "department": "", "institution": "", "email": "jane@example.com"},
        {"name": "John Smith", "institution": "MIT", "email": ""},
    ]
    warnings = validate_author_metadata(incomplete_authors)
    assert any("Author #1 is missing a required name" in w for w in warnings)
    assert any("Author 'Jane Doe' is missing institutional affiliation" in w for w in warnings)
    assert any("Author 'John Smith' is missing an email address" in w for w in warnings)


def _build_ieee_test_paper() -> PaperDraft:
    """Build a realistic 5-author paper matching the structure of ASEP 2 RP.docx."""
    affiliations = [
        AuthorAffiliation(
            id="aff1",
            department="Dept. of Information Technology",
            institution="B.K. Birla Institute of Engineering & Technology",
            city="Pilani",
            country="India",
        ),
        AuthorAffiliation(
            id="aff2",
            department="Dept. of Computer Science & Engineering",
            institution="B.K. Birla Institute of Engineering & Technology",
            city="Pilani",
            country="India",
        ),
    ]

    authors = [
        AuthorMetadata(
            name="Author One",
            affiliation_ids=["aff1"],
            role_or_title="UG Student",
            email="author1@example.com",
            order=1,
        ),
        AuthorMetadata(
            name="Author Two",
            affiliation_ids=["aff1"],
            role_or_title="UG Student",
            email="author2@example.com",
            order=2,
        ),
        AuthorMetadata(
            name="Author Three",
            affiliation_ids=["aff1"],
            role_or_title="UG Student",
            email="author3@example.com",
            order=3,
        ),
        AuthorMetadata(
            name="Author Four",
            affiliation_ids=["aff1"],
            role_or_title="UG Student",
            email="author4@example.com",
            order=4,
        ),
        AuthorMetadata(
            name="Author Five",
            affiliation_ids=["aff2"],
            role_or_title="Assistant Professor",
            email="author5@example.com",
            is_corresponding=True,
            order=5,
        ),
    ]

    sections = [
        PaperSection(
            id="sec_intro",
            heading="Introduction",
            content=(
                "Human posture analysis is an active field in computer vision. "
                "In this paper, we evaluate postural symmetry."
            ),
            state="draft",
        ),
        PaperSection(
            id="sec_method",
            heading="Methodology",
            content=(
                "### Feature Extraction\n\n"
                "The keypoint coordinates are normalized using scale factor $\\alpha \\in [0, 1]$. "
                "The display formulation is given by:\n\n"
                r"$$\mathbf{E} = \sum_{i=1}^{K} \|\mathbf{p}_i - \mathbf{q}_i\|^2$$"
                "\n\n"
                "#### Coordinate Normalization\n\n"
                "Coordinates are aligned using centroid subtraction."
            ),
            state="draft",
        ),
        PaperSection(
            id="sec_results",
            heading="Results and Analysis",
            content="Quantitative evaluations demonstrate high posture detection fidelity.",
            state="draft",
        ),
        PaperSection(
            id="sec_refs",
            heading="References",
            content="[1] A. Smith, 'Posture estimation algorithms,' IEEE Trans. PAMI, 2024.\n[2] B. Jones, 'Deep biomechanics,' IEEE Access, 2023.",
            state="draft",
        ),
    ]

    return PaperDraft(
        schema_version=1,
        title="Automated Posture Analysis and Ergonomic Risk Assessment",
        abstract="Musculoskeletal disorders represent a major ergonomic risk in sedentary environments.",
        keywords=["pose estimation", "ergonomics", "computer vision", "biomechanics"],
        sections=sections,
        references=[],
        page_layout="two_column_academic",
        document_template="ieee_conference",
        authors=authors,
        affiliations=affiliations,
        review_warnings=[],
    )


def test_ieee_docx_export_replicates_reference_geometry() -> None:
    """Verify DOCX export conforms to IEEE conference geometry, author tables, headings, and OMML."""
    paper = _build_ieee_test_paper()
    docx_bytes = export_paper_docx(paper, template_id="ieee_conference")
    assert docx_bytes.startswith(b"PK")

    with zipfile.ZipFile(io.BytesIO(docx_bytes)) as archive:
        doc_xml = archive.read("word/document.xml")
        root = ET.fromstring(doc_xml)

        # 1. Verify two sections: Section 0 (single column, Letter), Section 1 (continuous 2-column)
        body = root.find("w:body", W_NS)
        assert body is not None

        # Look for sectPr in body
        sect_elements = body.findall(".//w:sectPr", W_NS)
        assert len(sect_elements) >= 2, f"Expected at least 2 sections, found {len(sect_elements)}"

        # Check section 0 properties (title & author section)
        sect0 = sect_elements[0]
        pg_sz0 = sect0.find("w:pgSz", W_NS)
        assert pg_sz0 is not None
        # Letter width: 12240 dxa, height: 15840 dxa
        assert pg_sz0.get(f"{{{W_NS['w']}}}w") == "12240"
        assert pg_sz0.get(f"{{{W_NS['w']}}}h") == "15840"

        pg_mar0 = sect0.find("w:pgMar", W_NS)
        assert pg_mar0 is not None
        # Margins: top/bottom 0.75 in (1080 dxa), left/right 0.625 in (900 dxa)
        assert pg_mar0.get(f"{{{W_NS['w']}}}top") == "1080"
        assert pg_mar0.get(f"{{{W_NS['w']}}}bottom") == "1080"
        assert pg_mar0.get(f"{{{W_NS['w']}}}left") == "900"
        assert pg_mar0.get(f"{{{W_NS['w']}}}right") == "900"

        # Check section 1 properties (body section): 2 columns, space=360 (0.25 in)
        sect1 = sect_elements[-1]
        cols1 = sect1.find("w:cols", W_NS)
        assert cols1 is not None
        assert cols1.get(f"{{{W_NS['w']}}}num") == "2"
        assert cols1.get(f"{{{W_NS['w']}}}space") == "360"

        # 2. Verify author tables: 5 authors -> 2 tables (row 1: 3 cols, row 2: 2 cols)
        tables = body.findall("w:tbl", W_NS)
        assert len(tables) >= 2, f"Expected at least 2 author tables, found {len(tables)}"

        table0 = tables[0]
        grid0 = table0.find("w:tblGrid", W_NS)
        assert grid0 is not None
        cols0 = grid0.findall("w:gridCol", W_NS)
        assert len(cols0) == 3
        for col in cols0:
            assert col.get(f"{{{W_NS['w']}}}w") == "3480"

        table1 = tables[1]
        grid1 = table1.find("w:tblGrid", W_NS)
        assert grid1 is not None
        cols1_tbl = grid1.findall("w:gridCol", W_NS)
        assert len(cols1_tbl) == 2
        for col in cols1_tbl:
            assert col.get(f"{{{W_NS['w']}}}w") == "5220"

        # Borderless tables
        for tbl in (table0, table1):
            pr = tbl.find("w:tblPr", W_NS)
            assert pr is not None
            tbl_borders = pr.find("w:tblBorders", W_NS)
            assert tbl_borders is not None
            top_b = tbl_borders.find("w:top", W_NS)
            assert top_b is not None
            assert top_b.get(f"{{{W_NS['w']}}}val") in ("none", "nil")

        # 3. Verify Abstract— and Index Terms— run-in styles
        all_text = "".join(root.itertext())
        assert "Abstract—" in all_text
        assert "Index Terms—" in all_text

        # 4. Verify Heading formatting: Roman numerals, small caps
        assert "I. INTRODUCTION" in all_text
        assert "II. METHODOLOGY" in all_text
        assert "A. Feature Extraction" in all_text
        assert "1) Coordinate Normalization:" in all_text
        assert "References" in all_text
        # Ensure REFERENCES is NOT numbered as "IV. REFERENCES"
        assert "IV. REFERENCES" not in all_text
        assert "IV. References" not in all_text

        # 5. Verify Native OMML math is present
        math_elements = root.findall(".//m:oMath", MATH_NS)
        assert len(math_elements) >= 2, (
            f"Expected native OMML equations, found {len(math_elements)}"
        )


def test_ieee_export_api_endpoints() -> None:
    """Verify DOCX and PDF export endpoints with IEEE conference template parameter."""
    app = _app()
    paper = _build_ieee_test_paper()
    payload = paper.model_dump(mode="json")

    async def run_calls() -> None:
        transport = httpx.ASGITransport(app=app, raise_app_exceptions=False)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            # 1. DOCX export
            docx_resp = await client.post(
                "/api/v1/exports/docx?template=ieee_conference", json=payload
            )
            assert docx_resp.status_code == 200
            assert docx_resp.headers["content-type"] == (
                "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            )
            assert docx_resp.content.startswith(b"PK")

            # 2. PDF export
            pdf_resp = await client.post(
                "/api/v1/exports/pdf?template=ieee_conference", json=payload
            )
            assert pdf_resp.status_code == 200
            assert pdf_resp.headers["content-type"] == "application/pdf"
            assert pdf_resp.content.startswith(b"%PDF-")

    import asyncio

    asyncio.run(run_calls())


def test_ieee_pdf_export_service() -> None:
    """Verify PDF export service renders valid PDF for IEEE conference paper."""
    paper = _build_ieee_test_paper()
    pdf_bytes = export_paper_pdf(paper, template_id="ieee_conference")
    assert pdf_bytes.startswith(b"%PDF-")
    assert len(pdf_bytes) > 1000
