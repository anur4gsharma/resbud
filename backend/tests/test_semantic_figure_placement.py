"""Comprehensive unit and regression tests for Semantic Figure Management and Intelligent IEEE Placement."""

import base64
from io import BytesIO

from docx import Document
from PIL import Image as PILImage

from resbud_api.domain.models import (
    PaperDraft,
    PaperSection,
    StructuredFigure,
)
from resbud_api.services.docx_export import export_paper_docx
from resbud_api.services.figure_analyzer import (
    analyze_figures,
    classify_figure_category,
    detect_duplicate_figures,
    infer_target_section,
)
from resbud_api.services.figure_distributor import distribute_and_reindex_figures
from resbud_api.services.figure_planner import clean_ieee_caption_text, plan_figure_placements
from resbud_api.services.pdf_export import export_paper_pdf


def _make_dummy_image_data_uri(
    fmt: str = "PNG",
    color: tuple[int, int, int] = (100, 150, 200),
    width: int = 120,
    height: int = 90,
) -> str:
    img = PILImage.new("RGB", (width, height), color=color)
    buf = BytesIO()
    img.save(buf, format=fmt)
    b64 = base64.b64encode(buf.getvalue()).decode("ascii")
    mime = "image/png" if fmt.upper() == "PNG" else "image/jpeg"
    return f"data:{mime};base64,{b64}"


def test_structured_figure_model_fields_and_defaults() -> None:
    fig = StructuredFigure(
        id="FIG-001",
        filename="methodology_flowchart.png",
        caption="Overview of proposed methodology.",
        width=800,
        height=600,
    )
    assert fig.id == "FIG-001"
    assert fig.filename == "methodology_flowchart.png"
    assert fig.caption == "Overview of proposed methodology."
    assert fig.category == "other"
    assert fig.column_span == "column_width"
    assert fig.preferred_placement == "after_paragraph"
    assert fig.figure_order == 1
    assert fig.referenced_in_text is False
    assert fig.placement_status == "unplaced"


def test_multimodal_analysis_categorization() -> None:
    flowchart_fig = StructuredFigure(
        id="FIG-001",
        filename="process_pipeline_flowchart.png",
        caption="Flowchart illustrating data preprocessing and feature extraction.",
    )
    arch_fig = StructuredFigure(
        id="FIG-002",
        filename="system_architecture_diagram.png",
        caption="High-level architecture of the neural network framework.",
    )
    graph_fig = StructuredFigure(
        id="FIG-003",
        filename="roc_loss_curve.png",
        caption="Loss convergence curve and ROC distribution.",
    )
    screenshot_fig = StructuredFigure(
        id="FIG-004",
        filename="mobile_app_interface.png",
        caption="User interface screenshot of the deployed mobile application.",
    )

    assert classify_figure_category(flowchart_fig) == "flowchart"
    assert classify_figure_category(arch_fig) == "architecture_diagram"
    assert classify_figure_category(graph_fig) == "graph"
    assert classify_figure_category(screenshot_fig) == "screenshot"


def test_multimodal_analysis_section_mapping() -> None:
    available_sections = ["introduction", "methodology", "results", "discussion", "conclusion"]

    flowchart_fig = StructuredFigure(
        id="FIG-001",
        filename="flowchart.png",
        caption="Methodology flowchart",
    )
    graph_fig = StructuredFigure(
        id="FIG-002",
        filename="results_accuracy.png",
        caption="Benchmark performance comparison",
    )

    assert infer_target_section(flowchart_fig, available_sections) == "methodology"
    assert infer_target_section(graph_fig, available_sections) == "results"


def test_duplicate_figure_detection() -> None:
    uri = _make_dummy_image_data_uri()
    fig1 = StructuredFigure(
        id="FIG-001",
        filename="chart.png",
        caption="Figure 1: Benchmark chart",
        data_uri=uri,
    )
    fig2 = StructuredFigure(
        id="FIG-002",
        filename="chart_copy.png",
        caption="Figure 2: Duplicate chart",
        data_uri=uri,
    )

    analyzed = detect_duplicate_figures([fig1, fig2])
    assert len(analyzed) == 2
    assert analyzed[0].placement_status == "unplaced"
    assert analyzed[1].placement_status == "omitted"
    assert "duplicate of figure fig-001" in analyzed[1].placement_rationale.lower()


