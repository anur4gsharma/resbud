"""Long-Form Manuscript Generation Engine: Controlled planning, section synthesis, and resilient assembly."""

from __future__ import annotations

import asyncio
from time import perf_counter
from uuid import uuid4

from pydantic import ValidationError

from resbud_api.core.errors import ResbudError
from resbud_api.domain.manuscript_plan import ManuscriptPlan, PlannedSection
from resbud_api.domain.models import (
    GenerationMeta,
    GenerationRequest,
    GenerationResponse,
    PaperDraft,
    PaperSection,
    ReviewWarning,
)
from resbud_api.providers.base import (
    GenerationProvider,
    ProviderInvalidResponse,
    ProviderRateLimited,
    ProviderTimeout,
    ProviderUnavailable,
    ResearchBrief,
)
from resbud_api.services.integrity import has_meaningful_content, run_integrity_checks
from resbud_api.services.manuscript_planner import create_manuscript_plan
from resbud_api.services.section_generator import (
    build_section_prompt,
    execute_section_generation,
)
from resbud_api.services.section_validator import (
    count_words,
    perform_bounded_expansion,
    validate_section_depth,
)


def _extract_section_summary(section: PaperSection) -> str:
    """Extract a concise 1-2 sentence takeaway of a completed section for continuity."""
    paragraphs = [p.strip() for p in section.content.split("\n\n") if p.strip() and not p.startswith("|")]
    if not paragraphs:
        return f"Section '{section.heading}' established relevant domain parameters."
    last_paragraph = paragraphs[-1]
    sentences = [s.strip() for s in last_paragraph.split(". ") if s.strip()]
    if sentences:
        return f"Section '{section.heading}' concluded: {sentences[-1]}."
    return f"Section '{section.heading}' concluded its analysis."


def _create_fallback_section(section_plan: PlannedSection, error_message: str) -> PaperSection:
    """Construct an informative fallback section when provider generation encounters an interruption."""
    subsections_text = "\n".join(
        f"### {sub.title}\n{sub.purpose}\n" for sub in section_plan.subsections
    )
    fallback_content = (
        f"This section is planned to cover: {section_plan.purpose}\n\n"
        f"{subsections_text}\n\n"
        f"[Note: Section generation encountered a provider interruption ({error_message}). "
        f"Use the 'Regenerate Section' tool in the editor to synthesize this section.]"
    )
    return PaperSection(
        id=section_plan.id,
        heading=section_plan.heading,
        content=fallback_content,
        state="needs_input",
    )


