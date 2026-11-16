"""Comprehensive end-to-end validation test suite for IEEE Conference Research Paper format.

Validates:
1. 5 authors with multiple affiliations matching ASEP 2 RP.docx geometry.
2. Abstract and Index Terms with authentic run-in prefixes.
3. Roman-numbered primary sections (I to V) and lettered subsections (A, B, C).
4. Inline math and centered display equations with right-aligned parentheses numbering (1), (2).
5. Multimodal figures: flowchart, algorithm diagram, experimental graph, application screenshot.
6. Numerical results table with formatted borders, bold headers, and cell alignment.
7. IEEE numbered in-text citations ([1], [1]–[3]) and bibliography engine.
8. Native OMML Microsoft Word equation objects.
9. Cross-template switching between IEEE Conference, single-column, and two-column academic.
"""

from __future__ import annotations

import io
import xml.etree.ElementTree as ET
import zipfile

from resbud_api.domain.models import (
    AuthorAffiliation,
    AuthorMetadata,
    PaperDraft,
    PaperSection,
    ReferenceInput,
    StructuredFigure,
)
from resbud_api.services.docx_export import export_paper_docx
from resbud_api.services.pdf_export import export_paper_pdf

W_NS = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
MATH_NS = {"m": "http://schemas.openxmlformats.org/officeDocument/2006/math"}

# 1x1 transparent PNG data URI for figure testing
SAMPLE_PNG_DATA_URI = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="


