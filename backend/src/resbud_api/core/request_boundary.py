"""Request ID propagation and bounded request buffering."""

import re
import uuid
from collections.abc import Awaitable, Callable
from typing import cast

from starlette.types import ASGIApp, Message, Receive, Scope, Send

from resbud_api.core.errors import ApiErrorResponse, safe_http_error

REQUEST_ID_HEADER = b"x-request-id"
_VALID_REQUEST_ID = re.compile(r"[A-Za-z0-9._:-]{1,100}\Z")


def _request_id(scope: Scope) -> str:
    headers = cast(list[tuple[bytes, bytes]], scope.get("headers", []))
    for name, value in headers:
        if name.lower() == REQUEST_ID_HEADER:
            candidate = value.decode("latin-1")
            if _VALID_REQUEST_ID.fullmatch(candidate):
                return candidate
            break
    return str(uuid.uuid4())


class RequestBoundaryMiddleware:
    """Cap buffered HTTP bodies and attach a safe correlation ID to each response."""

    def __init__(self, app: ASGIApp, max_body_bytes: int) -> None:
        self.app = app
        self.max_body_bytes = max_body_bytes

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        request_id = _request_id(scope)
        scope.setdefault("state", {})["request_id"] = request_id

        async def send_with_request_id(message: Message) -> None:
            if message["type"] == "http.response.start":
                headers = list(message.get("headers", []))
                headers = [
                    (name, value) for name, value in headers if name.lower() != REQUEST_ID_HEADER
                ]
                headers.append((REQUEST_ID_HEADER, request_id.encode("ascii")))
                message = {**message, "headers": headers}
            await send(message)

        content_length = self._content_length(scope)
        if content_length is not None and content_length > self.max_body_bytes:
            await self._send_too_large(send_with_request_id, request_id)
            return

        chunks: list[bytes] = []
        body_size = 0
        while True:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            if message["type"] != "http.request":
                continue
            chunk = message.get("body", b"")
            body_size += len(chunk)
            if body_size > self.max_body_bytes:
                await self._send_too_large(send_with_request_id, request_id)
                return
            chunks.append(chunk)
            if not message.get("more_body", False):
                break

        body = b"".join(chunks)
        replayed = False

        async def replay_receive() -> Message:
            nonlocal replayed
            if not replayed:
                replayed = True
                return {"type": "http.request", "body": body, "more_body": False}
            return await receive()

        await self.app(scope, replay_receive, send_with_request_id)

    @staticmethod
    def _content_length(scope: Scope) -> int | None:
        headers = cast(list[tuple[bytes, bytes]], scope.get("headers", []))
        for name, value in headers:
            if name.lower() == b"content-length":
                try:
                    return int(value)
                except ValueError:
                    return None
        return None

    @staticmethod
    async def _send_too_large(
        send: Callable[[Message], Awaitable[None]],
        request_id: str,
    ) -> None:
        error = safe_http_error(413)
        payload = (
            ApiErrorResponse(
                title=error.title,
                status=error.status,
                detail=error.detail,
                code=error.code,
                request_id=request_id,
            )
            .model_dump_json()
            .encode("utf-8")
        )
        await send(
            {
                "type": "http.response.start",
                "status": 413,
                "headers": [
                    (b"content-type", b"application/json"),
                    (b"content-length", str(len(payload)).encode()),
                ],
            }
        )
        await send({"type": "http.response.body", "body": payload})
