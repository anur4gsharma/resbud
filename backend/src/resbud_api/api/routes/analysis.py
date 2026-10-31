"""Research analysis and document extraction API endpoints."""

from __future__ import annotations

import base64
from typing import Annotated, cast

from fastapi import APIRouter, Depends, Request, UploadFile

from resbud_api.core.auth import get_current_user
from resbud_api.core.rate_limit import check_rate_limit
from resbud_api.domain.models import (
    DocumentExtractRequest,
    DocumentExtractResponse,
    ResearchAnalysisRequest,
    ResearchAnalysisResponse,
)
from resbud_api.providers.base import GenerationProvider
from resbud_api.services.analysis import (
    DocumentExtractionError,
    assess_research_quality,
    extract_document_text,
)

router = APIRouter(prefix="/api/v1", tags=["Analysis & Ingestion"])


def get_generation_provider(request: Request) -> GenerationProvider:
    return cast(GenerationProvider, request.app.state.generation_provider)


@router.post(
    "/analyze",
    response_model=ResearchAnalysisResponse,
    operation_id="analyzeResearch",
    dependencies=[Depends(check_rate_limit), Depends(get_current_user)],
)
async def analyze_research_endpoint(
    request: ResearchAnalysisRequest,
    provider: Annotated[GenerationProvider, Depends(get_generation_provider)],
) -> ResearchAnalysisResponse:
    """Analyze uploaded research material and generate dynamic outline."""
    analyzer = getattr(provider, "analyze_research", None)
    if callable(analyzer):
        result: ResearchAnalysisResponse = await analyzer(request)
        return result
    return assess_research_quality(request)


@router.post(
    "/documents/extract",
    response_model=DocumentExtractResponse,
    operation_id="extractDocument",
    dependencies=[Depends(check_rate_limit), Depends(get_current_user)],
)
async def extract_document_endpoint(
    file: UploadFile | None = None,
    body: DocumentExtractRequest | None = None,
) -> DocumentExtractResponse:
    """Extract readable text from .txt, .md, .docx, or .pdf files."""
    if file is not None:
        file_name = file.filename or "uploaded_document"
        content_bytes = await file.read()
    elif body is not None:
        file_name = body.file_name
        if body.content_base64:
            try:
                content_bytes = base64.b64decode(body.content_base64)
            except Exception as exc:
                raise DocumentExtractionError("Invalid base64 document content.") from exc
        elif body.text_content:
            content_bytes = body.text_content.encode("utf-8")
        else:
            raise DocumentExtractionError("No file or document content provided.")
    else:
        raise DocumentExtractionError("No document payload provided.")

    text, fmt = extract_document_text(file_name, content_bytes)
    return DocumentExtractResponse(
        file_name=file_name,
        format=fmt,
        text=text,
        char_count=len(text),
    )