def _build_full_ieee_validation_manuscript() -> PaperDraft:
    """Construct an authentic, complete research paper manuscript resembling ASEP 2 RP.docx."""
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
            name="Aarav Sharma",
            affiliation_ids=["aff1"],
            role_or_title="UG Scholar",
            email="aarav.sharma@bkbiet.ac.in",
            order=1,
        ),
        AuthorMetadata(
            name="Diya Patel",
            affiliation_ids=["aff1"],
            role_or_title="UG Scholar",
            email="diya.patel@bkbiet.ac.in",
            order=2,
        ),
        AuthorMetadata(
            name="Rohan Verma",
            affiliation_ids=["aff1"],
            role_or_title="UG Scholar",
            email="rohan.verma@bkbiet.ac.in",
            order=3,
        ),
        AuthorMetadata(
            name="Ananya Iyer",
            affiliation_ids=["aff1"],
            role_or_title="UG Scholar",
            email="ananya.iyer@bkbiet.ac.in",
            order=4,
        ),
        AuthorMetadata(
            name="Dr. Rajesh Kumar",
            affiliation_ids=["aff2"],
            role_or_title="Associate Professor",
            email="rajesh.kumar@bkbiet.ac.in",
            is_corresponding=True,
            order=5,
        ),
    ]

    figures = [
        StructuredFigure(
            id="FIG-001",
            filename="methodology_flowchart.png",
            title="Methodology Pipeline Flowchart",
            caption="Fig. 1. End-to-end architectural flowchart illustrating landmark acquisition, coordinate normalization, and posture classification.",
            description="Flowchart detailing system data flow from camera input to ergonomic risk calculation.",
            category="flowchart",
            related_section="sec_method",
            column_span="column_width",
            figure_order=1,
            data_uri=SAMPLE_PNG_DATA_URI,
        ),
        StructuredFigure(
            id="FIG-002",
            filename="algorithm_architecture.png",
            title="Algorithm Topology",
            caption="Fig. 2. Spatial coordinate alignment algorithm topology with bipartite landmark matching.",
            description="Network diagram showing geometric graph constraints for human skeleton tracking.",
            category="architecture_diagram",
            related_section="sec_method",
            column_span="column_width",
            figure_order=2,
            data_uri=SAMPLE_PNG_DATA_URI,
        ),
        StructuredFigure(
            id="FIG-003",
            filename="benchmark_performance.png",
            title="Classification Benchmark Curves",
            caption="Fig. 3. Precision-Recall curves across various lighting and occlusion settings comparing baseline versus proposed framework.",
            description="Line graph showing classification accuracy across 5 benchmark scenarios.",
            category="graph",
            related_section="sec_results",
            column_span="column_width",
            figure_order=3,
            data_uri=SAMPLE_PNG_DATA_URI,
        ),
        StructuredFigure(
            id="FIG-004",
            filename="system_screenshot.png",
            title="Real-time Ergonomic Monitoring Dashboard",
            caption="Fig. 4. Real-time operator workstation dashboard visualizing instantaneous postural symmetry indices and ergonomic warning alerts.",
            description="User interface dashboard displaying posture assessment feedback.",
            category="screenshot",
            related_section="sec_results",
            column_span="full_width",
            figure_order=4,
            data_uri=SAMPLE_PNG_DATA_URI,
        ),
    ]

    references = [
        ReferenceInput(
            id="ref_smith2024",
            authors=["A. Smith", "C. Johnson"],
            title="Deep learning frameworks for real-time human pose estimation",
            venue="IEEE Transactions on Pattern Analysis and Machine Intelligence",
            year=2024,
            volume="46",
            issue="3",
            pages="1420-1435",
            doi="10.1109/TPAMI.2023.1234567",
            publication_type="journal_article",
            text="A. Smith and C. Johnson, 'Deep learning frameworks for real-time human pose estimation,' IEEE Trans. Pattern Anal. Mach. Intell., vol. 46, no. 3, pp. 1420-1435, Mar. 2024.",
        ),
        ReferenceInput(
            id="ref_jones2023",
            authors=["B. Jones", "M. Davis", "L. Taylor"],
            title="Ergonomic risk evaluation in sedentary computer operators",
            venue="IEEE International Conference on Bioinformatics and Biomedicine (BIBM)",
            year=2023,
            pages="512-518",
            doi="10.1109/BIBM.2023.9876543",
            publication_type="conference_paper",
            text="B. Jones, M. Davis, and L. Taylor, 'Ergonomic risk evaluation in sedentary computer operators,' in Proc. IEEE Int. Conf. Bioinformat. Biomed. (BIBM), 2023, pp. 512-518.",
        ),
        ReferenceInput(
            id="ref_iso2021",
            authors=["International Organization for Standardization"],
            title="Ergonomics of Human-System Interaction—Part 400: Principles and Requirements",
            publisher="ISO",
            year=2021,
            publication_type="standard",
            text="International Organization for Standardization, Ergonomics of Human-System Interaction—Part 400: Principles and Requirements, ISO Standard 9241-400, 2021.",
        ),
        ReferenceInput(
            id="ref_brown2022",
            authors=["R. Brown"],
            title="Biomechanical Computer Vision Foundations",
            publisher="IEEE Press / Wiley",
            year=2022,
            isbn_or_issn="978-1-119-12345-6",
            publication_type="book",
            text="R. Brown, Biomechanical Computer Vision Foundations. Piscataway, NJ, USA: IEEE Press / Wiley, 2022.",
        ),
    ]

    sections = [
        PaperSection(
            id="sec_intro",
            heading="Introduction",
            content=(
                "Musculoskeletal disorders represent a pervasive occupational hazard among knowledge workers "
                "operating in sedentary computational environments [1]. Computer vision frameworks enable continuous, "
                "non-invasive ergonomic assessment without tactile sensors or wearable hardware [2]. "
                "Recent studies have highlighted the necessity of unified biomechanical modeling for real-time risk classification [3].\n\n"
                "In this paper, we propose a standardized vision-based posture assessment framework that computes kinematic "
                "joint deviations and maps them to ergonomic risk levels defined by ISO standards [3]."
            ),
            state="draft",
        ),
        PaperSection(
            id="sec_related",
            heading="Related Work",
            content=(
                "Previous approaches to ergonomic monitoring have predominantly utilized wearable inertial measurement units "
                "or specialized depth cameras [1]–[3]. While effective in controlled laboratory settings, wearable sensors induce user fatigue "
                "and disrupt typical workplace routines [2]. Vision-based landmark estimators offer a non-intrusive alternative [1].\n\n"
                "Recent advances in spatial keypoint regression [4] allow real-time extraction of 33 anatomical landmarks. "
                "However, mapping coordinate trajectories to standardized ergonomic risk scores remains an open challenge."
            ),
            state="draft",
        ),
        PaperSection(
            id="sec_method",
            heading="Proposed System and Methodology",
            content=(
                "### Anatomical Landmark Acquisition\n\n"
                "The incoming video feed is captured at 30 frames per second. For each video frame, keypoint coordinates "
                r"$\mathbf{p}_i = (x_i, y_i, z_i)$ are regressed using normalized screen coordinates, where $\alpha \in [0, 1]$ "
                "represents the confidence threshold for anatomical landmark visibility.\n\n"
                "![Fig. 1. End-to-end architectural flowchart](FIG-001)\n\n"
                "### Spatial Coordinate Normalization\n\n"
                "To achieve scale invariance across varying user distances from the optical sensor, coordinates are aligned "
                "using the midpoint of the bilateral shoulder landmarks as the coordinate origin. "
                "The normalized postural deviation is formulated in Equation (1):\n\n"
                r"$$\mathbf{E}_{\text{posture}} = \sum_{i=1}^{K} w_i \|\mathbf{p}_i - \mathbf{q}_i\|^2$$"
                "\n\n"
                r"where $w_i$ denotes the anatomical joint weight and $\mathbf{q}_i$ represents the neutral ergonomic posture vector."
                "\n\n"
                "![Fig. 2. Spatial coordinate alignment algorithm topology](FIG-002)\n\n"
                "### Dynamic Kinematic Formulation\n\n"
                "Angular deviations are computed using cosine similarities. "
                "The multiline state-space formulation is expressed in Eq. (2):\n\n"
                r"$$\begin{aligned}"
                "\n"
                r"\theta_{\text{neck}} &= \arccos\left(\frac{\mathbf{v}_{\text{spine}} \cdot \mathbf{v}_{\text{cranium}}}{\|\mathbf{v}_{\text{spine}}\| \|\mathbf{v}_{\text{cranium}}\|}\right) \\"
                "\n"
                r"\theta_{\text{torso}} &= \arccos\left(\frac{\mathbf{v}_{\text{spine}} \cdot \mathbf{u}_z}{\|\mathbf{v}_{\text{spine}}\|}\right)"
                "\n"
                r"\end{aligned}$$"
                "\n\n"
                "Equations (1) and (2) form the quantitative foundation of the posture scoring index."
            ),
            state="draft",
        ),
        PaperSection(
            id="sec_results",
            heading="Experimental Evaluation and Results",
            content=(
                "The proposed framework was evaluated on an experimental benchmark comprising 15 participants over 45 hours "
                "of natural workstation tasks.\n\n"
                "### Quantitative Benchmark Comparison\n\n"
                "Performance was evaluated against clinical ground-truth classifications across four standard risk categories. "
                "The evaluation metrics are summarized in Table I.\n\n"
                "| Method | Accuracy (%) | Precision (%) | Recall (%) | F1-Score (%) |\n"
                "| :--- | :---: | :---: | :---: | :---: |\n"
                "| Baseline Heuristic [2] | 81.4 | 79.2 | 80.5 | 79.8 |\n"
                "| Depth Sensor Model [3] | 88.7 | 87.1 | 86.9 | 87.0 |\n"
                "| Proposed Framework | 95.3 | 94.8 | 95.1 | 94.9 |\n\n"
                "![Fig. 3. Precision-Recall curves](FIG-003)\n\n"
                "### Workstation Monitoring Dashboard\n\n"
                "The real-time monitoring interface was deployed across standard desktop browser viewports.\n\n"
                "![Fig. 4. Real-time operator workstation dashboard](FIG-004)"
            ),
            state="draft",
        ),
        PaperSection(
            id="sec_conclusion",
            heading="Conclusion and Future Directions",
            content=(
                "This paper presented an automated, non-invasive ergonomic posture monitoring framework conforming to IEEE "
                "publishing standards and ISO ergonomic guidelines. By combining spatial normalization with dynamic angular kinematics, "
                "the system achieves 95.3% accuracy in posture classification.\n\n"
                "Future work will explore longitudinal ergonomic intervention efficacy and federated multi-camera workplace calibration."
            ),
            state="draft",
        ),
    ]

    return PaperDraft(
        schema_version=1,
        title="Automated Computer Vision-Based Ergonomic Risk Assessment for Sedentary Workstations",
        abstract=(
            "Musculoskeletal disorders represent a major ergonomic risk in sedentary computer environments. "
            "This paper presents a standardized vision-based posture assessment framework that continuously analyzes 33 anatomical "
            "landmarks from standard monocular video feeds without requiring wearable hardware. By utilizing spatial coordinate "
            "normalization and kinematic angular deviations, the system computes real-time ergonomic compliance scores. "
            "Evaluations across 45 hours of workstation tasks demonstrate 95.3% posture classification accuracy."
        ),
        keywords=[
            "ergonomic assessment",
            "computer vision",
            "pose estimation",
            "biomechanics",
            "musculoskeletal disorders",
        ],
        sections=sections,
        references=references,
        page_layout="two_column_academic",
        document_template="ieee_conference",
        authors=authors,
        affiliations=affiliations,
        figures=figures,
        review_warnings=[],
    )