def test_ambiguous_figure_flagged_for_user_review() -> None:
    ambiguous_fig = StructuredFigure(
        id="FIG-099",
        filename="IMG_9999.jpg",
        caption="Image",
        description="",
    )
    analyzed = analyze_figures([ambiguous_fig], available_sections=["methodology", "results"])
    assert analyzed[0].placement_status == "unplaced"
    assert "user review" in analyzed[0].placement_rationale.lower()


def test_figure_placement_planning_anti_bundling() -> None:
    figures = [
        StructuredFigure(id="FIG-001", filename="flowchart.png", caption="Flowchart"),
        StructuredFigure(id="FIG-002", filename="algorithm.png", caption="Algorithm"),
        StructuredFigure(id="FIG-003", filename="chart.png", caption="Results chart"),
        StructuredFigure(id="FIG-004", filename="app_screen.png", caption="Mobile app"),
    ]
    analyzed = analyze_figures(figures, available_sections=["methodology", "results"])
    planned = plan_figure_placements(analyzed, section_ids=["methodology", "results"])

    method_figs = [f for f in planned if f.related_section == "methodology"]
    results_figs = [f for f in planned if f.related_section == "results"]

    # Invariant: figures are balanced across sections, not bundled into one!
    assert len(method_figs) >= 1
    assert len(results_figs) >= 1
    assert len(method_figs) + len(results_figs) == 4

    # IEEE caption prefix
    assert planned[0].caption.startswith("Fig. 1. ")
    assert planned[1].caption.startswith("Fig. 2. ")
    assert planned[2].caption.startswith("Fig. 3. ")
    assert planned[3].caption.startswith("Fig. 4. ")


def test_clean_ieee_caption_text() -> None:
    assert clean_ieee_caption_text("Figure 1: Overview") == "Overview"
    assert clean_ieee_caption_text("Fig. 2. Convergence plot") == "Convergence plot"
    assert clean_ieee_caption_text("Fig 3: Architecture") == "Architecture"
    assert clean_ieee_caption_text("System Overview") == "System Overview"


def test_distribute_and_reindex_figures_contextual_insertion() -> None:
    draft = PaperDraft(
        schema_version=1,
        title="Smart Posture Analysis",
        abstract="Abstract content.",
        keywords=["posture", "cv"],
        sections=[
            PaperSection(
                id="methodology",
                heading="Methodology",
                content=(
                    "This paragraph details the data acquisition protocol and sensor configurations.\n\n"
                    "The second paragraph formalizes mathematical transformations and metric derivations."
                ),
                state="draft",
            ),
            PaperSection(
                id="results",
                heading="Results",
                content=(
                    "Quantitative evaluation benchmarked the proposed method against three standard baselines.\n\n"
                    "Statistical significance testing confirmed substantial accuracy improvements."
                ),
                state="draft",
            ),
        ],
        references=[],
        review_warnings=[],
        figures=[
            StructuredFigure(
                id="FIG-001",
                filename="methodology_flowchart.png",
                caption="Overview of the methodology pipeline.",
                category="flowchart",
                related_section="methodology",
            ),
            StructuredFigure(
                id="FIG-002",
                filename="benchmark_chart.png",
                caption="Empirical accuracy comparison.",
                category="graph",
                related_section="results",
            ),
        ],
    )

    distributed = distribute_and_reindex_figures(draft)

    # Invariant: FIG-001 is injected into methodology, FIG-002 into results
    method_content = distributed.sections[0].content
    results_content = distributed.sections[1].content

    assert "![Fig. 1. Overview of the methodology pipeline.](FIG-001)" in method_content
    assert "![Fig. 2. Empirical accuracy comparison.](FIG-002)" in results_content

    # Invariant: preceding introductory prose is weaved
    assert "Fig. 1" in method_content
    assert "Fig. 2" in results_content

    # Invariant: figures updated in paper.figures
    assert distributed.figures[0].figure_order == 1
    assert distributed.figures[0].placement_status == "assigned"
    assert distributed.figures[0].referenced_in_text is True

    assert distributed.figures[1].figure_order == 2
    assert distributed.figures[1].placement_status == "assigned"
    assert distributed.figures[1].referenced_in_text is True


