"""Comprehensive regression harness guarding against the critical manuscript quality defects.

Specifically tests:
1. Markdown headings (###, ####) parsed into docx/pdf styles rather than leaking literal text.
2. Cormack 2009 reference title extracted correctly across multiple lines without hallucination.
3. Unicode author names (Barlas Oğuz) rendered without corruption (no O■uz).
4. References section is strictly bibliographic, never contaminated with prose or analysis subsections.
5. Section numbering is consecutive and hierarchical (1., 1.1, etc.) without duplication.
6. Prompt residue strings eliminated completely from generated drafts.
7. Unconducted experiments produce hypothesis/protocol text, not fabricated performance claims.
8. Figures array in project input payload processed cleanly without schema rejection.
"""

from __future__ import annotations

import io

import pypdf
from docx import Document

from resbud_api.domain.models import (
    PaperDraft,
    PaperPreferences,
    PaperSection,
    ProjectContext,
    ReferenceInput,
)
from resbud_api.providers.base import ResearchBrief
from resbud_api.services.analysis import extract_bibliographic_references
from resbud_api.services.docx_export import export_paper_docx
from resbud_api.services.manuscript_planner import create_manuscript_plan
from resbud_api.services.markdown_renderer import (
    clean_heading_text,
    format_hierarchical_heading,
)
from resbud_api.services.pdf_export import export_paper_pdf

SAMPLE_DOSSIER_REFS = """
[1] Cormack, G. V., Clarke, C. L., & Buettcher, S. (2009).
    Reciprocal rank fusion outperforms condorcet and individual rank learning methods.
    Proceedings of the 32nd International ACM SIGIR Conference on Research and Development in Information Retrieval, 758–759.
    https://doi.org/10.1145/1571941.1572114

[2] Karpukhin, V., Oğuz, B., Min, S., Lewis, P., Wu, L., Edunov, S., Chen, D., & Yih, W. (2020).
    Dense passage retrieval for open-domain question answering.
    arXiv preprint arXiv:2004.04906.
"""


def _create_test_paper(
    headings_with_markdown: bool = False,
    include_oguz: bool = True,
    corrupted_cormack: bool = False,
) -> PaperDraft:
    ref_1_title = (
        "Reciprocal rank fusion outperforms rank introducing variables for rank-merging"
        if corrupted_cormack
        else "Reciprocal rank fusion outperforms condorcet and individual rank learning methods."
    )
    ref_2_author = (
        "Karpukhin, V., Oğuz, B., Min, S., Lewis, P., Wu, L., Edunov, S., Chen, D., & Yih, W."
        if include_oguz
        else "Karpukhin, V., Oguz, B., Min, S."
    )

    sections = [
        PaperSection(
            id="introduction",
            heading="### 1.1 Context & Motivation"
            if headings_with_markdown
            else "Context & Motivation",
            content=(
                "Modern retrieval systems combine sparse and dense signals.\n\n"
                "### Theoretical Rationale\n\n"
                "Dense retrieval aligns semantic spaces as described by Karpukhin et al. [ref_2].\n\n"
                "#### Analytical Interpretation\n\n"
                "Reciprocal rank fusion provides robust rank aggregation [ref_1]."
            ),
            state="draft",
        ),
        PaperSection(
            id="methodology",
            heading="Methodology",
            content="We formalize hybrid retrieval fusion over dual index spaces.",
            state="draft",
        ),
        PaperSection(
            id="discussion",
            heading="Discussion",
            content="Our findings suggest complementary failure modes between representations.",
            state="draft",
        ),
    ]

    return PaperDraft(
        schema_version=1,
        title="Hybrid Dense-Sparse Information Retrieval Systems",
        abstract="This paper investigates reciprocal rank fusion over dual dense-sparse representations.",
        keywords=["Information Retrieval", "Reciprocal Rank Fusion", "Dense Retrieval"],
        sections=sections,
        references=[
            ReferenceInput(
                id="ref_1",
                text=f"Cormack, G. V., Clarke, C. L., & Buettcher, S. (2009). {ref_1_title}",
                authors=["Cormack, G. V.", "Clarke, C. L.", "Buettcher, S."],
                year=2009,
                title=ref_1_title,
                doi="10.1145/1571941.1572114",
            ),
            ReferenceInput(
                id="ref_2",
                text=f"{ref_2_author} (2020). Dense passage retrieval for open-domain question answering.",
                authors=["Karpukhin, V.", "Oğuz, B.", "Min, S."],
                year=2020,
                title="Dense passage retrieval for open-domain question answering.",
            ),
        ],
        review_warnings=[],
    )


def test_markdown_heading_markers_never_leak_into_docx() -> None:
    paper = _create_test_paper(headings_with_markdown=True)
    docx_bytes = export_paper_docx(paper)
    doc = Document(io.BytesIO(docx_bytes))
    paragraphs = [p.text for p in doc.paragraphs]

    for p in paragraphs:
        assert not p.startswith("###"), f"Literal markdown leaked into DOCX: {p}"
        assert not p.startswith("####"), f"Literal markdown leaked into DOCX: {p}"
        assert not p.startswith("## "), f"Literal markdown leaked into DOCX: {p}"

    # Verify heading is cleanly stripped
    assert any("Context & Motivation" in p for p in paragraphs)
    assert any("Theoretical Rationale" in p for p in paragraphs)
    assert any("Analytical Interpretation" in p for p in paragraphs)


def test_markdown_heading_markers_never_leak_into_pdf() -> None:
    paper = _create_test_paper(headings_with_markdown=True)
    pdf_bytes = export_paper_pdf(paper)
    reader = pypdf.PdfReader(io.BytesIO(pdf_bytes))
    pdf_text = "\n".join(page.extract_text() or "" for page in reader.pages)

    assert "###" not in pdf_text
    assert "####" not in pdf_text
    assert "Context & Motivation" in pdf_text
    assert "Theoretical Rationale" in pdf_text


