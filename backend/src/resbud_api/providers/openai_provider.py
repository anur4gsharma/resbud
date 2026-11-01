"""OpenAI Responses API adapter; SDK details stay behind the provider protocol."""

from time import perf_counter
from typing import Any, cast

import httpx
from openai import (
    APIConnectionError,
    APIStatusError,
    APITimeoutError,
    AsyncOpenAI,
    AuthenticationError,
    LengthFinishReasonError,
    OpenAIError,
    PermissionDeniedError,
    RateLimitError,
)
from pydantic import ValidationError

from resbud_api.core.settings import Settings
from resbud_api.domain.models import PaperDraft, PaperSection
from resbud_api.providers.base import (
    GenerationInput,
    GenerationPrompt,
    ProviderInvalidResponse,
    ProviderRateLimited,
    ProviderResult,
    ProviderTimeout,
    ProviderUnavailable,
    SectionRegenerationInput,
)


class OpenAIProvider:
    """Call one configured OpenAI model with schema-constrained, non-stored output."""

    provider_name = "openai"

    def __init__(self, settings: Settings, client: Any | None = None) -> None:
        self._model = settings.provider_model
        self._max_output_tokens = settings.provider_max_output_tokens
        self._timeout = httpx.Timeout(
            connect=settings.provider_connect_timeout_seconds,
            read=settings.provider_read_timeout_seconds,
            write=settings.provider_connect_timeout_seconds,
            pool=settings.provider_connect_timeout_seconds,
        )
        if client is not None:
            self._client = client
        elif settings.provider_api_key is not None and self._model is not None:
            self._client = AsyncOpenAI(
                api_key=settings.provider_api_key.get_secret_value(),
                timeout=self._timeout,
                max_retries=0,
            )
        else:
            self._client = None

    async def generate_paper(self, generation_input: GenerationInput) -> ProviderResult:
        return await self._request(generation_input.prompt, PaperDraft)

    async def regenerate_section(
        self, regeneration_input: SectionRegenerationInput
    ) -> ProviderResult:
        return await self._request(regeneration_input.prompt, PaperSection)

    async def generate_section(self, prompt: GenerationPrompt) -> ProviderResult:
        return await self._request(prompt, PaperSection)

    async def _request(
        self,
        prompt: GenerationPrompt,
        output_model: type[PaperDraft] | type[PaperSection],
    ) -> ProviderResult:
        if self._client is None or self._model is None:
            raise ProviderUnavailable

        started = perf_counter()
        try:
            response = await self._client.responses.parse(
                model=cast(Any, self._model),
                instructions=prompt.system_instructions,
                input=prompt.user_message,
                text_format=cast(Any, output_model),
                max_output_tokens=self._max_output_tokens,
                store=False,
            )
        except APITimeoutError as exc:
            raise ProviderTimeout from exc
        except RateLimitError as exc:
            raise ProviderRateLimited from exc
        except (AuthenticationError, PermissionDeniedError, APIConnectionError) as exc:
            raise ProviderUnavailable from exc
        except APIStatusError as exc:
            if exc.status_code == 429:
                raise ProviderRateLimited from exc
            if exc.status_code >= 500:
                raise ProviderUnavailable from exc
            raise ProviderInvalidResponse from exc
        except (
            LengthFinishReasonError,
            OpenAIError,
            ValidationError,
            TypeError,
            ValueError,
        ) as exc:
            raise ProviderInvalidResponse from exc

        parsed = getattr(response, "output_parsed", None)
        if getattr(response, "status", None) != "completed" or not isinstance(parsed, output_model):
            raise ProviderInvalidResponse

        usage = getattr(response, "usage", None)
        return ProviderResult(
            structured_output=parsed.model_dump_json(),
            provider_name=self.provider_name,
            model_name=getattr(response, "model", None) or self._model,
            duration_ms=max(0, round((perf_counter() - started) * 1000)),
            input_tokens=getattr(usage, "input_tokens", None),
            output_tokens=getattr(usage, "output_tokens", None),
            request_id=getattr(response, "_request_id", None),
        )

    async def aclose(self) -> None:
        """Release the SDK's HTTP connection pool during application shutdown."""
        if self._client is not None:
            await self._client.close()