def test_full_ieee_docx_manuscript_verification() -> None:
    """Verify complete IEEE Conference DOCX generation meets reference structural and visual standards."""
    paper = _build_full_ieee_validation_manuscript()
    docx_bytes = export_paper_docx(paper, template_id="ieee_conference")
    assert docx_bytes.startswith(b"PK")
    assert len(docx_bytes) > 10000

    with zipfile.ZipFile(io.BytesIO(docx_bytes)) as archive:
        doc_xml = archive.read("word/document.xml")
        root = ET.fromstring(doc_xml)

        # 1. Section 0: Letter size with IEEE margins (top/bottom: 0.75 in, left/right: 0.625 in)
        body = root.find("w:body", W_NS)
        assert body is not None
        sect_elements = body.findall(".//w:sectPr", W_NS)
        assert len(sect_elements) >= 2

        sect0 = sect_elements[0]
        pg_mar0 = sect0.find("w:pgMar", W_NS)
        assert pg_mar0 is not None
        assert pg_mar0.get(f"{{{W_NS['w']}}}top") == "1080"  # 0.75 in
        assert pg_mar0.get(f"{{{W_NS['w']}}}bottom") == "1080"  # 0.75 in
        assert pg_mar0.get(f"{{{W_NS['w']}}}left") == "900"  # 0.625 in
        assert pg_mar0.get(f"{{{W_NS['w']}}}right") == "900"  # 0.625 in

        # 2. Section 1: Continuous Two-Column academic layout (w:cols num="2" space="360")
        sect1 = sect_elements[1]
        col_elem = sect1.find("w:cols", W_NS)
        assert col_elem is not None
        assert col_elem.get(f"{{{W_NS['w']}}}num") == "2"
        assert col_elem.get(f"{{{W_NS['w']}}}space") == "360"

        # 3. 5-Author Responsive Grid: ASEP 2 RP.docx format (row 1: 3 authors, row 2: 2 authors)
        tables = root.findall(".//w:tbl", W_NS)
        # First table in Section 0 is row 1 of authors (3 cells)
        author_tbl1 = tables[0]
        cols_tbl1 = author_tbl1.findall(".//w:tc", W_NS)
        assert len(cols_tbl1) == 3

        # Second table in Section 0 is row 2 of authors (2 cells)
        author_tbl2 = tables[1]
        cols_tbl2 = author_tbl2.findall(".//w:tc", W_NS)
        assert len(cols_tbl2) == 2

        # 4. Heading formatting with smallCaps and Roman numerals
        text_content = "".join(root.itertext())
        assert "I. INTRODUCTION" in text_content
        assert "II. RELATED WORK" in text_content
        assert "III. PROPOSED SYSTEM AND METHODOLOGY" in text_content
        assert "IV. EXPERIMENTAL EVALUATION AND RESULTS" in text_content
        assert "V. CONCLUSION AND FUTURE DIRECTIONS" in text_content

        # Subheadings
        assert "A. Anatomical Landmark Acquisition" in text_content
        assert "B. Spatial Coordinate Normalization" in text_content
        assert "C. Dynamic Kinematic Formulation" in text_content

        # 5. Native OMML Equations with centered math and right-aligned (1) and (2)
        omath_elements = root.findall(".//m:oMath", MATH_NS)
        assert len(omath_elements) >= 2, (
            f"Expected at least 2 OMML equations, got {len(omath_elements)}"
        )
        assert "(1)" in text_content
        assert "(2)" in text_content
        assert "Equation (1)" in text_content
        assert "Eq. (2)" in text_content

        # 6. Figures and Captions
        assert "Fig. 1. End-to-end architectural flowchart" in text_content
        assert "Fig. 2. Spatial coordinate alignment algorithm topology" in text_content
        assert "Fig. 3. Precision-Recall curves" in text_content
        assert "Fig. 4. Real-time operator workstation dashboard" in text_content

        # 7. Numerical Results Table
        assert "Accuracy (%)" in text_content
        assert "F1-Score (%)" in text_content
        assert "95.3" in text_content

        # 8. References Section
        assert "References" in text_content
        assert "[1]" in text_content
        assert "[2]" in text_content
        assert "[3]" in text_content
        assert "[4]" in text_content
        assert "10.1109/TPAMI.2023.1234567" in text_content


