"""End-to-end generation flow tests through the ASGI app."""

import asyncio
import json
import logging
from pathlib import Path
from typing import Any

import httpx
import pytest
from fastapi import FastAPI
from pydantic import ValidationError

from resbud_api.core.settings import Settings
from resbud_api.main import create_app
from resbud_api.providers.base import GenerationInput, ProviderResult
from resbud_api.providers.fake import FakeOutcome, FakeProvider

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests" / "fixtures"
REQUEST = json.loads((FIXTURES / "generation-request.valid.json").read_text())


def _request(app: FastAPI, body: object, headers: dict[str, str] | None = None) -> httpx.Response:
    async def send_request() -> httpx.Response:
        transport = httpx.ASGITransport(app=app, raise_app_exceptions=False)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            return await client.post("/api/v1/generations", json=body, headers=headers or {})

    return asyncio.run(send_request())


def _app(provider: FakeProvider) -> FastAPI:
    return create_app(
        Settings(environment="test", generation_provider="fake", _env_file=None),
        generation_provider=provider,
    )


def test_fake_provider_generates_contract_valid_deterministic_paper() -> None:
    provider = FakeProvider()
    response = _request(_app(provider), REQUEST)

    assert response.status_code == 200
    result = response.json()
    result.pop("generation_id")
    expected = json.loads((FIXTURES / "generation-response.fake.json").read_text())
    assert result == expected
    assert result["meta"]["provider_name"] == "fake"
    assert result["paper"]["references"] == REQUEST["references"]
    assert provider.call_count == 1


def test_fastapi_openapi_exposes_the_generation_operation_and_error_contract() -> None:
    operation = _app(FakeProvider()).openapi()["paths"]["/api/v1/generations"]["post"]

    assert operation["operationId"] == "generatePaper"
    assert operation["requestBody"]["content"]["application/json"]["schema"]["$ref"].endswith(
        "/GenerationRequest"
    )
    assert operation["responses"]["200"]["headers"]["X-Request-ID"]
    for status in ("422", "429", "502", "503", "504"):
        assert operation["responses"][status]["content"]["application/json"]["schema"]
        assert operation["responses"][status]["headers"]["X-Request-ID"]


def test_invalid_request_is_rejected_before_provider_invocation() -> None:
    provider = FakeProvider()
    invalid = {**REQUEST, "source_draft": "   "}

    response = _request(_app(provider), invalid)

    assert response.status_code == 422
    assert response.json()["code"] == "VALIDATION_ERROR"
    assert provider.call_count == 0


@pytest.mark.parametrize(
    ("outcome", "status", "code"),
    [
        (FakeOutcome.TIMEOUT, 504, "PROVIDER_TIMEOUT"),
        (FakeOutcome.UNAVAILABLE, 503, "PROVIDER_UNAVAILABLE"),
        (FakeOutcome.RATE_LIMITED, 429, "RATE_LIMITED"),
        (FakeOutcome.MALFORMED, 502, "PROVIDER_INVALID_RESPONSE"),
    ],
)
def test_provider_failures_map_to_stable_request_correlated_errors(
    outcome: FakeOutcome, status: int, code: str
) -> None:
    provider = FakeProvider(outcome)
    response = _request(_app(provider), REQUEST, headers={"X-Request-ID": "generation-failure-123"})

    assert response.status_code == status
    assert response.json()["code"] == code
    assert response.json()["request_id"] == "generation-failure-123"
    assert response.headers["x-request-id"] == "generation-failure-123"
    assert "Example Study" not in response.text
    assert provider.call_count == 1


class InvalidSchemaProvider:
    async def generate_paper(self, _generation_input: GenerationInput) -> ProviderResult:
        return ProviderResult(
            structured_output='{"schema_version":1,"title":"x","unexpected":true}',
            provider_name="test",
            model_name="test",
            duration_ms=0,
        )


def test_json_that_does_not_match_the_paper_contract_fails_closed() -> None:
    response = _request(
        create_app(
            Settings(environment="test", _env_file=None),
            generation_provider=InvalidSchemaProvider(),
        ),
        REQUEST,
    )

    assert response.status_code == 502
    assert response.json()["code"] == "PROVIDER_INVALID_RESPONSE"


class InventedReferenceProvider:
    async def generate_paper(self, generation_input: GenerationInput) -> ProviderResult:
        paper = await FakeProvider().generate_paper(generation_input)
        data: dict[str, Any] = json.loads(paper.structured_output)
        data["references"] = [{"id": "new_ref", "text": "Invented Author (2024)."}]
        return ProviderResult(json.dumps(data), "test", "test", 0)


def test_provider_cannot_add_unprovided_references() -> None:
    response = _request(
        create_app(
            Settings(environment="test", _env_file=None),
            generation_provider=InventedReferenceProvider(),
        ),
        REQUEST,
    )

    assert response.status_code == 502
    assert response.json()["code"] == "PROVIDER_INVALID_RESPONSE"


class UnsupportedNumberProvider:
    async def generate_paper(self, generation_input: GenerationInput) -> ProviderResult:
        result = await FakeProvider().generate_paper(generation_input)
        paper = json.loads(result.structured_output)
        paper["abstract"] = "The study achieved 98% accuracy."
        return ProviderResult(json.dumps(paper), "test", "test", 0)


def test_integrity_check_flags_numeric_claims_absent_from_user_material() -> None:
    response = _request(
        create_app(
            Settings(environment="test", _env_file=None),
            generation_provider=UnsupportedNumberProvider(),
        ),
        REQUEST,
    )

    assert response.status_code == 200
    assert "CLAIM_NEEDS_REVIEW" in {
        warning["code"] for warning in response.json()["review_warnings"]
    }


def test_generation_does_not_persist_or_log_source_content(caplog: Any) -> None:
    marker = "PRIVATE-SOURCE-DO-NOT-LOG-7d3f"
    request = {**REQUEST, "source_draft": marker}
    provider = FakeProvider()
    app = _app(provider)
    caplog.set_level(logging.DEBUG)

    response = _request(app, request)

    assert response.status_code == 200
    assert marker in response.text
    assert marker not in caplog.text
    assert set(app.state.__dict__) == {"_state"}
    assert vars(provider) == {"outcome": FakeOutcome.SUCCESS, "call_count": 1}


def test_production_rejects_fake_provider_configuration() -> None:
    with pytest.raises(ValidationError):
        Settings(environment="production", generation_provider="fake", _env_file=None)

    with pytest.raises(ValueError, match="cannot be injected in production"):
        create_app(
            Settings(environment="production", _env_file=None),
            generation_provider=FakeProvider(),
        )
