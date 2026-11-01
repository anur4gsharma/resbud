"""Comprehensive tests for the long-form manuscript generation engine."""

import asyncio
import json
from pathlib import Path
from typing import Any
from unittest.mock import AsyncMock, patch

from jsonschema import Draft202012Validator
import pytest

from resbud_api.domain.manuscript_plan import ManuscriptPlan, PlannedSection
from resbud_api.domain.models import (
    GenerationRequest,
    GenerationResponse,
    PaperDraft,
    PaperPreferences,
    ProjectContext,
    ReferenceInput,
)
from resbud_api.providers.base import (
    GenerationPrompt,
    ProviderResult,
    ProviderTimeout,
    ResearchBrief,
)
from resbud_api.providers.fake import FakeProvider
from resbud_api.services.long_form_engine import (
    _create_fallback_section,
    _extract_section_summary,
    generate_long_form_manuscript,
)
from resbud_api.services.manuscript_planner import create_manuscript_plan
from resbud_api.services.section_generator import build_section_prompt, execute_section_generation

ROOT = Path(__file__).resolve().parents[1]
PAPER_SCHEMA = json.loads((ROOT / "../contracts/paper-draft.schema.json").resolve().read_text())


@pytest.fixture
def sample_brief() -> ResearchBrief:
    return ResearchBrief(
        project=ProjectContext(
            title="Evaluating Retrieval-Augmented Generation for Factual Question Answering over a University Policy Corpus",
            research_field="Natural Language Processing",
            research_question="Does RAG improve answer correctness and reduce unsupported factual claims?",
            objectives=[
                "Compare closed-book vs RAG across 120 benchmark policy questions",
                "Measure citation support rate and distinguish citations from factual grounding",
            ],
            claimed_contribution="A controlled paired evaluation framework demonstrating RAG groundability.",
            methodology_status="provided",
            methodology="Within-question paired design with ResearchBuddy-Sim-7B, top-5 retrieved passages.",
            dataset_or_materials_status="provided",
            dataset_or_materials="120 university policy questions across academic regulations, registration, and financial aid.",
            results_status="provided",
            results="RAG achieved 81.7% correctness vs 59.2% for closed-book (p = 0.0000143). Citation presence was 85.0% but citation support was 74.2%.",
            limitations_status="provided",
            limitations="Single model architecture, synthetic evaluation corpus, and uncalibrated retriever scores.",
        ),
        source_draft=(
            "Detailed research dossier:\n"
            "We investigate retrieval-augmented generation in university policy contexts.\n"
            "We evaluated 120 policy questions using a paired design.\n"
            "Closed-book was correct on 71 questions (59.2%). RAG was correct on 98 questions (81.7%).\n"
            "McNemar test p-value was 0.0000143. 33 questions were corrected by RAG, 6 were worsened.\n"
            "Citation presence was 85.0% (102/120) but citation support was 74.2% (89/120)."
        ),
        references=(
            ReferenceInput(id="ref_1", text="Lewis, P. et al. (2020). Retrieval-Augmented Generation. NeurIPS 33."),
            ReferenceInput(id="ref_2", text="Karpukhin, V. et al. (2020). Dense Passage Retrieval. EMNLP."),
        ),
        preferences=PaperPreferences(
            target_word_count=5000,
            desired_sections=[],
            citation_style="apa_7",
        ),
    )


def test_manuscript_planner_generates_detailed_plan(sample_brief: ResearchBrief) -> None:
    """Verify Stage 1: Manuscript planning produces structured, mathematically allocated plans."""
    provider = FakeProvider()
    plan: ManuscriptPlan = create_manuscript_plan(sample_brief, provider)

    assert isinstance(plan, ManuscriptPlan)
    assert plan.total_target_words == 5000
    assert len(plan.sections) >= 5
    assert len(plan.terminology_glossary) >= 3

    # Check that section word budgets + abstract allocate the target word count
    total_allocated = sum(s.allocated_words for s in plan.sections)
    assert total_allocated >= 4700
    assert total_allocated <= 5000

    # Verify sections have subsections and key arguments
    for sec in plan.sections:
        assert sec.id
        assert sec.heading
        assert sec.purpose
        assert sec.allocated_words > 0
        assert len(sec.subsections) >= 1
        assert len(sec.key_arguments) >= 1
        assert isinstance(sec.available_evidence, list)


