"""Comprehensive automated tests for word-count control, section depth validation, and completion reporting (Prompt 3)."""

import asyncio
from unittest.mock import AsyncMock

import pytest

from resbud_api.domain.manuscript_plan import PlannedSection, PlannedSubsection
from resbud_api.domain.models import (
    GenerationRequest,
    GenerationResponse,
    PaperDraft,
    PaperPreferences,
    PaperSection,
    ProjectContext,
    ReferenceInput,
)
from resbud_api.providers.base import GenerationPrompt, ProviderResult, ResearchBrief
from resbud_api.providers.fake import FakeProvider
from resbud_api.services.long_form_engine import generate_long_form_manuscript
from resbud_api.services.section_allocation import (
    STANDARD_EMPIRICAL_WEIGHTS,
    SectionBudgetPlan,
    compute_adaptive_section_budgets,
    detect_paper_type,
)
from resbud_api.services.section_validator import (
    SectionValidationResult,
    check_topic_and_evidence_coverage,
    count_words,
    detect_repetition_and_filler,
    perform_bounded_expansion,
    validate_section_depth,
)


@pytest.fixture
def empirical_brief() -> ResearchBrief:
    return ResearchBrief(
        project=ProjectContext(
            title="Empirical Evaluation of Attention Gating in Neural Histopathology",
            research_field="Computer Science and Artificial Intelligence",
            research_question="Does cross-attention gating improve diagnosis accuracy?",
            objectives=["Evaluate diagnosis precision", "Measure throughput efficiency"],
            claimed_contribution="A cross-attention gating mechanism for histology imaging.",
            methodology_status="provided",
            methodology="Retrospective 5-fold cross-validation on TCGA cohorts.",
            dataset_or_materials_status="provided",
            dataset_or_materials="TCGA and Camelyon16 whole-slide datasets.",
            results_status="provided",
            results="Accuracy was 94.2% vs 88.5% for baseline CNN (p = 0.0003).",
            limitations_status="provided",
            limitations="Single-center clinical validation only.",
        ),
        source_draft="Comprehensive research dossier detailing 5-fold CV results on TCGA.",
        references=(
            ReferenceInput(id="ref_1", text="Author. (2024). Histopathology Transformers."),
        ),
        preferences=PaperPreferences(
            target_word_count=5000,
            desired_sections=[],
            citation_style="apa_7",
        ),
    )


def test_count_words_accurately_ignores_markdown_formatting() -> None:
    """Verify word count strips markdown heading markers, horizontal rules, and table delimiters."""
    raw_markdown = (
        "# Main Heading\n\n"
        "This is a standard academic paragraph containing exactly ten words here.\n\n"
        "| Metric | Score |\n"
        "| Accuracy | 95.2% |\n\n"
        "--- \n\n"
        "### Subsection 1.1\n"
        "Another sentence with seven words right here."
    )
    # Paragraph 1 = 10 words, Table row 1 = 2 words (Metric, Score), Table row 2 = 2 words (Accuracy, 95.2%),
    # Subsection line = 3 words (Subsection, 1.1, Heading), Paragraph 2 = 7 words
    wc = count_words(raw_markdown)
    assert wc >= 20 and wc <= 28


def test_detect_repetition_and_filler() -> None:
    """Verify detection of repeated sentences and degenerate low-diversity filler."""
    clean_text = (
        "The proposed architecture incorporates a dual-branch feature extractor. "
        "Each branch processes distinct spatial frequencies to preserve cellular morphology. "
        "Empirical evaluations demonstrate substantial performance gains over conventional convolutional baselines."
    )
    score_clean, issues_clean = detect_repetition_and_filler(clean_text)
    assert score_clean == 0.0
    assert len(issues_clean) == 0

    repetitive_text = (
        "In this section we analyze the primary experimental results of the proposed method. "
        "In this section we analyze the primary experimental results of the proposed method. "
        "In this section we analyze the primary experimental results of the proposed method. "
        "In this section we analyze the primary experimental results of the proposed method."
    )
    score_rep, issues_rep = detect_repetition_and_filler(repetitive_text)
    assert score_rep > 0.0
    assert any("duplicate" in issue.lower() or "diversity" in issue.lower() for issue in issues_rep)


def test_adaptive_section_budgets_empirical_baseline(empirical_brief: ResearchBrief) -> None:
    """Verify standard empirical allocation distributes words matching the Prompt 3 baseline."""
    abstract_words, budget_plans, restrictions = compute_adaptive_section_budgets(empirical_brief, 5000)

    assert abstract_words == 250  # 5% of 5000
    plan_map = {p.section_id: p for p in budget_plans}

    # Verify standard empirical sections exist
    assert "introduction" in plan_map
    assert "related_work" in plan_map
    assert "methodology" in plan_map
    assert "results" in plan_map
    assert "discussion" in plan_map
    assert "conclusion" in plan_map

    # Check sum of section budgets + abstract equals total requested
    total_allocated = sum(p.target_words for p in budget_plans) + abstract_words
    assert total_allocated == 5000

    # Verify methodology and results receive substantial allocations
    assert plan_map["methodology"].target_words >= 900
    assert plan_map["results"].target_words >= 600


