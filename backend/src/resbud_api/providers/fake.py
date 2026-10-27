"""Deterministic fake provider for local demos and tests."""

import json
from enum import StrEnum

from resbud_api.domain.models import PaperSection, ProjectContext, SectionState
from resbud_api.providers.base import (
    GenerationInput,
    ProviderRateLimited,
    ProviderResult,
    ProviderTimeout,
    ProviderUnavailable,
    ResearchBrief,
    SectionRegenerationInput,
)


class FakeOutcome(StrEnum):
    SUCCESS = "success"
    TIMEOUT = "timeout"
    UNAVAILABLE = "unavailable"
    MALFORMED = "malformed"
    RATE_LIMITED = "rate_limited"


class FakeProvider:
    """Return explicit placeholders and user-provided material without adding claims."""

    provider_name = "fake"
    model_name = "deterministic-demo"

    def __init__(self, outcome: FakeOutcome = FakeOutcome.SUCCESS) -> None:
        self.outcome = outcome
        self.call_count = 0

    async def generate_paper(self, generation_input: GenerationInput) -> ProviderResult:
        self.call_count += 1
        if self.outcome is FakeOutcome.TIMEOUT:
            raise ProviderTimeout
        if self.outcome is FakeOutcome.UNAVAILABLE:
            raise ProviderUnavailable
        if self.outcome is FakeOutcome.RATE_LIMITED:
            raise ProviderRateLimited
        if self.outcome is FakeOutcome.MALFORMED:
            return ProviderResult("not-json", self.provider_name, self.model_name, 0)

        paper = self._paper(generation_input.brief)
        return ProviderResult(
            structured_output=json.dumps(paper, ensure_ascii=False, separators=(",", ":")),
            provider_name=self.provider_name,
            model_name=self.model_name,
            duration_ms=0,
        )

    async def regenerate_section(
        self, regeneration_input: SectionRegenerationInput
    ) -> ProviderResult:
        self.call_count += 1
        if self.outcome is FakeOutcome.TIMEOUT:
            raise ProviderTimeout
        if self.outcome is FakeOutcome.UNAVAILABLE:
            raise ProviderUnavailable
        if self.outcome is FakeOutcome.RATE_LIMITED:
            raise ProviderRateLimited
        if self.outcome is FakeOutcome.MALFORMED:
            return ProviderResult("not-json", self.provider_name, self.model_name, 0)

        content, state = _section_content(
            regeneration_input.brief.project,
            regeneration_input.target_section.id,
            regeneration_input.brief.source_draft,
        )
        section = PaperSection(
            id=regeneration_input.target_section.id,
            heading=regeneration_input.target_section.heading,
            content=content,
            state=state,
        )
        return ProviderResult(
            structured_output=json.dumps(
                section.model_dump(mode="json"), ensure_ascii=False, separators=(",", ":")
            ),
            provider_name=self.provider_name,
            model_name=self.model_name,
            duration_ms=0,
        )

    @staticmethod
    def _paper(brief: ResearchBrief) -> dict[str, object]:
        project = brief.project
        requested_sections = brief.preferences.desired_sections
        section_ids = requested_sections or ["introduction", "methodology", "results"]
        sections: list[PaperSection] = []
        for section_id in section_ids:
            content, state = _section_content(project, section_id, brief.source_draft)
            sections.append(
                PaperSection(
                    id=section_id,
                    heading=section_id.replace("_", " ").title(),
                    content=content,
                    state=state,
                )
            )
        return {
            "schema_version": 1,
            "title": project.title,
            "abstract": "[DRAFT ABSTRACT: synthesize only supplied material; verify before use.]",
            "keywords": [],
            "sections": [section.model_dump(mode="json") for section in sections],
            "references": [reference.model_dump(mode="json") for reference in brief.references],
            "review_warnings": [],
        }


def _section_content(
    project: ProjectContext, section_id: str, source_draft: str
) -> tuple[str, SectionState]:
    if section_id == "introduction":
        prefix = "[SOURCE MATERIAL]\n"
        excerpt = source_draft[: 30000 - len(prefix)]
        return f"{prefix}{excerpt}", "draft"
    status_content = {
        "methodology": (project.methodology_status, project.methodology, "methodology"),
        "results": (project.results_status, project.results, "results"),
        "limitations": (project.limitations_status, project.limitations, "limitations"),
    }
    if section_id in status_content:
        status, content, label = status_content[section_id]
        if status == "provided" and content is not None:
            return content, "draft"
        if status == "not_applicable":
            return "", "not_applicable"
        return f"[PROVIDE {label.upper()} DETAILS]", "needs_input"
    return "[DRAFT FROM SUPPLIED MATERIALS; VERIFY ALL CLAIMS]", "needs_input"
