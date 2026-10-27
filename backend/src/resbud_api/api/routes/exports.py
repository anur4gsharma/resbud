"""Paper document export endpoint."""

from typing import Any

from fastapi import APIRouter, Depends
from fastapi.responses import Response

from resbud_api.api.routes.generations import ERROR_RESPONSES, REQUEST_ID_HEADER
from resbud_api.core.auth import get_current_user
from resbud_api.core.rate_limit import check_rate_limit
from resbud_api.domain.models import PaperDraft
from resbud_api.services.docx_export import DOCX_MEDIA_TYPE, export_paper_docx, safe_docx_filename

router = APIRouter(
    prefix="/api/v1/exports",
    tags=["export"],
    dependencies=[Depends(get_current_user), Depends(check_rate_limit)],
)
EXPORT_ERROR_RESPONSES: dict[int | str, dict[str, Any]] = {
    status: details
    for status, details in ERROR_RESPONSES.items()
    if status != 502 and status != 503 and status != 504
}


@router.post(
    "/docx",
    operation_id="exportDocx",
    response_class=Response,
    responses={
        **EXPORT_ERROR_RESPONSES,
        200: {
            "description": "Generated DOCX document; not stored by the server.",
            "headers": {
                **REQUEST_ID_HEADER,
                "Content-Disposition": {"schema": {"type": "string"}},
            },
            "content": {
                DOCX_MEDIA_TYPE: {"schema": {"type": "string", "format": "binary"}},
            },
        },
    },
)
async def export_docx(paper: PaperDraft) -> Response:
    content = export_paper_docx(paper)
    filename = safe_docx_filename(paper.title)
    return Response(
        content=content,
        media_type=DOCX_MEDIA_TYPE,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