def test_adaptive_section_budgets_reallocates_when_results_not_collected() -> None:
    """Verify results budget is reallocated to Methodology and Discussion when experiments were not conducted."""
    no_results_brief = ResearchBrief(
        project=ProjectContext(
            title="Conceptual Framework for Clinical AI",
            research_field="Computer Science",
            research_question="How should governance be structured?",
            objectives=["Define governance taxonomy"],
            claimed_contribution="A governance taxonomy.",
            methodology_status="provided",
            methodology="Qualitative policy framework analysis.",
            dataset_or_materials_status="not_applicable",
            dataset_or_materials=None,
            results_status="not_collected",
            results=None,
            limitations_status="provided",
            limitations="Conceptual proposal only.",
        ),
        source_draft="Governance framework description without experimental outcomes.",
        references=(),
        preferences=PaperPreferences(target_word_count=3000, desired_sections=[], citation_style="apa_7"),
    )

    abstract_words, budget_plans, restrictions = compute_adaptive_section_budgets(no_results_brief, 3000)
    plan_map = {p.section_id: p for p in budget_plans}

    # Results section should be omitted or budget reallocated
    assert "results" not in plan_map
    assert any("not collected" in r.lower() for r in restrictions)

    # Reallocated budget expands methodology and discussion
    assert plan_map["methodology"].target_words >= 700
    assert plan_map["discussion"].target_words >= 600


def test_validate_section_depth_under_generation_detection(empirical_brief: ResearchBrief) -> None:
    """Verify validate_section_depth flags sections that fall below the acceptance tolerance."""
    section_plan = PlannedSection(
        id="methodology",
        heading="3. Methodology",
        purpose="Describe pipeline and data curation.",
        allocated_words=1000,
        subsections=[
            PlannedSubsection(title="Data Curation", purpose="Data splits.", target_words=500),
            PlannedSubsection(title="Architecture Pipeline", purpose="Model details.", target_words=500),
        ],
        available_evidence=["TCGA cohort."],
        key_arguments=["Cross-validation protocol."],
    )

    # Under-generated section (only 80 words vs 1000 budget = 8% of budget)
    short_section = PaperSection(
        id="methodology",
        heading="3. Methodology",
        content="We used TCGA cohort with 5-fold cross-validation. The model was trained with Adam optimizer.",
        state="draft",
    )

    result: SectionValidationResult = validate_section_depth(
        section=short_section,
        section_plan=section_plan,
        brief=empirical_brief,
        tolerance_pct=0.75,
    )

    assert result.is_under_generated is True
    assert result.ratio < 0.15
    assert result.is_complete is False


@pytest.mark.anyio
async def test_bounded_expansion_handles_insufficient_evidence_safely(empirical_brief: ResearchBrief) -> None:
    """Verify safe handling of insufficient evidence: appends limitation disclosure rather than fabricating filler."""
    section_plan = PlannedSection(
        id="results",
        heading="4. Results",
        purpose="Present quantitative outcomes.",
        allocated_words=800,
        requires_input_notice=True,  # Insufficient evidence
        missing_information=["Specific ablation tables missing"],
    )

    short_section = PaperSection(
        id="results",
        heading="4. Results",
        content="Primary accuracy was 94.2%. Baseline was 88.5%.",
        state="needs_input",
    )

    val_result = validate_section_depth(short_section, section_plan, empirical_brief)
    assert val_result.is_evidence_constrained is True

    provider = FakeProvider()
    expanded_section, updated_val = await perform_bounded_expansion(
        section=short_section,
        section_plan=section_plan,
        brief=empirical_brief,
        val_result=val_result,
        provider=provider,
    )

    # Must append methodological disclosure note
    assert "Methodological Scope Note" in expanded_section.content
    assert "rigorously grounded in verified evidence without speculative extrapolation" in expanded_section.content
    assert updated_val.was_expanded is True


@pytest.mark.anyio
async def test_long_form_engine_reports_full_completion_statistics(empirical_brief: ResearchBrief) -> None:
    """Verify long-form generation generates complete statistics and attaches completion metadata."""
    provider = FakeProvider()
    response: GenerationResponse = await generate_long_form_manuscript(empirical_brief, provider)

    meta = response.meta
    assert meta.requested_words == 5000
    assert meta.generated_words is not None
    assert meta.generated_words >= 4500
    assert meta.completion_status in ("completed", "evidence_constrained")
    assert isinstance(meta.words_per_section, dict)
    assert len(meta.words_per_section) >= 5

    # Check that completion status is also surfaced in review warnings for immediate visibility
    completion_warning = next(
        (w for w in response.review_warnings if "Manuscript Completion:" in w.message),
        None,
    )
    assert completion_warning is not None
    assert "Manuscript Completion: [COMPLETED]" in completion_warning.message or "EVIDENCE_CONSTRAINED" in completion_warning.message
