"""Security, authentication, rate limits, and privacy release gate tests."""

import asyncio
import json
import logging
import time
from typing import Any

import httpx
from fastapi import FastAPI
from pydantic import SecretStr

from resbud_api.core.auth import create_token
from resbud_api.core.settings import Settings
from resbud_api.main import create_app
from resbud_api.providers.fake import FakeProvider


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


def _sample_generation_request() -> dict[str, Any]:
    return {
        "schema_version": 1,
        "project": {
            "title": "Quantum Error Mitigation",
            "research_field": "Quantum Information",
            "research_question": "Can zero-noise extrapolation improve fidelity?",
            "objectives": ["Measure gate error rates"],
            "claimed_contribution": "New extrapolation curve",
            "methodology_status": "provided",
            "methodology": "Simulated randomized benchmarking with Clifford gates.",
            "dataset_or_materials_status": "not_available",
            "results_status": "not_collected",
            "limitations_status": "not_identified",
        },
        "source_draft": (
            "We analyze zero-noise extrapolation on noisy intermediate-scale quantum devices."
        ),
        "references": [],
        "preferences": {
            "target_word_count": 1500,
            "desired_sections": ["introduction", "methodology", "results"],
            "citation_style": "user_supplied",
        },
    }


def test_production_readiness_fails_closed_when_auth_is_missing() -> None:
    settings = Settings(
        environment="production",
        generation_provider="openai",
        provider_model="gpt-4o",
        provider_api_key=SecretStr("sk-prod-test-key"),
        # auth_issuer and auth_audience omitted
        _env_file=None,
    )
    assert "auth_issuer" in settings.readiness_issues()
    assert "auth_audience" in settings.readiness_issues()

    app = create_app(settings)
    ready = _request(app, "GET", "/health/ready")
    assert ready.status_code == 503
    assert ready.json() == {"status": "not_ready"}


def test_production_rejects_unauthenticated_requests_with_401() -> None:
    settings = Settings(
        environment="production",
        generation_provider="openai",
        provider_model="gpt-4o",
        provider_api_key=SecretStr("sk-prod-test-key"),
        auth_issuer="https://auth.example.com",
        auth_audience="resbud-api",
        _env_file=None,
    )
    app = create_app(settings)

    response = _request(
        app,
        "POST",
        "/api/v1/generations",
        json=_sample_generation_request(),
    )

    assert response.status_code == 401
    assert response.json()["code"] == "UNAUTHENTICATED"
    assert response.json()["detail"] == "Sign in and try again."
    assert "sk-prod-test-key" not in response.text


def test_production_rejects_malformed_authorization_header() -> None:
    settings = Settings(
        environment="production",
        generation_provider="openai",
        provider_model="gpt-4o",
        provider_api_key=SecretStr("sk-prod-test-key"),
        auth_issuer="https://auth.example.com",
        auth_audience="resbud-api",
        _env_file=None,
    )
    app = create_app(settings)

    # Missing 'Bearer ' prefix
    response = _request(
        app,
        "POST",
        "/api/v1/generations",
        headers={"Authorization": "Basic dXNlcjpwYXNz"},
        json=_sample_generation_request(),
    )
    assert response.status_code == 401
    assert response.json()["code"] == "UNAUTHENTICATED"

    # Empty bearer token
    response2 = _request(
        app,
        "POST",
        "/api/v1/generations",
        headers={"Authorization": "Bearer   "},
        json=_sample_generation_request(),
    )
    assert response2.status_code == 401
    assert response2.json()["code"] == "UNAUTHENTICATED"


def test_production_accepts_valid_jwt_bearer_token() -> None:
    signing_key = SecretStr("secret-jwt-hmac-key-1234567890")
    settings = Settings(
        # Development environment with auth_issuer configured allows testing FakeProvider
        environment="development",
        generation_provider="fake",
        auth_issuer="https://auth.example.com",
        auth_audience="resbud-api",
        auth_signing_key=signing_key,
        _env_file=None,
    )
    app = create_app(settings, generation_provider=FakeProvider())

    token = create_token(
        payload={
            "sub": "user_scientist_42",
            "iss": "https://auth.example.com",
            "aud": "resbud-api",
            "exp": time.time() + 3600,
            "nbf": time.time() - 10,
        },
        signing_key=signing_key,
    )

    response = _request(
        app,
        "POST",
        "/api/v1/generations",
        headers={"Authorization": f"Bearer {token}"},
        json=_sample_generation_request(),
    )

    assert response.status_code == 200
    assert response.json()["schema_version"] == 1
    assert token not in response.text
    assert "secret-jwt-hmac-key" not in response.text


def test_rejects_expired_jwt_token() -> None:
    signing_key = SecretStr("secret-jwt-hmac-key-1234567890")
    settings = Settings(
        environment="development",
        generation_provider="fake",
        auth_issuer="https://auth.example.com",
        auth_audience="resbud-api",
        auth_signing_key=signing_key,
        _env_file=None,
    )
    app = create_app(settings, generation_provider=FakeProvider())

    expired_token = create_token(
        payload={
            "sub": "user_scientist_42",
            "iss": "https://auth.example.com",
            "aud": "resbud-api",
            "exp": time.time() - 120,  # Expired 2 minutes ago
        },
        signing_key=signing_key,
    )

    response = _request(
        app,
        "POST",
        "/api/v1/generations",
        headers={"Authorization": f"Bearer {expired_token}"},
        json=_sample_generation_request(),
    )

    assert response.status_code == 401
    assert response.json()["code"] == "UNAUTHENTICATED"


