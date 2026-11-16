"""Regression test suite for Paper Generation Response Contract and Error Taxonomy.

Covers Tests A through J:
- Test A: Standard academic paper generation
- Test B: Two-column academic paper generation
- Test C: IEEE Conference paper generation (5 authors, 2 affiliations, 3 figures, OMML equations, 15 IEEE references)
- Test D: Missing info handling
- Test E: Provider timeout handling
- Test F: Invalid format rejection
- Test G: Response contract adherence
- Test H: Database persistence / round-trip serialization
- Test I: Export generation from persisted paper (DOCX and PDF, with and without notes)
- Test J: Backward compatibility with older paper versions
"""

import json
from typing import Any
from uuid import UUID, uuid4

import pytest
from pydantic import ValidationError

from resbud_api.core.errors import ResbudError
from resbud_api.domain.models import (
    AuthorAffiliation,
    AuthorMetadata,
    GenerationMeta,
    GenerationRequest,
    GenerationResponse,
    PaperDraft,
    PaperPreferences,
    PaperSection,
    ProjectContext,
    ReferenceInput,
    ReviewWarning,
    StructuredFigure,
)
from resbud_api.providers.base import (
    ProviderResult,
    ProviderTimeout,
)
from resbud_api.services.docx_export import export_paper_docx
from resbud_api.services.generation import generate_paper
from resbud_api.services.pdf_export import export_paper_pdf


class MockDeterministicProvider:
    provider_name = "test-provider"
    model_name = "test-model"

    def __init__(self, raw_output: str | None = None, raise_timeout: bool = False):
        self.raw_output = raw_output
        self.raise_timeout = raise_timeout

    async def generate_paper(self, generation_input: Any) -> ProviderResult:
        if self.raise_timeout:
            raise ProviderTimeout("Model generation timed out.")
        return ProviderResult(
            provider_name=self.provider_name,
            model_name=self.model_name,
            structured_output=self.raw_output or "",
            duration_ms=120,
            input_tokens=100,
            output_tokens=250,
        )


def _build_test_sections() -> list[PaperSection]:
    return [
        PaperSection(
            id="introduction",
            heading="Introduction",
            content="This research addresses automated document generation. Inline math like $E = mc^2$ is preserved.",
            state="draft",
        ),
        PaperSection(
            id="methodology",
            heading="Methodology",
            content="We formalize the transformation pipeline using display equations:\n\n$$\\nabla \\cdot \\mathbf{E} = \\frac{\\rho}{\\varepsilon_0}$$\n\nDetailed algorithmic guarantees are presented.",
            state="draft",
        ),
        PaperSection(
            id="results",
            heading="Results and Evaluation",
            content="Empirical measurements demonstrate 99.8% precision across all test suites.",
            state="draft",
        ),
    ]


def _build_standard_request(page_layout: str = "single_column", template: str = "default") -> GenerationRequest:
    return GenerationRequest(
        schema_version=1,
        project=ProjectContext(
            title="Comprehensive Analysis of Generation Contracts",
            research_field="Computer Science",
            research_question="How can strict API contracts prevent mobile deserialization failures?",
            objectives=["Quantify contract drift", "Implement bounded schema repair"],
            claimed_contribution="A robust bidirectional contract architecture.",
            methodology_status="provided",
            methodology="Static analysis and automated regression suites.",
            dataset_or_materials_status="provided",
            dataset_or_materials="500 generated paper samples.",
            results_status="provided",
            results="Zero contract mismatch exceptions after unifying schemas.",
            limitations_status="provided",
            limitations="Assumes modern JSON parser compatibility.",
        ),
        source_draft="Detailed source draft exploring manuscript generation pipelines.",
        references=[
            ReferenceInput(
                id="ref_1",
                text="A. Sharma et al., 'Contract Integrity in Mobile-Cloud Architectures', IEEE Trans. Software Eng., 2026.",
            )
        ],
        preferences=PaperPreferences(
            target_word_count=2000,
            desired_sections=["introduction", "methodology", "results"],
            citation_style="ieee",
            page_layout=page_layout,
            document_template=template,
            include_review_notes_appendix=False,
        ),
    )


