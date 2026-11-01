"""Unit tests for Gemini adapter behavior using mocked HTTP responses."""

import asyncio
import json
from pathlib import Path
from typing import Any

import httpx
import pytest

from resbud_api.core.settings import Settings
from resbud_api.domain.models import GenerationRequest, PaperDraft, PaperSection
from resbud_api.providers.base import (
    ProviderInvalidResponse,
    ProviderRateLimited,
    ProviderTimeout,
    ProviderUnavailable,
    SectionRegenerationInput,
)
from resbud_api.providers.gemini_provider import GeminiProvider, strip_code_fences
from resbud_api.services.generation import normalize_research_brief
from resbud_api.services.prompt_builder import (
    build_generation_input,
    build_section_regeneration_input,
)

FIXTURES = Path(__file__).parent / "fixtures"
REQUEST = json.loads((FIXTURES / "generation-request.valid.json").read_text())
PAPER_DATA = json.loads((FIXTURES / "paper-draft.valid.json").read_text())


def _settings(**overrides: Any) -> Settings:
    defaults = {
        "environment": "test",
        "generation_provider": "gemini",
        "provider_model": "gemini-2.5-flash",
        "provider_api_key": "synthetic-test-gemini-key",
        "_env_file": None,
    }
    defaults.update(overrides)
    return Settings(**defaults)


def _input() -> Any:
    request = GenerationRequest.model_validate(REQUEST)
    brief = normalize_research_brief(request)
    return build_generation_input(brief)


def _gemini_payload(text: str, model_version: str = "gemini-2.5-flash") -> dict[str, Any]:
    return {
        "candidates": [
            {
                "content": {
                    "parts": [{"text": text}],
                    "role": "model",
                },
                "finishReason": "STOP",
            }
        ],
        "usageMetadata": {
            "promptTokenCount": 110,
            "candidatesTokenCount": 85,
        },
        "modelVersion": model_version,
    }


def test_gemini_adapter_uses_schema_mode_and_normalizes_metadata() -> None:
    paper = PaperDraft.model_validate(PAPER_DATA)
    payload = _gemini_payload(paper.model_dump_json())

    recorded_requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        recorded_requests.append(request)
        return httpx.Response(
            200,
            json=payload,
            headers={"x-goog-request-id": "gemini-req-789"},
            request=request,
        )

    transport = httpx.MockTransport(handler)
    client = httpx.AsyncClient(transport=transport)
    provider = GeminiProvider(_settings(), client=client)

    result = asyncio.run(provider.generate_paper(_input()))

    assert json.loads(result.structured_output) == paper.model_dump(mode="json")
    assert result.provider_name == "gemini"
    assert result.model_name == "gemini-2.5-flash"
    assert result.input_tokens == 110
    assert result.output_tokens == 85
    assert result.request_id == "gemini-req-789"

    assert len(recorded_requests) == 1
    req = recorded_requests[0]
    assert req.headers["x-goog-api-key"] == "synthetic-test-gemini-key"
    assert "models/gemini-2.5-flash:generateContent" in str(req.url)

    body = json.loads(req.content.decode("utf-8"))
    assert body["generationConfig"]["responseMimeType"] == "application/json"
    assert "responseSchema" in body["generationConfig"]


def test_gemini_adapter_handles_code_fenced_json() -> None:
    paper = PaperDraft.model_validate(PAPER_DATA)
    fenced = f"```json\n{paper.model_dump_json()}\n```"
    payload = _gemini_payload(fenced)

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=payload, request=request)

    transport = httpx.MockTransport(handler)
    client = httpx.AsyncClient(transport=transport)
    provider = GeminiProvider(_settings(), client=client)

    result = asyncio.run(provider.generate_paper(_input()))
    assert json.loads(result.structured_output) == paper.model_dump(mode="json")


def test_strip_code_fences_utility() -> None:
    raw = '{"key": "value"}'
    assert strip_code_fences(raw) == raw
    assert strip_code_fences(f"```json\n{raw}\n```") == raw
    assert strip_code_fences(f"```\n{raw}\n```") == raw


def test_gemini_adapter_regenerates_section() -> None:
    request = GenerationRequest.model_validate(REQUEST)
    brief = normalize_research_brief(request)
    current_paper = PaperDraft.model_validate(PAPER_DATA)
    target = current_paper.sections[1]
    regeneration_input: SectionRegenerationInput = build_section_regeneration_input(
        brief,
        current_paper,
        target,
        "Update the section with latest results.",
    )
    replacement = PaperSection(
        id=target.id,
        heading=target.heading,
        content="Updated experimental results and detailed observations.",
        state="draft",
    )
    payload = _gemini_payload(replacement.model_dump_json())

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            json=payload,
            headers={"x-goog-request-id": "gemini-sec-123"},
            request=request,
        )

    transport = httpx.MockTransport(handler)
    client = httpx.AsyncClient(transport=transport)
    provider = GeminiProvider(_settings(), client=client)

    result = asyncio.run(provider.regenerate_section(regeneration_input))

    assert json.loads(result.structured_output) == replacement.model_dump(mode="json")
    assert result.request_id == "gemini-sec-123"


