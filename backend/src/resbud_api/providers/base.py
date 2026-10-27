"""Provider-neutral generation types and protocol."""

from dataclasses import dataclass
from typing import Protocol

from resbud_api.domain.models import PaperPreferences, ProjectContext, ReferenceInput


@dataclass(frozen=True)
class ResearchBrief:
    project: ProjectContext
    source_draft: str
    references: tuple[ReferenceInput, ...]
    preferences: PaperPreferences


@dataclass(frozen=True)
class GenerationPrompt:
    version: str
    system_instructions: str
    user_message: str
    output_schema: str


@dataclass(frozen=True)
class GenerationInput:
    brief: ResearchBrief
    prompt: GenerationPrompt


@dataclass(frozen=True)
class ProviderResult:
    structured_output: str
    provider_name: str
    model_name: str
    duration_ms: int
    input_tokens: int | None = None
    output_tokens: int | None = None
    request_id: str | None = None


class ProviderTimeout(Exception):
    """The configured provider did not return within its time budget."""


class ProviderUnavailable(Exception):
    """The configured provider cannot currently serve requests."""


class ProviderRateLimited(Exception):
    """The configured provider rejected a request due to its own quota."""


class ProviderInvalidResponse(Exception):
    """The provider response could not be parsed as the expected structured output."""


class GenerationProvider(Protocol):
    async def generate_paper(self, generation_input: GenerationInput) -> ProviderResult:
        """Return structured output and provider-neutral operational metadata."""


class DisabledProvider:
    async def generate_paper(self, _generation_input: GenerationInput) -> ProviderResult:
        raise ProviderUnavailable
