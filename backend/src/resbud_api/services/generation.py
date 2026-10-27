"""Synchronous paper-generation use case with strict provider-output validation."""

import json
from uuid import uuid4

from pydantic import ValidationError

from resbud_api.core.errors import ResbudError
from resbud_api.domain.models import (
    GenerationMeta,
    GenerationRequest,
    GenerationResponse,
    PaperDraft,
)
from resbud_api.providers.base import (
    GenerationProvider,
    ProviderRateLimited,
    ProviderTimeout,
    ProviderUnavailable,
    ResearchBrief,
)
from resbud_api.services.integrity import has_meaningful_content, run_integrity_checks
from resbud_api.services.prompt_builder import build_generation_input


def normalize_research_brief(request: GenerationRequest) -> ResearchBrief:
    """Normalize line endings and boundary whitespace without rewriting research claims."""
    return ResearchBrief(
        project=request.project,
        source_draft=request.source_draft.replace("\r\n", "\n").replace("\r", "\n").strip(),
        references=tuple(request.references),
        preferences=request.preferences,
    )


async def generate_paper(
    request: GenerationRequest,
    provider: GenerationProvider,
) -> GenerationResponse:
    brief = normalize_research_brief(request)
    generation_input = build_generation_input(brief)
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

    if not has_meaningful_content(paper):
        raise ResbudError(502)
    if paper.references != list(brief.references):
        raise ResbudError(502)

    warnings = run_integrity_checks(brief, paper, provider_result.provider_name)
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
