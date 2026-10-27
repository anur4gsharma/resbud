"""Targeted section regeneration tests through FastAPI and the service boundary."""

import asyncio
import json
from pathlib import Path
from typing import Any

import httpx
import pytest
from fastapi import FastAPI

from resbud_api.core.settings import Settings
from resbud_api.domain.models import SectionRegenerationRequest
from resbud_api.main import create_app
from resbud_api.providers.base import SectionRegenerationInput
from resbud_api.providers.fake import FakeOutcome, FakeProvider
from resbud_api.services.generation import regenerate_section

FIXTURES = Path(__file__).parent / "fixtures"
REQUEST = json.loads((FIXTURES / "generation-request.valid.json").read_text())
PAPER = json.loads((FIXTURES / "paper-draft.valid.json").read_text())
PATH = "/api/v1/generations/sections"


def _payload() -> dict[str, Any]:
    current_paper = json.loads(json.dumps(PAPER))
    current_paper["sections"][1]["content"] = "User-edited results placeholder."
    return {
        "schema_version": 1,
        "generation_request": REQUEST,
        "current_paper": current_paper,
        "section_id": "results",
        "user_instruction": "Keep the section cautious and preserve the original evidence.",
    }


def _post(app: FastAPI, payload: object) -> httpx.Response:
    async def send() -> httpx.Response:
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app, raise_app_exceptions=False),
            base_url="http://test",
        ) as client:
            return await client.post(PATH, json=payload)

    return asyncio.run(send())


def _app(provider: FakeProvider) -> FastAPI:
    return create_app(
        Settings(environment="test", generation_provider="fake", _env_file=None),
        generation_provider=provider,
    )


class CaptureFakeProvider(FakeProvider):
    last_input: SectionRegenerationInput | None = None

    async def regenerate_section(self, regeneration_input: SectionRegenerationInput):
        self.last_input = regeneration_input
        return await super().regenerate_section(regeneration_input)


def test_success_returns_only_a_targeted_preview_and_integrity_warnings() -> None:
    provider = CaptureFakeProvider()
    payload = _payload()

    response = _post(_app(provider), payload)

    assert response.status_code == 200
    body = response.json()
    assert set(body) == {"schema_version", "section", "review_warnings"}
    assert body["section"]["id"] == "results"
    assert body["section"]["content"] == "[PROVIDE RESULTS DETAILS]"
    assert body["section"]["state"] == "needs_input"
    assert {warning["code"] for warning in body["review_warnings"]} >= {
        "MISSING_RESULTS",
        "GENERAL_REVIEW",
    }
    assert provider.call_count == 1
    assert provider.last_input is not None
    assert provider.last_input.current_paper.title == PAPER["title"]
    assert provider.last_input.target_section.id == "results"
    assert provider.last_input.user_instruction == payload["user_instruction"]
    assert "PaperSection JSON Schema" in provider.last_input.prompt.system_instructions


def test_accepting_preview_changes_only_target_and_preserves_paper_fields() -> None:
    payload = _payload()
    request = SectionRegenerationRequest.model_validate(payload)
    original_json = request.current_paper.model_dump_json()
    original_non_target = request.current_paper.sections[0].model_dump_json()
    original_refs = [reference.model_dump_json() for reference in request.current_paper.references]

    proposal = asyncio.run(regenerate_section(request, FakeProvider()))

    # The service proposal leaves the supplied paper object untouched until client acceptance.
    assert request.current_paper.model_dump_json() == original_json
    accepted = request.current_paper.model_copy(
        update={
            "sections": [request.current_paper.sections[0], proposal.section],
        }
    )

    assert accepted.sections[0].model_dump_json() == original_non_target
    assert [reference.model_dump_json() for reference in accepted.references] == original_refs
    assert accepted.title == request.current_paper.title
    assert accepted.abstract == request.current_paper.abstract
    assert accepted.keywords == request.current_paper.keywords
    assert accepted.schema_version == request.current_paper.schema_version
    assert accepted.review_warnings == request.current_paper.review_warnings


def test_missing_target_and_unsupported_state_are_rejected_before_provider_call() -> None:
    provider = FakeProvider()
    missing = _payload()
    missing["section_id"] = "discussion"

    missing_response = _post(_app(provider), missing)

    assert missing_response.status_code == 422
    assert missing_response.json()["code"] == "VALIDATION_ERROR"
    assert provider.call_count == 0

    unsupported = _payload()
    unsupported["current_paper"]["sections"][1]["state"] = "not_applicable"
    unsupported_response = _post(_app(provider), unsupported)

    assert unsupported_response.status_code == 422
    assert unsupported_response.json()["code"] == "VALIDATION_ERROR"
    assert provider.call_count == 0


def test_invalid_request_is_rejected_before_provider_call() -> None:
    provider = FakeProvider()
    invalid = _payload()
    invalid["unexpected"] = "private"

    response = _post(_app(provider), invalid)

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
def test_provider_failures_use_stable_errors_and_preserve_request_id(
    outcome: FakeOutcome, status: int, code: str
) -> None:
    provider = FakeProvider(outcome)
    app = _app(provider)

    async def send() -> httpx.Response:
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app, raise_app_exceptions=False),
            base_url="http://test",
        ) as client:
            return await client.post(
                PATH,
                json=_payload(),
                headers={"X-Request-ID": "section-regeneration-123"},
            )

    response = asyncio.run(send())

    assert response.status_code == status
    assert response.json()["code"] == code
    assert response.json()["request_id"] == "section-regeneration-123"
    assert response.headers["x-request-id"] == "section-regeneration-123"
    assert provider.call_count == 1


class EmptyReplacementProvider:
    async def regenerate_section(self, _regeneration_input: SectionRegenerationInput):
        from resbud_api.providers.base import ProviderResult

        return ProviderResult(
            structured_output=(
                '{"id":"results","heading":"Results","content":"  ","state":"draft"}'
            ),
            provider_name="test",
            model_name="test",
            duration_ms=0,
        )


def test_empty_provider_replacement_fails_closed() -> None:
    app = create_app(
        Settings(environment="test", _env_file=None),
        generation_provider=EmptyReplacementProvider(),
    )

    response = _post(app, _payload())

    assert response.status_code == 502
    assert response.json()["code"] == "PROVIDER_INVALID_RESPONSE"


@pytest.mark.parametrize(
    ("section_id", "state"),
    [("introduction", "draft"), ("results", "not_applicable")],
)
def test_mismatched_or_unsupported_provider_section_fails_closed(
    section_id: str, state: str
) -> None:
    from resbud_api.providers.base import ProviderResult

    class InvalidSectionProvider:
        async def regenerate_section(self, _regeneration_input: SectionRegenerationInput):
            return ProviderResult(
                structured_output=json.dumps(
                    {
                        "id": section_id,
                        "heading": "Results",
                        "content": "A nonblank replacement.",
                        "state": state,
                    }
                ),
                provider_name="test",
                model_name="test",
                duration_ms=0,
            )

    app = create_app(
        Settings(environment="test", _env_file=None),
        generation_provider=InvalidSectionProvider(),
    )

    response = _post(app, _payload())

    assert response.status_code == 502
    assert response.json()["code"] == "PROVIDER_INVALID_RESPONSE"


def test_fastapi_openapi_exposes_regeneration_contract() -> None:
    operation = _app(FakeProvider()).openapi()["paths"][PATH]["post"]

    assert operation["operationId"] == "regenerateSection"
    assert operation["responses"]["200"]["content"]["application/json"]["schema"]
    assert operation["responses"]["422"]["content"]["application/json"]["schema"]
