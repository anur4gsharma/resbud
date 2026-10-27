"""Liveness and configuration readiness endpoints."""

from typing import Literal

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from resbud_api.core.settings import Settings

router = APIRouter(tags=["health"])


class HealthResponse(BaseModel):
    status: Literal["alive", "ready"]


class NotReadyResponse(BaseModel):
    status: Literal["not_ready"]


REQUEST_ID_RESPONSE_HEADER = {
    "X-Request-ID": {
        "description": "Request correlation identifier.",
        "schema": {"type": "string", "maxLength": 100},
    }
}


@router.get(
    "/health/live",
    response_model=HealthResponse,
    operation_id="liveness",
    responses={200: {"headers": REQUEST_ID_RESPONSE_HEADER}},
)
async def liveness() -> HealthResponse:
    return HealthResponse(status="alive")


@router.get(
    "/health/ready",
    operation_id="readiness",
    response_model=None,
    responses={
        200: {"model": HealthResponse, "headers": REQUEST_ID_RESPONSE_HEADER},
        503: {"model": NotReadyResponse, "headers": REQUEST_ID_RESPONSE_HEADER},
    },
)
async def readiness(request: Request) -> JSONResponse:
    settings: Settings = request.app.state.settings
    if settings.readiness_issues():
        return JSONResponse(status_code=503, content={"status": "not_ready"})
    return JSONResponse(status_code=200, content={"status": "ready"})