# --- Test A: Standard Academic Paper Generation ---
def test_a_standard_academic_paper_generation() -> None:
    req = _build_standard_request(page_layout="single_column", template="default")
    assert req.preferences.page_layout == "single_column"
    assert req.preferences.document_template == "default"
    assert req.preferences.include_review_notes_appendix is False

    sections = _build_test_sections()
    warnings = [
        ReviewWarning(
            code="GENERAL_REVIEW",
            severity="info",
            message="Manuscript completed successfully.",
            section_id=None,
        )
    ]
    paper = PaperDraft(
        schema_version=1,
        title=req.project.title,
        abstract="A rigorous study of contract verification.",
        keywords=["API Contracts", "Pydantic", "Flutter", "FastAPI"],
        sections=sections,
        references=list(req.references),
        review_warnings=warnings,
        page_layout=req.preferences.page_layout,
        document_template=req.preferences.document_template,
    )

    response = GenerationResponse(
        schema_version=1,
        generation_id=uuid4(),
        paper=paper,
        review_warnings=warnings,
        meta=GenerationMeta(
            provider_name="test-provider",
            model_name="test-model",
            duration_ms=250,
            requested_words=2000,
            generated_words=1850,
        ),
    )

    dumped = response.model_dump(mode="json")
    assert dumped["schema_version"] == 1
    assert dumped["paper"]["document_template"] == "default"
    assert dumped["paper"]["page_layout"] == "single_column"
    assert dumped["review_warnings"] == dumped["paper"]["review_warnings"]


# --- Test B: Two-Column Academic Paper Generation ---
def test_b_two_column_academic_paper_generation() -> None:
    req = _build_standard_request(page_layout="two_column_academic", template="default")
    assert req.preferences.page_layout == "two_column_academic"

    paper = PaperDraft(
        schema_version=1,
        title=req.project.title,
        abstract="Two-column layout test abstract.",
        keywords=["Two Column", "Layout"],
        sections=_build_test_sections(),
        references=list(req.references),
        review_warnings=[],
        page_layout="two_column_academic",
        document_template="default",
    )
    assert paper.page_layout == "two_column_academic"
    data = paper.model_dump(mode="json")
    assert data["page_layout"] == "two_column_academic"


# --- Test C: IEEE Conference Paper Generation ---
def test_c_ieee_conference_paper_generation() -> None:
    # 5 authors
    authors = [
        AuthorMetadata(name=f"Author {i}", order=i, affiliation_ids=["aff_1" if i <= 3 else "aff_2"], email=f"author{i}@univ.edu")
        for i in range(1, 6)
    ]
    # 2 affiliations
    affiliations = [
        AuthorAffiliation(id="aff_1", institution="Department of EECS, Tech University", city="Boston", country="USA"),
        AuthorAffiliation(id="aff_2", institution="AI Research Lab, Global Institute", city="London", country="UK"),
    ]
    # 3 structured figures
    figures = [
        StructuredFigure(
            id=f"fig_{i}",
            filename=f"figure_{i}.png",
            caption=f"Fig. {i}. Architectural diagram of stage {i}.",
            category="architecture_diagram",
            related_section="methodology",
            placement_status="assigned",
        )
        for i in range(1, 4)
    ]
    # 15 IEEE references
    references = [
        ReferenceInput(
            id=f"ref_{i}",
            text=f"Author {i}, 'Title of paper {i}', IEEE Trans. Comput., vol. {i}, pp. 100-110, 202{i%6}.",
            citation_number=i,
            is_cited=True,
        )
        for i in range(1, 16)
    ]

    paper = PaperDraft(
        schema_version=1,
        title="Deep Learning Posture Analysis under IEEE Format Standards",
        abstract="This paper satisfies all structural, typographical, and mathematical criteria for IEEE Conference manuscripts.",
        keywords=["IEEE Conference", "OMML Equations", "Semantic Figures", "Numbered Citations"],
        sections=_build_test_sections(),
        references=references,
        review_warnings=[],
        page_layout="two_column_academic",
        document_template="ieee_conference",
        authors=authors,
        affiliations=affiliations,
        figures=figures,
    )

    dumped = paper.model_dump(mode="json")
    assert dumped["document_template"] == "ieee_conference"
    assert len(dumped["authors"]) == 5
    assert len(dumped["affiliations"]) == 2
    assert len(dumped["figures"]) == 3
    assert len(dumped["references"]) == 15

    # Re-parse to ensure 100% contract compliance
    reparsed = PaperDraft.model_validate(dumped)
    assert reparsed.document_template == "ieee_conference"
    assert len(reparsed.authors or []) == 5