def test_six_figure_regression_manuscript() -> None:
    """Rigorous test with user's specified 6-figure manuscript:
    1 methodology flowchart, 1 algorithm diagram, 1 experimental chart,
    2 application screenshots, 1 architecture diagram.
    """
    six_figures = [
        StructuredFigure(
            id="FIG-001",
            filename="methodology_flowchart.png",
            title="Methodology Sequence",
            caption="Overview of the end-to-end processing pipeline.",
            category="flowchart",
            data_uri=_make_dummy_image_data_uri(color=(10, 20, 30)),
        ),
        StructuredFigure(
            id="FIG-002",
            filename="algorithm_block_diagram.png",
            title="Posture Classification Algorithm",
            caption="Algorithmic pipeline for landmark triangulation.",
            category="flowchart",
            data_uri=_make_dummy_image_data_uri(color=(40, 50, 60)),
        ),
        StructuredFigure(
            id="FIG-003",
            filename="experimental_chart.png",
            title="Classification Accuracy Chart",
            caption="Comparison of classification accuracy across subject cohorts.",
            category="graph",
            data_uri=_make_dummy_image_data_uri(color=(70, 80, 90)),
        ),
        StructuredFigure(
            id="FIG-004",
            filename="app_screenshot_realtime.png",
            title="Real-Time Feedback Interface",
            caption="Mobile application interface displaying real-time posture feedback.",
            category="screenshot",
            data_uri=_make_dummy_image_data_uri(color=(100, 110, 120)),
        ),
        StructuredFigure(
            id="FIG-005",
            filename="app_screenshot_history.png",
            title="Historical Analytics View",
            caption="Mobile application interface displaying historical ergonomic analytics.",
            category="screenshot",
            data_uri=_make_dummy_image_data_uri(color=(130, 140, 150)),
        ),
        StructuredFigure(
            id="FIG-006",
            filename="system_architecture_diagram.png",
            title="System Architecture Diagram",
            caption="Broad edge-to-cloud distributed architecture diagram.",
            description="Broad distributed hardware and cloud infrastructure architecture.",
            category="architecture_diagram",
            data_uri=_make_dummy_image_data_uri(color=(160, 170, 180)),
        ),
    ]

    analyzed = analyze_figures(six_figures, available_sections=["methodology", "results"])
    planned = plan_figure_placements(analyzed, section_ids=["methodology", "results"])

    # 1. Architecture diagram should have full_width due to 'broad' description
    arch = next(f for f in planned if f.id == "FIG-006")
    assert arch.column_span == "full_width"

    # 2. Check sequential numbers
    for i, fig in enumerate(planned, start=1):
        assert fig.figure_order == i
        assert fig.caption.startswith(f"Fig. {i}. ")

    # 3. Create manuscript draft and distribute
    paper = PaperDraft(
        schema_version=1,
        title="Comprehensive Posture Assessment Framework",
        abstract="An empirical investigation into ergonomic computer vision posture classification.",
        keywords=["ergonomics", "computer vision", "posture classification"],
        document_template="ieee_conference",
        page_layout="two_column_academic",
        sections=[
            PaperSection(
                id="methodology",
                heading="Methodology",
                content=(
                    "The proposed methodological protocol captures visual input and tracks skeletal landmarks.\n\n"
                    "Feature vectors are constructed from geometric angles and normalized against anthropometric ratios.\n\n"
                    "The classification model processes temporal feature windows using multi-head attention."
                ),
                state="draft",
            ),
            PaperSection(
                id="results",
                heading="Results",
                content=(
                    "Empirical validation evaluated classification performance across 50 diverse participants.\n\n"
                    "The mobile application deployment was validated for real-time inference latency.\n\n"
                    "Longitudinal analysis demonstrated sustained user engagement and posture improvement."
                ),
                state="draft",
            ),
        ],
        references=[],
        review_warnings=[],
        figures=planned,
    )

    distributed_paper = distribute_and_reindex_figures(paper)

    # Invariant: All 6 figures are assigned and embedded
    assert len(distributed_paper.figures) == 6
    assert all(f.placement_status == "assigned" for f in distributed_paper.figures)
    assert all(f.referenced_in_text for f in distributed_paper.figures)

    # Invariant: Neither section contains all 6 figures (Anti-bundling!)
    m_count = distributed_paper.sections[0].content.count("![Fig.")
    r_count = distributed_paper.sections[1].content.count("![Fig.")
    assert m_count > 0
    assert r_count > 0
    assert m_count + r_count == 6

    # Invariant: Both DOCX and PDF export succeed without crashing
    docx_bytes = export_paper_docx(distributed_paper)
    assert docx_bytes.startswith(b"PK")

    pdf_bytes = export_paper_pdf(distributed_paper)
    assert pdf_bytes.startswith(b"%PDF-")

    # Invariant: In-text citations and captions present in exported DOCX
    doc = Document(BytesIO(docx_bytes))
    docx_text = "\n".join(p.text for p in doc.paragraphs)
    for i in range(1, 7):
        assert f"Fig. {i}" in docx_text
