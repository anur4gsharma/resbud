"""Contain unexpected request errors before the ASGI server can log their details."""

import logging
from typing import cast

from starlette.types import ASGIApp, Message, Receive, Scope, Send

from resbud_api.core.errors import ApiErrorResponse, safe_http_error

logger = logging.getLogger("resbud_api.errors")


class SafeUnexpectedErrorMiddleware:
    """Return a generic error and log operational metadata without exception content."""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        response_started = False

        async def track_response(message: Message) -> None:
            nonlocal response_started
            if message["type"] == "http.response.start":
                response_started = True
            await send(message)

        try:
            await self.app(scope, receive, track_response)
        except Exception:
            state = cast(dict[str, object], scope.get("state", {}))
            request_id = state.get("request_id", "unknown")
            route = scope.get("route")
            route_path = getattr(route, "path", "unmatched")
            logger.error(
                "unhandled_request_error request_id=%s method=%s route=%s",
                request_id,
                scope.get("method", "unknown"),
                route_path,
            )
            if response_started:
                return

            error = safe_http_error(500)
            payload = (
                ApiErrorResponse(
                    title=error.title,
                    status=error.status,
                    detail=error.detail,
                    code=error.code,
                    request_id=str(request_id),
                )
                .model_dump_json()
                .encode("utf-8")
            )
            await send(
                {
                    "type": "http.response.start",
                    "status": error.status,
                    "headers": [
                        (b"content-type", b"application/json"),
                        (b"content-length", str(len(payload)).encode()),
                    ],
                }
            )
            await send({"type": "http.response.body", "body": payload})