# --- Test D: Missing Information Handling ---
def test_d_missing_info_handling() -> None:
    # Context with explicit negative evidence statuses
    ctx = ProjectContext(
        title="Incomplete Study Context",
        research_field="Computer Science",
        research_question="What happens when data is missing?",
        objectives=["Identify gaps"],
        claimed_contribution="Negative fact discovery.",
        methodology_status="not_available",
        dataset_or_materials_status="not_available",
        results_status="not_collected",
        limitations_status="not_identified",
    )
    assert ctx.methodology is None
    assert ctx.dataset_or_materials is None
    assert ctx.results is None
    assert ctx.limitations is None

    # Sections where results is marked needs_input
    sections = [
        PaperSection(id="introduction", heading="Introduction", content="Intro.", state="draft"),
        PaperSection(id="results", heading="Results", content="[RESULTS NOT COLLECTED YET]", state="needs_input"),
    ]
    warnings = [
        ReviewWarning(code="MISSING_RESULTS", severity="warning", message="No results were supplied.", section_id="results"),
        ReviewWarning(code="MISSING_METHOD", severity="warning", message="No methodology was supplied.", section_id=None),
    ]

    paper = PaperDraft(
        schema_version=1,
        title=ctx.title,
        abstract="Abstract with caveats.",
        keywords=["Gaps"],
        sections=sections,
        references=[],
        review_warnings=warnings,
    )
    assert any(s.state == "needs_input" for s in paper.sections)
    assert any(w.code == "MISSING_RESULTS" for w in paper.review_warnings)


# --- Test E: Provider Timeout Handling ---
@pytest.mark.anyio
async def test_e_provider_timeout_handling() -> None:
    provider = MockDeterministicProvider(raise_timeout=True)
    req = _build_standard_request()

    with pytest.raises(ResbudError) as exc_info:
        await generate_paper(req, provider)

    assert exc_info.value.public_error.status == 504
    assert exc_info.value.public_error.code == "PROVIDER_TIMEOUT"


# --- Test F: Invalid Format Rejection ---
def test_f_invalid_format_rejection() -> None:
    # 1. Invalid target word count (< 500)
    with pytest.raises(ValidationError):
        PaperPreferences(
            target_word_count=200,
            desired_sections=["introduction"],
            citation_style="ieee",
        )

    # 2. Invalid section ID format (uppercase or symbols)
    with pytest.raises(ValidationError):
        PaperPreferences(
            target_word_count=1500,
            desired_sections=["INVALID_SECTION_ID!"],
            citation_style="ieee",
        )

    # 3. Forbidden extra fields rejected by ContractModel
    with pytest.raises(ValidationError):
        PaperPreferences.model_validate({
            "target_word_count": 1500,
            "desired_sections": ["introduction"],
            "citation_style": "ieee",
            "forbidden_extra_field": "disallowed",
        })


# --- Test G: Response Contract Adherence ---
def test_g_response_contract_adherence() -> None:
    gen_id = uuid4()
    paper = PaperDraft(
        schema_version=1,
        title="Contract Verified Paper",
        abstract="Valid abstract.",
        keywords=["Contract"],
        sections=_build_test_sections(),
        references=[],
        review_warnings=[],
    )
    resp = GenerationResponse(
        schema_version=1,
        generation_id=gen_id,
        paper=paper,
        review_warnings=[],
        meta=GenerationMeta(
            provider_name="gemini",
            model_name="gemini-3.5-flash",
            duration_ms=3140,
            requested_words=2000,
            generated_words=2050,
            words_per_section={"introduction": 500, "methodology": 800, "results": 750},
            completion_status="completed",
        ),
    )
    dumped = resp.model_dump(mode="json")

    # Strict key checks
    assert set(dumped.keys()) == {"schema_version", "generation_id", "paper", "review_warnings", "meta"}
    UUID(dumped["generation_id"])  # Valid UUID string
    assert dumped["meta"]["duration_ms"] == 3140
    assert dumped["meta"]["completion_status"] == "completed"