def test_gemini_timeout_normalized() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("Timeout from Gemini", request=request)

    transport = httpx.MockTransport(handler)
    client = httpx.AsyncClient(transport=transport)
    provider = GeminiProvider(_settings(), client=client)

    with pytest.raises(ProviderTimeout):
        asyncio.run(provider.generate_paper(_input()))


def test_gemini_rate_limited_normalized() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(429, request=request)

    transport = httpx.MockTransport(handler)
    client = httpx.AsyncClient(transport=transport)
    provider = GeminiProvider(_settings(), client=client)

    with pytest.raises(ProviderRateLimited):
        asyncio.run(provider.generate_paper(_input()))


def test_gemini_auth_error_normalized() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(401, request=request)

    transport = httpx.MockTransport(handler)
    client = httpx.AsyncClient(transport=transport)
    provider = GeminiProvider(_settings(), client=client)

    with pytest.raises(ProviderUnavailable):
        asyncio.run(provider.generate_paper(_input()))


def test_gemini_network_error_normalized() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("Connection refused", request=request)

    transport = httpx.MockTransport(handler)
    client = httpx.AsyncClient(transport=transport)
    provider = GeminiProvider(_settings(), client=client)

    with pytest.raises(ProviderUnavailable):
        asyncio.run(provider.generate_paper(_input()))


def test_gemini_schema_fallback_on_400() -> None:
    paper = PaperDraft.model_validate(PAPER_DATA)
    payload = _gemini_payload(paper.model_dump_json())

    call_count = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal call_count
        call_count += 1
        body = json.loads(request.content.decode("utf-8"))
        # First call with responseSchema fails with 400
        if "responseSchema" in body.get("generationConfig", {}):
            return httpx.Response(400, text="Invalid schema", request=request)
        # Second fallback call without responseSchema succeeds
        return httpx.Response(200, json=payload, request=request)

    transport = httpx.MockTransport(handler)
    client = httpx.AsyncClient(transport=transport)
    provider = GeminiProvider(_settings(), client=client)

    result = asyncio.run(provider.generate_paper(_input()))
    assert call_count == 2
    assert json.loads(result.structured_output) == paper.model_dump(mode="json")


def test_gemini_incomplete_candidate_fails_closed() -> None:
    payload = {"candidates": []}

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=payload, request=request)

    transport = httpx.MockTransport(handler)
    client = httpx.AsyncClient(transport=transport)
    provider = GeminiProvider(_settings(), client=client)

    with pytest.raises(ProviderInvalidResponse):
        asyncio.run(provider.generate_paper(_input()))


def test_gemini_missing_credentials_prevents_client_creation() -> None:
    settings = Settings(
        environment="development",
        generation_provider="gemini",
        provider_model=None,
        provider_api_key=None,
        _env_file=None,
    )
    provider = GeminiProvider(settings)

    assert provider._client is None
    with pytest.raises(ProviderUnavailable):
        asyncio.run(provider.generate_paper(_input()))


def test_gemini_multiple_keys_fallback_on_429() -> None:
    paper = PaperDraft.model_validate(PAPER_DATA)
    payload = _gemini_payload(paper.model_dump_json())

    keys_attempted: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        key = request.headers.get("x-goog-api-key", "")
        keys_attempted.append(key)
        if key == "key-primary":
            return httpx.Response(429, text="Rate limited", request=request)
        return httpx.Response(200, json=payload, request=request)

    transport = httpx.MockTransport(handler)
    client = httpx.AsyncClient(transport=transport)
    settings = _settings(
        provider_api_key="key-primary",
        provider_fallback_api_keys=["key-secondary", "key-tertiary"],
    )
    provider = GeminiProvider(settings, client=client)

    result = asyncio.run(provider.generate_paper(_input()))
    assert json.loads(result.structured_output) == paper.model_dump(mode="json")
    assert keys_attempted == ["key-primary", "key-secondary"]
    assert provider._api_key == "key-secondary"


def test_gemini_multiple_keys_fallback_on_timeout() -> None:
    paper = PaperDraft.model_validate(PAPER_DATA)
    payload = _gemini_payload(paper.model_dump_json())

    keys_attempted: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        key = request.headers.get("x-goog-api-key", "")
        keys_attempted.append(key)
        if key == "key-primary":
            raise httpx.ReadTimeout("Read timed out", request=request)
        return httpx.Response(200, json=payload, request=request)

    transport = httpx.MockTransport(handler)
    client = httpx.AsyncClient(transport=transport)
    settings = _settings(
        provider_api_key="key-primary, key-secondary",
    )
    provider = GeminiProvider(settings, client=client)

    result = asyncio.run(provider.generate_paper(_input()))
    assert json.loads(result.structured_output) == paper.model_dump(mode="json")
    assert keys_attempted == ["key-primary", "key-secondary"]
    assert provider._api_key == "key-secondary"


def test_gemini_multiple_keys_all_rate_limited_raises() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(429, text="Rate limited", request=request)

    transport = httpx.MockTransport(handler)
    client = httpx.AsyncClient(transport=transport)
    settings = _settings(
        provider_api_key="key-1, key-2",
    )
    provider = GeminiProvider(settings, client=client)

    with pytest.raises(ProviderRateLimited):
        asyncio.run(provider.generate_paper(_input()))
