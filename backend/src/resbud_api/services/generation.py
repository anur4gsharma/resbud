"""Synchronous paper-generation use case with strict provider-output validation."""

import json
import re
from uuid import uuid4

from pydantic import ValidationError

from resbud_api.core.errors import ResbudError
from resbud_api.domain.models import (
    GenerationMeta,
    GenerationRequest,
    GenerationResponse,
    PaperDraft,
    ReviewWarning,
    WarningCode,
)
from resbud_api.providers.base import (
    GenerationInput,
    GenerationProvider,
    ProviderRateLimited,
    ProviderTimeout,
    ProviderUnavailable,
)


def normalize_research_brief(request: GenerationRequest) -> GenerationInput:
    """Normalize line endings and boundary whitespace without rewriting research claims."""
    return GenerationInput(
        project=request.project,
        source_draft=request.source_draft.replace("\r\n", "\n").replace("\r", "\n").strip(),
        references=tuple(request.references),
        preferences=request.preferences,
    )


async def generate_paper(
    request: GenerationRequest,
    provider: GenerationProvider,
) -> GenerationResponse:
    generation_input = normalize_research_brief(request)
    try:
        provider_result = await provider.generate_paper(generation_input)
    except ProviderTimeout as exc:
        raise ResbudError(504) from exc
    except ProviderUnavailable as exc:
        raise ResbudError(503) from exc
    except ProviderRateLimited as exc:
        raise ResbudError(429) from exc

    try:
        provider_data = json.loads(provider_result.structured_output)
        paper = PaperDraft.model_validate(provider_data)
    except (json.JSONDecodeError, TypeError, ValidationError) as exc:
        raise ResbudError(502) from exc

    if paper.references != list(generation_input.references):
        raise ResbudError(502)

    warnings = _integrity_warnings(generation_input, paper, provider_result.provider_name)
    paper = paper.model_copy(update={"review_warnings": warnings})
    try:
        return GenerationResponse(
            schema_version=1,
            generation_id=uuid4(),
            paper=paper,
            review_warnings=warnings,
            meta=GenerationMeta(
                provider_name=provider_result.provider_name,
                model_name=provider_result.model_name,
                duration_ms=provider_result.duration_ms,
                input_tokens=provider_result.input_tokens,
                output_tokens=provider_result.output_tokens,
            ),
        )
    except ValidationError as exc:
        raise ResbudError(502) from exc


def _integrity_warnings(
    generation_input: GenerationInput,
    paper: PaperDraft,
    provider_name: str,
) -> list[ReviewWarning]:
    section_ids = {section.id for section in paper.sections}
    warnings: list[ReviewWarning] = []

    def add(code: WarningCode, message: str, section_id: str | None = None) -> None:
        warnings.append(
            ReviewWarning(
                code=code,
                severity="warning",
                message=message,
                section_id=section_id if section_id in section_ids else None,
            )
        )

    project = generation_input.project
    if project.methodology_status not in {"provided", "not_applicable"}:
        method_message = (
            "Methodology was marked unavailable. Add the actual method if it exists."
            if project.methodology_status == "not_available"
            else "Method details were not supplied. Add the actual method before submission."
        )
        add(
            "MISSING_METHOD",
            method_message,
            "methodology",
        )
    if project.dataset_or_materials_status not in {"provided", "not_applicable"}:
        dataset_message = (
            "Dataset or material details were marked unavailable. Confirm this status before "
            "submission."
            if project.dataset_or_materials_status == "not_available"
            else "Dataset or material details were not supplied. Add verified details before "
            "submission."
        )
        add(
            "MISSING_DATASET_DETAILS",
            dataset_message,
            "methodology",
        )
    if project.results_status not in {"provided", "not_applicable"}:
        result_message = (
            "Results were not collected. Do not describe outcomes without measured results."
            if project.results_status == "not_collected"
            else (
                "Results were marked unavailable. Confirm this status before submission."
                if project.results_status == "not_available"
                else "Results were not supplied. Add measured results before describing outcomes."
            )
        )
        add(
            "MISSING_RESULTS",
            result_message,
            "results",
        )
    if project.limitations_status not in {"provided", "not_applicable"}:
        limitation_message = (
            "No limitations have been identified. Review this status before submission."
            if project.limitations_status == "not_identified"
            else (
                "Limitations were marked unavailable. Confirm this status before submission."
                if project.limitations_status == "not_available"
                else "Limitations were not supplied. Identify and review limitations before "
                "submission."
            )
        )
        add(
            "MISSING_LIMITATIONS",
            limitation_message,
            "limitations",
        )
    if not generation_input.references:
        add(
            "CITATION_NEEDED",
            "No references were supplied. Add verified sources for claims that need citations.",
            "introduction",
        )
    if _has_unsupported_numeric_claim(generation_input, paper):
        add(
            "CLAIM_NEEDS_REVIEW",
            "The draft contains a numeric value not found in supplied materials. Verify it "
            "before use.",
        )
    if provider_name == "fake":
        add(
            "GENERAL_REVIEW",
            "Deterministic fake-provider demo output; it is not a research analysis.",
        )
    return warnings


def _has_unsupported_numeric_claim(generation_input: GenerationInput, paper: PaperDraft) -> bool:
    supplied_text = " ".join(
        (
            generation_input.project.title,
            generation_input.project.research_field,
            generation_input.project.research_question,
            *generation_input.project.objectives,
            generation_input.project.claimed_contribution,
            generation_input.project.methodology or "",
            generation_input.project.dataset_or_materials or "",
            generation_input.project.results or "",
            generation_input.project.limitations or "",
            generation_input.source_draft,
            *(reference.text for reference in generation_input.references),
        )
    )
    supplied_numbers = set(re.findall(r"\b\d+(?:[.,]\d+)*%?\b", supplied_text))
    output_text = " ".join(
        (paper.title, paper.abstract, *(section.content for section in paper.sections))
    )
    return any(
        number not in supplied_numbers
        for number in re.findall(r"\b\d+(?:[.,]\d+)*%?\b", output_text)
    )