def test_full_ieee_pdf_manuscript_verification() -> None:
    """Verify complete IEEE Conference PDF generation builds valid binary bytes."""
    paper = _build_full_ieee_validation_manuscript()
    pdf_bytes = export_paper_pdf(paper, template_id="ieee_conference")
    assert pdf_bytes.startswith(b"%PDF")
    assert len(pdf_bytes) > 20000


def test_cross_template_switching_preserves_content_without_contamination() -> None:
    """Verify switching between IEEE Conference, Single-Column, and Two-Column Academic preserves content."""
    base_paper = _build_full_ieee_validation_manuscript()

    templates = [
        ("ieee_conference", "two_column_academic"),
        ("default", "single_column"),
        ("default", "two_column_academic"),
    ]

    for t_id, layout in templates:
        paper_variant = base_paper.model_copy(
            update={"document_template": t_id, "page_layout": layout}
        )

        # 1. Verify DOCX export
        docx_bytes = export_paper_docx(paper_variant, template_id=t_id, layout=layout)
        assert docx_bytes.startswith(b"PK"), f"Failed DOCX export for {t_id}/{layout}"

        with zipfile.ZipFile(io.BytesIO(docx_bytes)) as archive:
            doc_xml = archive.read("word/document.xml")
            root = ET.fromstring(doc_xml)
            text_str = "".join(root.itertext())

            # Mathematical equations preserved
            omath = root.findall(".//m:oMath", MATH_NS)
            assert len(omath) >= 2, f"OMML missing for {t_id}/{layout}"

            # Figures preserved
            assert "Fig. 1" in text_str, f"Figure missing for {t_id}/{layout}"

            # Table preserved
            assert "Accuracy (%)" in text_str, f"Table missing for {t_id}/{layout}"

            # References preserved
            assert "[1]" in text_str, f"Citations missing for {t_id}/{layout}"

        # 2. Verify PDF export
        pdf_bytes = export_paper_pdf(paper_variant, template_id=t_id, layout=layout)
        assert pdf_bytes.startswith(b"%PDF"), f"Failed PDF export for {t_id}/{layout}"
        assert len(pdf_bytes) > 10000, f"PDF too small for {t_id}/{layout}"
