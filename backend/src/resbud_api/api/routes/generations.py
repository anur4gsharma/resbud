"""Generation endpoint with provider selection kept behind dependency injection."""

from typing import Annotated, Any, cast

from fastapi import APIRouter, Depends, Request

from resbud_api.core.errors import ApiErrorResponse
from resbud_api.domain.models import (
    GenerationRequest,
    GenerationResponse,
    SectionRegenerationRequest,
    SectionRegenerationResponse,
)
from resbud_api.providers.base import GenerationProvider
from resbud_api.services.generation import generate_paper, regenerate_section

router = APIRouter(prefix="/api/v1/generations", tags=["generation"])
REQUEST_ID_HEADER = {
    "X-Request-ID": {
        "description": "Request correlation identifier.",
        "schema": {"type": "string", "maxLength": 100},
    }
}
ERROR_RESPONSES: dict[int | str, dict[str, Any]] = {
    status: {
        "model": ApiErrorResponse,
        "description": "Stable application error response.",
        "headers": REQUEST_ID_HEADER,
    }
    for status in (400, 401, 403, 405, 413, 415, 422, 429, 500, 502, 503, 504)
}


def get_generation_provider(request: Request) -> GenerationProvider:
    return cast(GenerationProvider, request.app.state.generation_provider)


@router.post(
    "",
    response_model=GenerationResponse,
    operation_id="generatePaper",
    responses={**ERROR_RESPONSES, 200: {"headers": REQUEST_ID_HEADER}},
)
async def create_generation(
    generation_request: GenerationRequest,
    provider: Annotated[GenerationProvider, Depends(get_generation_provider)],
) -> GenerationResponse:
    return await generate_paper(generation_request, provider)


@router.post(
    "/sections",
    response_model=SectionRegenerationResponse,
    operation_id="regenerateSection",
    responses={**ERROR_RESPONSES, 200: {"headers": REQUEST_ID_HEADER}},
)
async def create_section_regeneration(
    regeneration_request: SectionRegenerationRequest,
    provider: Annotated[GenerationProvider, Depends(get_generation_provider)],
) -> SectionRegenerationResponse:
    return await regenerate_section(regeneration_request, provider)
