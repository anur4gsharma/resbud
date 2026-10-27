import asyncio
import json
import logging
import re
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from starlette.types import Message, Scope

from resbud_api.core.errors import ResbudError
from resbud_api.core.request_boundary import RequestBoundaryMiddleware
from resbud_api.core.settings import Settings
from resbud_api.main import create_app


def _client(app: FastAPI) -> httpx.AsyncClient:
    return httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app, raise_app_exceptions=False),
        base_url="http://test",
    )


def _request(app: FastAPI, method: str, path: str, **kwargs: Any) -> httpx.Response:
    async def send_request() -> httpx.Response:
        async with _client(app) as client:
            return await client.request(method, path, **kwargs)

    return asyncio.run(send_request())


def test_liveness_and_development_readiness_include_request_ids() -> None:
    app = create_app(Settings(environment="test", _env_file=None))
    live = _request(app, "GET", "/health/live", headers={"X-Request-ID": "caller-trace-123"})
    ready = _request(app, "GET", "/health/ready")

    assert live.status_code == 200
    assert live.json() == {"status": "alive"}
    assert live.headers["x-request-id"] == "caller-trace-123"
    assert ready.status_code == 200
    assert ready.json() == {"status": "ready"}
    assert ready.headers.get("x-request-id")


def test_incomplete_production_configuration_is_not_ready_or_disclosed() -> None:
    app = create_app(Settings(environment="production", _env_file=None))
    response = _request(app, "GET", "/health/ready")

    assert response.status_code == 503
    assert response.json() == {"status": "not_ready"}
    assert "provider_api_key" not in response.text
    assert "auth_issuer" not in response.text


def test_invalid_request_id_is_replaced() -> None:
    app = create_app(Settings(environment="test", _env_file=None))
    response = _request(app, "GET", "/health/live", headers={"X-Request-ID": "bad\r\nvalue"})

    assert response.status_code == 200
    assert re.fullmatch(r"[0-9a-f-]{36}", response.headers["x-request-id"])


def test_cors_is_origin_specific_and_does_not_enable_credentials() -> None:
    settings = Settings(
        environment="development",
        cors_allowed_origins=["https://client.example.test"],
        _env_file=None,
    )
    response = _request(
        create_app(settings),
        "OPTIONS",
        "/health/live",
        headers={
            "Origin": "https://client.example.test",
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "x-request-id",
        },
    )

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "https://client.example.test"
    assert "access-control-allow-credentials" not in response.headers


def test_validation_error_is_normalized_and_does_not_echo_body() -> None:
    app = create_app(Settings(environment="test", _env_file=None))

    class RequiredNumber(BaseModel):
        value: int

    @app.post("/test/validation")
    async def validation_probe(payload: RequiredNumber) -> dict[str, int]:
        return {"value": payload.value}

    response = _request(app, "POST", "/test/validation", json={"value": "private-draft-fragment"})

    assert response.status_code == 422
    assert set(response.json()) == {"type", "title", "status", "detail", "code", "request_id"}
    assert response.json()["code"] == "VALIDATION_ERROR"
    assert response.json()["request_id"] == response.headers["x-request-id"]
    assert "private-draft-fragment" not in response.text


def test_application_error_uses_fixed_safe_error_catalog() -> None:
    app = create_app(Settings(environment="test", _env_file=None))

    @app.get("/test/application-error")
    async def application_error_probe() -> None:
        raise ResbudError(503)

    response = _request(app, "GET", "/test/application-error")

    assert response.status_code == 503
    assert response.json()["code"] == "PROVIDER_UNAVAILABLE"
    assert response.json()["detail"] == "The service is not ready. Try again later."
    assert response.headers["x-request-id"] == response.json()["request_id"]


def test_framework_http_errors_do_not_echo_exception_details() -> None:
    app = create_app(Settings(environment="test", _env_file=None))

    @app.get("/test/http-error")
    async def http_error_probe() -> None:
        raise HTTPException(status_code=404, detail="private-file-path-and-content")

    response = _request(app, "GET", "/test/http-error")

    assert response.status_code == 404
    assert response.json()["code"] == "INVALID_REQUEST"
    assert response.json()["detail"] == "The requested resource was not found."
    assert "private-file-path-and-content" not in response.text


def test_unexpected_error_is_generic_and_logs_only_operational_metadata(
    caplog: Any,
) -> None:
    app = create_app(Settings(environment="test", _env_file=None))

    @app.post("/test/failure")
    async def failure_probe() -> None:
        raise RuntimeError("provider-secret-and-private-draft")

    caplog.set_level(logging.ERROR, logger="resbud_api.errors")
    response = _request(app, "POST", "/test/failure", content="private-draft-fragment")

    assert response.status_code == 500
    assert response.json()["code"] == "INTERNAL_ERROR"
    assert response.json()["detail"] == "An unexpected error occurred."
    assert "private-draft-fragment" not in response.text
    assert "provider-secret-and-private-draft" not in response.text
    assert "private-draft-fragment" not in caplog.text
    assert "provider-secret-and-private-draft" not in caplog.text
    assert all(
        record.exc_info is None for record in caplog.records if record.name == "resbud_api.errors"
    )
    assert response.headers["x-request-id"] == response.json()["request_id"]


def test_streamed_body_limit_applies_without_content_length() -> None:
    max_bytes = 1024
    body_app_called = False
    incoming: list[Message] = [
        {"type": "http.request", "body": b"a" * 700, "more_body": True},
        {"type": "http.request", "body": b"b" * 500, "more_body": False},
    ]
    sent: list[Message] = []

    async def receive() -> Message:
        return incoming.pop(0)

    async def send(message: Message) -> None:
        sent.append(message)

    async def downstream(scope: Scope, _receive: Any, _send: Any) -> None:
        nonlocal body_app_called
        body_app_called = True

    middleware = RequestBoundaryMiddleware(downstream, max_bytes)
    scope: Scope = {
        "type": "http",
        "asgi": {"version": "3.0"},
        "method": "POST",
        "path": "/test/body",
        "headers": [],
        "state": {},
    }

    asyncio.run(middleware(scope, receive, send))

    assert not body_app_called
    assert sent[0]["status"] == 413
    assert (b"x-request-id", scope["state"]["request_id"].encode()) in sent[0]["headers"]
    body_error = json.loads(sent[1]["body"])
    assert body_error["code"] == "INPUT_TOO_LARGE"
    assert body_error["request_id"] == scope["state"]["request_id"]