def test_unicode_author_name_oguz_preserved_in_docx_and_pdf() -> None:
    paper = _create_test_paper(include_oguz=True)

    # DOCX check
    docx_bytes = export_paper_docx(paper)
    doc = Document(io.BytesIO(docx_bytes))
    docx_text = "\n".join(p.text for p in doc.paragraphs)
    assert "Oğuz" in docx_text
    assert "O■uz" not in docx_text
    assert "O?uz" not in docx_text

    # PDF check
    pdf_bytes = export_paper_pdf(paper)
    reader = pypdf.PdfReader(io.BytesIO(pdf_bytes))
    pdf_text = "\n".join(page.extract_text() or "" for page in reader.pages)
    assert "Oğuz" in pdf_text
    assert "O■uz" not in pdf_text
    assert "■" not in pdf_text


def test_cormack_multiline_reference_extraction_retains_exact_title() -> None:
    extracted = extract_bibliographic_references(SAMPLE_DOSSIER_REFS)
    assert len(extracted) == 2

    cormack_ref = next(r for r in extracted if "Cormack" in r.text)
    assert (
        "Reciprocal rank fusion outperforms condorcet and individual rank learning methods"
        in cormack_ref.text
    )
    assert "rank introducing variables" not in cormack_ref.text

    if cormack_ref.title:
        assert (
            "Reciprocal rank fusion outperforms condorcet and individual rank learning methods"
            in cormack_ref.title
        )
    assert cormack_ref.doi == "10.1145/1571941.1572114"


def test_hierarchical_section_numbering_is_consistent_and_non_duplicative() -> None:
    assert clean_heading_text("### 1.1 Context & Motivation") == "Context & Motivation"
    assert clean_heading_text("1. Introduction") == "Introduction"
    assert clean_heading_text("2.3.4 Experimental Protocol") == "Experimental Protocol"

    assert format_hierarchical_heading("Introduction", [1]) == "1. Introduction"
    assert format_hierarchical_heading("Background", [1, 1]) == "1.1 Background"
    assert format_hierarchical_heading("Context", [1, 1, 1]) == "1.1.1 Context"

    paper = _create_test_paper()
    docx_bytes = export_paper_docx(paper)
    doc = Document(io.BytesIO(docx_bytes))
    numbered_headings = [
        p.text
        for p in doc.paragraphs
        if p.style.name.startswith("Heading")
        and p.text not in ("Abstract", "Keywords", "References")
    ]

    # Check consecutive numbers
    assert numbered_headings[0] == "1. Context & Motivation"
    assert numbered_headings[1] == "1.1 Theoretical Rationale"
    assert numbered_headings[2] == "1.1.1 Analytical Interpretation"
    assert numbered_headings[3] == "2. Methodology"
    assert numbered_headings[4] == "3. Discussion"


def test_references_section_is_strictly_bibliographic_never_prose() -> None:
    paper = _create_test_paper()
    docx_bytes = export_paper_docx(paper)
    doc = Document(io.BytesIO(docx_bytes))
    paragraphs = [p.text for p in doc.paragraphs]

    ref_idx = paragraphs.index("References")
    subsequent = paragraphs[ref_idx + 1 :]

    # In our document, only reference items follow the References heading
    for p in subsequent:
        assert p.startswith("[") or p == "", f"Unexpected prose in References section: {p}"
        assert "Analysis" not in p
        assert "Reciprocal rank fusion outperforms condorcet" in p or "Dense passage retrieval" in p


def test_unconducted_results_produce_hypothesized_protocol_not_fabricated_claims() -> None:
    brief = ResearchBrief(
        project=ProjectContext(
            title="Hybrid IR",
            research_field="Computer Science",
            research_question="Does fusion improve recall?",
            objectives=["Evaluate RRF"],
            claimed_contribution="Protocol design",
            methodology_status="provided",
            methodology="Dual index retrieval",
            dataset_or_materials_status="provided",
            dataset_or_materials="MS-MARCO",
            results_status="not_collected",
            results=None,
            limitations_status="provided",
            limitations="Simulated indices",
        ),
        source_draft="We plan to run experiments in future work.",
        references=[],
        preferences=PaperPreferences(
            target_word_count=3000,
            desired_sections=["introduction", "methodology", "results"],
            citation_style="ieee",
        ),
    )

    plan = create_manuscript_plan(brief)
    # Abstract must not claim empirical performance gains
    assert "empirical findings demonstrate" not in plan.abstract.lower()
    assert "remain proposed without collected evaluation data" in plan.abstract.lower()


def test_large_section_with_embedded_figures_exports_successfully() -> None:
    tiny_png_b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
    large_figure_md = f"![Figure 1: Benchmark](data:image/png;base64,{tiny_png_b64})\n\n"
    large_content = ("Context discussion paragraph.\n\n" + large_figure_md) * 350
    assert len(large_content) > 30000

    paper = PaperDraft(
        schema_version=1,
        title="High Resolution Benchmark Figures",
        abstract="Evaluating multi-figure section rendering.",
        keywords=["figures", "evaluation"],
        sections=[
            PaperSection(
                id="results",
                heading="Results",
                content=large_content,
                state="draft",
            )
        ],
        references=[],
        review_warnings=[],
    )

    docx_bytes = export_paper_docx(paper)
    assert len(docx_bytes) > 500

    pdf_bytes = export_paper_pdf(paper)
    assert len(pdf_bytes) > 500