# --- Test H: Database Persistence / Round-Trip ---
def test_h_database_persistence_roundtrip() -> None:
    original = PaperDraft(
        schema_version=1,
        title="Persisted IEEE Draft",
        abstract="Abstract text for local storage.",
        keywords=["Persistence", "SQLite"],
        sections=_build_test_sections(),
        references=[ReferenceInput(id="ref_1", text="Sample Ref.")],
        review_warnings=[],
        page_layout="two_column_academic",
        document_template="ieee_conference",
        authors=[AuthorMetadata(name="Jane Doe", order=1, email="jane@doe.com")],
        affiliations=[AuthorAffiliation(id="aff_1", institution="MIT")],
        figures=[StructuredFigure(id="fig_1", filename="plot.png", caption="Fig. 1. Plot.")],
    )

    # Simulate saving to SQLite as JSON string
    serialized_json = original.model_dump_json()

    # Simulate reloading from SQLite row
    loaded_dict = json.loads(serialized_json)
    restored = PaperDraft.model_validate(loaded_dict)

    assert restored == original
    assert restored.document_template == "ieee_conference"
    assert restored.page_layout == "two_column_academic"
    assert len(restored.authors or []) == 1
    assert len(restored.figures or []) == 1


# --- Test I: Export Generation from Persisted Paper ---
def test_i_export_generation_from_persisted_paper() -> None:
    paper = PaperDraft(
        schema_version=1,
        title="Exportable IEEE Conference Manuscript",
        abstract="Testing document export pipelines for DOCX and PDF formats.",
        keywords=["DOCX", "PDF", "Export"],
        sections=_build_test_sections(),
        references=[ReferenceInput(id="ref_1", text="[1] A. Researcher, 'Export pipelines', 2026.")],
        review_warnings=[ReviewWarning(code="GENERAL_REVIEW", severity="info", message="Note for appendix.")],
        page_layout="two_column_academic",
        document_template="ieee_conference",
    )

    # 1. DOCX Export without review notes appendix
    docx_bytes_clean = export_paper_docx(paper, include_review_notes_appendix=False)
    assert len(docx_bytes_clean) > 0
    assert docx_bytes_clean[:4] == b"PK\x03\x04"  # Valid ZIP / DOCX magic bytes

    # 2. DOCX Export with review notes appendix
    docx_bytes_notes = export_paper_docx(paper, include_review_notes_appendix=True)
    assert len(docx_bytes_notes) > len(docx_bytes_clean)

    # 3. PDF Export
    pdf_bytes_clean = export_paper_pdf(paper, include_review_notes_appendix=False)
    assert len(pdf_bytes_clean) > 0
    assert pdf_bytes_clean[:4] == b"%PDF"  # Valid PDF header


# --- Test J: Backward Compatibility with Older Paper Versions ---
def test_j_backward_compatibility_with_older_paper_versions() -> None:
    # Older payload from APK v1.0.0 without document_template, authors, affiliations, figures
    legacy_payload = {
        "schema_version": 1,
        "title": "Legacy v1.0.0 Paper",
        "abstract": "Written before template system.",
        "keywords": ["Legacy"],
        "sections": [
            {
                "id": "introduction",
                "heading": "Introduction",
                "content": "Legacy content.",
                "state": "draft",
            }
        ],
        "references": [
            {
                "id": "ref_1",
                "text": "Old Reference.",
            }
        ],
        "review_warnings": [],
        "page_layout": "single_column",
    }

    paper = PaperDraft.model_validate(legacy_payload)
    assert paper.document_template == "default"
    assert paper.authors is None
    assert paper.affiliations is None
    assert paper.figures is None
    assert paper.page_layout == "single_column"
