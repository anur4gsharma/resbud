"""Unit tests for OpenAI adapter behavior using mocked SDK responses only."""

import asyncio
import json
from pathlib import Path
from types import SimpleNamespace
from typing import Any

import httpx
import pytest
from openai import (
    APIConnectionError,
    APIStatusError,
    APITimeoutError,
    AuthenticationError,
    RateLimitError,
)

from resbud_api.core.settings import Settings
from resbud_api.domain.models import GenerationRequest, PaperDraft
from resbud_api.providers.base import (
    ProviderInvalidResponse,
    ProviderRateLimited,
    ProviderTimeout,
    ProviderUnavailable,
)
from resbud_api.providers.openai_provider import OpenAIProvider
from resbud_api.services.generation import normalize_research_brief
from resbud_api.services.prompt_builder import build_generation_input

FIXTURES = Path(__file__).parent / "fixtures"
REQUEST = json.loads((FIXTURES / "generation-request.valid.json").read_text())
PAPER_DATA = json.loads((FIXTURES / "paper-draft.valid.json").read_text())


def _settings(**overrides: Any) -> Settings:
    return Settings(
        environment="test",
        generation_provider="openai",
        provider_model="configured-test-model",
        provider_api_key="synthetic-test-key",
        _env_file=None,
        **overrides,
    )


def _input() -> Any:
    request = GenerationRequest.model_validate(REQUEST)
    brief = normalize_research_brief(request)
    return build_generation_input(brief)


class MockResponses:
    def __init__(self, response: object | None = None, error: Exception | None = None) -> None:
        self.response = response
        self.error = error
        self.call: dict[str, object] = {}

    async def parse(self, **kwargs: object) -> object:
        self.call = kwargs
        if self.error is not None:
            raise self.error
        return self.response


def _provider_with_response(response: object | None = None, error: Exception | None = None):
    responses = MockResponses(response, error)
    return OpenAIProvider(_settings(), SimpleNamespace(responses=responses)), responses


def test_openai_adapter_uses_schema_mode_without_storing_and_normalizes_metadata() -> None:
    paper = PaperDraft.model_validate(PAPER_DATA)
    response = SimpleNamespace(
        status="completed",
        output_parsed=paper,
        model="configured-test-model-2026-01",
        usage=SimpleNamespace(input_tokens=120, output_tokens=80),
        _request_id="provider-request-123",
    )
    provider, responses = _provider_with_response(response)

    result = asyncio.run(provider.generate_paper(_input()))

    assert json.loads(result.structured_output) == paper.model_dump(mode="json")
    assert result.provider_name == "openai"
    assert result.model_name == "configured-test-model-2026-01"
    assert result.input_tokens == 120
    assert result.output_tokens == 80
    assert result.request_id == "provider-request-123"
    assert responses.call["model"] == "configured-test-model"
    assert responses.call["text_format"] is PaperDraft
    assert responses.call["store"] is False
    assert responses.call["max_output_tokens"] == 12000
    assert responses.call["instructions"] == _input().prompt.system_instructions


def test_openai_sdk_client_has_explicit_timeouts_and_retries_disabled() -> None:
    provider = OpenAIProvider(
        _settings(
            provider_connect_timeout_seconds=3.0,
            provider_read_timeout_seconds=40.0,
        )
    )
    client = provider._client

    assert client.max_retries == 0
    assert client.timeout.connect == 3.0
    assert client.timeout.read == 40.0
    asyncio.run(client.close())


def _provider_error(error: Exception) -> type[Exception]:
    provider, _ = _provider_with_response(error=error)
    with pytest.raises(
        (ProviderInvalidResponse, ProviderRateLimited, ProviderTimeout, ProviderUnavailable)
    ) as caught:
        asyncio.run(provider.generate_paper(_input()))
    return type(caught.value)


def test_openai_timeout_is_normalized_without_exposing_sdk_exception() -> None:
    error = APITimeoutError(request=httpx.Request("POST", "https://api.openai.com/v1/responses"))
    assert _provider_error(error) is ProviderTimeout


def test_openai_rate_limit_and_authentication_failures_are_normalized() -> None:
    request = httpx.Request("POST", "https://api.openai.com/v1/responses")
    rate_error = RateLimitError(
        "private rate details",
        response=httpx.Response(429, request=request),
        body={"detail": "secret"},
    )
    auth_error = AuthenticationError(
        "private credential details", response=httpx.Response(401, request=request), body=None
    )

    assert _provider_error(rate_error) is ProviderRateLimited
    assert _provider_error(auth_error) is ProviderUnavailable


def test_openai_network_and_server_errors_are_normalized() -> None:
    request = httpx.Request("POST", "https://api.openai.com/v1/responses")
    network_error = APIConnectionError(request=request)
    server_error = APIStatusError(
        "private server details", response=httpx.Response(503, request=request), body=None
    )

    assert _provider_error(network_error) is ProviderUnavailable
    assert _provider_error(server_error) is ProviderUnavailable


def test_incomplete_or_unparsed_sdk_response_fails_closed() -> None:
    response = SimpleNamespace(status="incomplete", output_parsed=None)
    provider, _ = _provider_with_response(response)

    with pytest.raises(ProviderInvalidResponse):
        asyncio.run(provider.generate_paper(_input()))


def test_missing_provider_credentials_or_model_prevents_network_client_creation() -> None:
    settings = Settings(
        environment="development",
        generation_provider="openai",
        provider_model=None,
        provider_api_key=None,
        _env_file=None,
    )
    provider = OpenAIProvider(settings)

    assert provider._client is None
    with pytest.raises(ProviderUnavailable):
        asyncio.run(provider.generate_paper(_input()))