async def generate_long_form_manuscript(
    brief: ResearchBrief,
    provider: GenerationProvider,
    max_retries_per_section: int = 2,
) -> GenerationResponse:
    """Execute controlled long-form manuscript generation with planning, section expansion, and failure recovery."""
    started = perf_counter()
    provider_name = getattr(provider, "provider_name", "unknown")
    model_name = getattr(provider, "model_name", getattr(provider, "_model", "default"))

    # Stage 1: Manuscript Planning
    plan: ManuscriptPlan = create_manuscript_plan(brief, provider)

    assembled_sections: list[PaperSection] = []
    failure_warnings: list[ReviewWarning] = []
    previous_summary: str | None = None
    total_input_tokens: int | None = 0
    total_output_tokens: int | None = 0

    # Stage 2: Controlled Section-by-Section Expansion
    for section_plan in plan.sections:
        section_prompt = build_section_prompt(
            brief=brief,
            plan=plan,
            section=section_plan,
            previous_section_summary=previous_summary,
        )

        section: PaperSection | None = None
        last_error = ""

        # Retry loop per section with exponential backoff (Requirement 5)
        for attempt in range(1, max_retries_per_section + 2):
            try:
                section = await execute_section_generation(
                    prompt=section_prompt,
                    section=section_plan,
                    provider=provider,
                )
                break
            except (ProviderRateLimited, asyncio.TimeoutError) as exc:
                last_error = type(exc).__name__
                if attempt <= max_retries_per_section:
                    await asyncio.sleep(1.5 * attempt)
                    continue
            except (ProviderTimeout, ProviderUnavailable, ProviderInvalidResponse, Exception) as exc:
                last_error = type(exc).__name__
                if attempt <= max_retries_per_section:
                    await asyncio.sleep(1.0 * attempt)
                    continue

        if section is not None:
            # Stage 2b: Actual Depth Validation and Bounded Continuation (Prompt 3)
            val_result = validate_section_depth(section, section_plan, brief)
            if val_result.is_under_generated:
                section, val_result = await perform_bounded_expansion(
                    section=section,
                    section_plan=section_plan,
                    brief=brief,
                    val_result=val_result,
                    provider=provider,
                )
            assembled_sections.append(section)
            previous_summary = _extract_section_summary(section)
        else:
            # Resilient partial recovery: never discard the rest of the manuscript
            fallback = _create_fallback_section(section_plan, last_error or "interrupted")
            assembled_sections.append(fallback)
            failure_warnings.append(
                ReviewWarning(
                    code="GENERAL_REVIEW",
                    message=f"Section '{section_plan.heading}' could not be completed during initial synthesis and requires regeneration.",
                    severity="warning",
                    section_id=section_plan.id,
                )
            )

    # Stage 3: Manuscript Assembly & Completion Reporting (Requirement 4)
    words_per_section = {s.id: count_words(s.content) for s in assembled_sections}
    abstract_words = count_words(plan.abstract)
    generated_words = sum(words_per_section.values()) + abstract_words
    requested_words = brief.preferences.target_word_count
    approx_output_tokens = int(generated_words * 1.35)

    missing_sections = [s.id for s in assembled_sections if s.state == "needs_input"]
    evidence_restrictions = list(plan.identified_limitations)

    # Determine completion status based on acceptance tolerance and evidence constraints
    if failure_warnings:
        completion_status = "partially_complete"
    elif generated_words >= int(requested_words * 0.75):
        completion_status = "completed"
    elif any(s.state == "needs_input" for s in assembled_sections) or evidence_restrictions:
        completion_status = "evidence_constrained"
    else:
        completion_status = "under_generated"

    paper = PaperDraft(
        schema_version=1,
        title=plan.title,
        abstract=plan.abstract,
        keywords=plan.keywords,
        sections=assembled_sections,
        references=list(brief.references),
        review_warnings=[],
    )

    if not has_meaningful_content(paper):
        raise ResbudError(502)

    # Stage 4: Research Integrity & Completion Review Warnings
    integrity_warnings = run_integrity_checks(brief, paper, provider_name)
    completion_msg = (
        f"Manuscript Completion: [{completion_status.upper()}]. "
        f"Generated {generated_words} of {requested_words} requested words across {len(assembled_sections)} sections."
    )
    if evidence_restrictions:
        completion_msg += f" Limitations: {evidence_restrictions[0]}."
    completion_warning = ReviewWarning(
        code="GENERAL_REVIEW",
        message=completion_msg,
        severity="info" if completion_status in ("completed", "evidence_constrained") else "warning",
        section_id=None,
    )

    all_warnings = [completion_warning] + integrity_warnings + failure_warnings
    paper = paper.model_copy(update={"review_warnings": all_warnings})

    elapsed_ms = int((perf_counter() - started) * 1000)

    return GenerationResponse(
        schema_version=1,
        generation_id=uuid4(),
        paper=paper,
        review_warnings=all_warnings,
        meta=GenerationMeta(
            provider_name=provider_name,
            model_name=str(model_name),
            duration_ms=elapsed_ms,
            input_tokens=None,
            output_tokens=approx_output_tokens,
            requested_words=requested_words,
            generated_words=generated_words,
            words_per_section=words_per_section,
            completion_status=completion_status,
            missing_sections=missing_sections,
            evidence_restrictions=evidence_restrictions,
        ),
    )