def test_section_prompt_builder_preserves_continuity(sample_brief: ResearchBrief) -> None:
    """Verify Stage 2: Prompt builder includes continuity chaining and canonical evidence."""
    provider = FakeProvider()
    plan = create_manuscript_plan(sample_brief, provider)
    target_section = plan.sections[1]

    prompt = build_section_prompt(
        brief=sample_brief,
        plan=plan,
        section=target_section,
        previous_section_summary="Section 1 established the RAG operational bottleneck.",
    )

    assert isinstance(prompt, GenerationPrompt)
    assert prompt.output_schema == "PaperSection"
    assert "Section 1 established the RAG operational bottleneck." in prompt.user_message
    assert "81.7%" in prompt.user_message or "McNemar" in prompt.user_message
    assert target_section.heading in prompt.user_message


def test_section_summary_extraction() -> None:
    """Verify section summary extraction isolates the concluding takeaway for chaining."""
    from resbud_api.domain.models import PaperSection

    sec = PaperSection(
        id="methodology",
        heading="Methodology",
        content="First paragraph introducing the setup.\n\nSecond paragraph. We established our evaluation metric at 95% precision. This confirms protocol soundness.",
        state="draft",
    )
    summary = _extract_section_summary(sec)
    assert "Methodology" in summary
    assert "protocol soundness" in summary


@pytest.mark.anyio
async def test_long_form_engine_hits_target_word_count(sample_brief: ResearchBrief) -> None:
    """Verify that the long-form engine achieves multi-thousand word output (>= 4,000 words on 5,000 target)."""
    provider = FakeProvider()
    response = await generate_long_form_manuscript(sample_brief, provider)

    assert isinstance(response, GenerationResponse)
    paper = response.paper
    assert len(paper.sections) >= 5

    # Count total words across all sections
    total_words = sum(len(sec.content.split()) for sec in paper.sections)
    assert total_words >= 4500, f"Expected >= 4500 words on a 5000 target, got {total_words}"

    # Verify each section has multiple substantive paragraphs
    for sec in paper.sections:
        paragraphs = [p for p in sec.content.split("\n\n") if p.strip()]
        assert len(paragraphs) >= 2, f"Section {sec.heading} has too few paragraphs: {len(paragraphs)}"

    # Validate against JSON schema contract
    paper_dict = paper.model_dump(mode="json")
    Draft202012Validator(PAPER_SCHEMA).validate(paper_dict)


@pytest.mark.anyio
async def test_long_form_engine_failure_recovery_preserves_manuscript(sample_brief: ResearchBrief) -> None:
    """Verify Stage 5: A single section failure does NOT abort generation; fallback is created and flagged."""
    provider = FakeProvider()

    # Create a mock wrapper that consistently fails on the results section
    original_generate_section = provider.generate_section

    async def flaky_generate_section(prompt: GenerationPrompt) -> ProviderResult:
        if '"id": "results"' in prompt.user_message:
            raise ProviderTimeout("Simulated API timeout on results section")
        return await original_generate_section(prompt)

    provider.generate_section = flaky_generate_section  # type: ignore[assignment]

    response = await generate_long_form_manuscript(sample_brief, provider, max_retries_per_section=1)

    assert isinstance(response, GenerationResponse)
    paper = response.paper
    assert len(paper.sections) >= 5

    # The results section should be preserved as needs_input with an informative message
    failed_section = next(s for s in paper.sections if s.id == "results")
    assert failed_section.state == "needs_input"
    assert "provider interruption" in failed_section.content
    assert "Regenerate Section" in failed_section.content

    # The remaining sections must still be drafted and substantial
    other_sections = [s for s in paper.sections if s.id != "results"]
    for sec in other_sections:
        assert sec.state == "draft"
        assert len(sec.content.split()) >= 100

    # Ensure a GENERAL_REVIEW warning was added for the failed section
    warning_codes = [w.code for w in response.review_warnings if w.section_id == failed_section.id]
    assert "GENERAL_REVIEW" in warning_codes

    # Ensure paper still strictly satisfies contract schema
    paper_dict = paper.model_dump(mode="json")
    Draft202012Validator(PAPER_SCHEMA).validate(paper_dict)
