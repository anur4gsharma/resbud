"""Normalize framework and unexpected errors to the public API shape."""

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from resbud_api.core.errors import (
    ResbudError,
    ResbudRateLimitError,
    SafeHttpError,
    api_error_payload,
    safe_http_error,
)


def _request_id(request: Request) -> str:
    return getattr(request.state, "request_id", "unknown")


def _response(
    status: int,
    code: str,
    title: str,
    detail: str,
    request_id: str,
    extra_headers: dict[str, str] | None = None,
) -> JSONResponse:
    payload = api_error_payload(
        SafeHttpError(status, code, title, detail),
        request_id,
    )
    headers = {"X-Request-ID": request_id}
    if extra_headers:
        headers.update(extra_headers)
    return JSONResponse(
        status_code=status,
        content=payload.model_dump(mode="json"),
        headers=headers,
    )


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(ResbudError)
    async def application_error_handler(request: Request, exc: ResbudError) -> JSONResponse:
        error = exc.public_error
        extra_headers: dict[str, str] = {}
        if isinstance(exc, ResbudRateLimitError):
            extra_headers["Retry-After"] = str(exc.retry_after)
        return _response(
            error.status,
            error.code,
            error.title,
            error.detail,
            _request_id(request),
            extra_headers=extra_headers,
        )

    @app.exception_handler(RequestValidationError)
    async def request_validation_error_handler(
        request: Request, _exc: RequestValidationError
    ) -> JSONResponse:
        error = safe_http_error(422)
        return _response(error.status, error.code, error.title, error.detail, _request_id(request))

    @app.exception_handler(StarletteHTTPException)
    async def http_exception_handler(request: Request, exc: StarletteHTTPException) -> JSONResponse:
        error = safe_http_error(exc.status_code)
        return _response(error.status, error.code, error.title, error.detail, _request_id(request))