def test_rejects_jwt_with_mismatched_issuer_or_audience() -> None:
    signing_key = SecretStr("secret-jwt-hmac-key-1234567890")
    settings = Settings(
        environment="development",
        generation_provider="fake",
        auth_issuer="https://auth.example.com",
        auth_audience="resbud-api",
        auth_signing_key=signing_key,
        _env_file=None,
    )
    app = create_app(settings, generation_provider=FakeProvider())

    # Wrong issuer
    wrong_iss_token = create_token(
        payload={
            "sub": "user_scientist_42",
            "iss": "https://malicious.issuer.test",
            "aud": "resbud-api",
            "exp": time.time() + 3600,
        },
        signing_key=signing_key,
    )
    resp1 = _request(
        app,
        "POST",
        "/api/v1/generations",
        headers={"Authorization": f"Bearer {wrong_iss_token}"},
        json=_sample_generation_request(),
    )
    assert resp1.status_code == 401

    # Wrong audience
    wrong_aud_token = create_token(
        payload={
            "sub": "user_scientist_42",
            "iss": "https://auth.example.com",
            "aud": "different-audience",
            "exp": time.time() + 3600,
        },
        signing_key=signing_key,
    )
    resp2 = _request(
        app,
        "POST",
        "/api/v1/generations",
        headers={"Authorization": f"Bearer {wrong_aud_token}"},
        json=_sample_generation_request(),
    )
    assert resp2.status_code == 401


def test_rejects_jwt_with_invalid_signature() -> None:
    valid_key = SecretStr("secret-jwt-hmac-key-1234567890")
    attacker_key = SecretStr("attacker-wrong-key-9999999999")
    settings = Settings(
        environment="development",
        generation_provider="fake",
        auth_issuer="https://auth.example.com",
        auth_audience="resbud-api",
        auth_signing_key=valid_key,
        _env_file=None,
    )
    app = create_app(settings, generation_provider=FakeProvider())

    tampered_token = create_token(
        payload={
            "sub": "user_scientist_42",
            "iss": "https://auth.example.com",
            "aud": "resbud-api",
            "exp": time.time() + 3600,
        },
        signing_key=attacker_key,
    )

    response = _request(
        app,
        "POST",
        "/api/v1/generations",
        headers={"Authorization": f"Bearer {tampered_token}"},
        json=_sample_generation_request(),
    )

    assert response.status_code == 401
    assert response.json()["code"] == "UNAUTHENTICATED"


def test_rate_limiter_throttles_excessive_requests_with_retry_after() -> None:
    settings = Settings(
        environment="test",
        generation_provider="fake",
        rate_limit_per_minute=2,  # Low limit for testing
        _env_file=None,
    )
    app = create_app(settings, generation_provider=FakeProvider())

    # Request 1: allowed
    r1 = _request(
        app,
        "POST",
        "/api/v1/generations",
        headers={"X-Forwarded-For": "203.0.113.10"},
        json=_sample_generation_request(),
    )
    assert r1.status_code == 200

    # Request 2: allowed
    r2 = _request(
        app,
        "POST",
        "/api/v1/generations",
        headers={"X-Forwarded-For": "203.0.113.10"},
        json=_sample_generation_request(),
    )
    assert r2.status_code == 200

    # Request 3: throttled
    r3 = _request(
        app,
        "POST",
        "/api/v1/generations",
        headers={"X-Forwarded-For": "203.0.113.10"},
        json=_sample_generation_request(),
    )
    assert r3.status_code == 429
    assert r3.json()["code"] == "RATE_LIMITED"
    assert "Retry-After" in r3.headers
    retry_after = int(r3.headers["Retry-After"])
    assert 1 <= retry_after <= 60

    # Different IP is not throttled
    r_diff = _request(
        app,
        "POST",
        "/api/v1/generations",
        headers={"X-Forwarded-For": "198.51.100.55"},
        json=_sample_generation_request(),
    )
    assert r_diff.status_code == 200


def test_oversized_payload_rejected_at_boundary_before_processing() -> None:
    settings = Settings(
        environment="test",
        max_request_body_bytes=2048,  # 2 KB limit
        _env_file=None,
    )
    app = create_app(settings)

    oversized_body = json.dumps({
        **_sample_generation_request(),
        "source_draft": "x" * 5000,
    })

    response = _request(
        app,
        "POST",
        "/api/v1/generations",
        content=oversized_body,
        headers={"Content-Type": "application/json"},
    )

    assert response.status_code == 413
    assert response.json()["code"] == "INPUT_TOO_LARGE"
    assert response.headers["x-request-id"]


def test_zero_content_and_secret_redaction_in_logs(caplog: Any) -> None:
    caplog.set_level(logging.DEBUG)
    settings = Settings(
        environment="test",
        generation_provider="fake",
        provider_api_key=SecretStr("super-confidential-openai-key"),
        _env_file=None,
    )
    app = create_app(settings, generation_provider=FakeProvider())

    private_source_text = "CONFIDENTIAL_UNPUBLISHED_GENOME_DATA_XYZ_987"

    req = _sample_generation_request()
    req["source_draft"] = private_source_text

    response = _request(
        app,
        "POST",
        "/api/v1/generations",
        json=req,
    )

    assert response.status_code == 200

    # Ensure logs do NOT contain private text or provider keys
    assert "super-confidential-openai-key" not in caplog.text
    assert private_source_text not in caplog.text
