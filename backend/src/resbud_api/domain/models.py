"""Typed domain representations matching the versioned Resbud contracts."""

from typing import Annotated, Any, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StrictInt, StringConstraints, model_serializer, model_validator

SectionId = Annotated[str, StringConstraints(pattern=r"^[a-z][a-z0-9_]{1,39}$")]
ReferenceId = Annotated[str, StringConstraints(pattern=r"^[A-Za-z0-9_-]{1,40}$")]
NON_WHITESPACE_PATTERN = r"[\s\S]*\S[\s\S]*"
TargetWordCount = Annotated[StrictInt, Field(ge=500, le=8000)]
TokenCount = Annotated[StrictInt, Field(ge=0)]

MethodologyStatus = Literal["provided", "not_available", "not_applicable", "unknown"]
MaterialsStatus = Literal["provided", "not_available", "not_applicable", "unknown"]
ResultsStatus = Literal["provided", "not_collected", "not_available", "not_applicable", "unknown"]
LimitationsStatus = Literal[
    "provided", "not_identified", "not_available", "not_applicable", "unknown"
]
SectionState = Literal["draft", "needs_input", "not_applicable"]
CitationStyle = Literal["user_supplied", "apa_7", "ieee", "other"]
WarningCode = Literal[
    "MISSING_METHOD",
    "MISSING_DATASET_DETAILS",
    "MISSING_RESULTS",
    "MISSING_LIMITATIONS",
    "CITATION_NEEDED",
    "REFERENCE_INCOMPLETE",
    "CLAIM_NEEDS_REVIEW",
    "INPUT_CONFLICT",
    "SECTION_NOT_APPLICABLE",
    "GENERAL_REVIEW",
]
WarningSeverity = Literal["info", "warning", "critical"]


class ContractModel(BaseModel):
    """Base model for wire-compatible data with unknown fields rejected."""

    model_config = ConfigDict(extra="forbid")


class ProjectContext(ContractModel):
    """Supplied research facts, including the user's explicit evidence status."""

    title: Annotated[str, Field(min_length=1, max_length=300)]
    research_field: Annotated[str, Field(min_length=1, max_length=200)]
    research_question: Annotated[str, Field(min_length=1, max_length=4000)]
    objectives: Annotated[
        list[Annotated[str, Field(min_length=1, max_length=1000)]],
        Field(min_length=1, max_length=20),
    ]
    claimed_contribution: Annotated[str, Field(max_length=4000)]
    methodology_status: MethodologyStatus
    methodology: Annotated[str, Field(max_length=12000)] | None = None
    dataset_or_materials_status: MaterialsStatus
    dataset_or_materials: Annotated[str, Field(max_length=8000)] | None = None
    results_status: ResultsStatus
    results: Annotated[str, Field(max_length=12000)] | None = None
    limitations_status: LimitationsStatus
    limitations: Annotated[str, Field(max_length=8000)] | None = None

    @model_validator(mode="after")
    def require_content_for_provided_status(self) -> "ProjectContext":
        for status_name, value_name in (
            ("methodology_status", "methodology"),
            ("dataset_or_materials_status", "dataset_or_materials"),
            ("results_status", "results"),
            ("limitations_status", "limitations"),
        ):
            if getattr(self, status_name) == "provided":
                value = getattr(self, value_name)
                if value is None or not value.strip():
                    raise ValueError(f"{value_name} is required when its status is provided")
        return self


ProvenanceType = Literal["user_supplied", "extracted", "verified", "placeholder"]
VerificationStatusType = Literal["unverified", "verified", "incomplete", "disputed"]


class ReferenceInput(ContractModel):
    id: ReferenceId
    text: Annotated[str, Field(min_length=1, max_length=2000)]
    raw_text: Annotated[str, Field(max_length=4000)] | None = None
    authors: list[Annotated[str, Field(max_length=300)]] | None = None
    year: int | None = None
    title: Annotated[str, Field(max_length=500)] | None = None
    venue: Annotated[str, Field(max_length=500)] | None = None
    volume: Annotated[str, Field(max_length=100)] | None = None
    issue: Annotated[str, Field(max_length=100)] | None = None
    pages: Annotated[str, Field(max_length=100)] | None = None
    publisher: Annotated[str, Field(max_length=300)] | None = None
    doi: Annotated[str, Field(max_length=200)] | None = None
    url: Annotated[str, Field(max_length=1000)] | None = None
    provenance: ProvenanceType | None = None
    verification_status: VerificationStatusType | None = None


class PaperPreferences(ContractModel):
    target_word_count: TargetWordCount
    desired_sections: Annotated[list[SectionId], Field(max_length=15)]
    citation_style: CitationStyle

    @model_validator(mode="after")
    def desired_section_ids_are_unique(self) -> "PaperPreferences":
        if len(self.desired_sections) != len(set(self.desired_sections)):
            raise ValueError("desired_sections must contain unique section IDs")
        return self


class GenerationRequest(ContractModel):
    schema_version: Literal[1]
    project: ProjectContext
    source_draft: Annotated[
        str,
        Field(min_length=1, max_length=50000, pattern=NON_WHITESPACE_PATTERN),
    ]
    references: Annotated[list[ReferenceInput], Field(max_length=50)]
    preferences: PaperPreferences


class ReviewWarning(ContractModel):
    code: WarningCode
    severity: WarningSeverity
    message: Annotated[str, Field(min_length=1, max_length=1000)]
    section_id: SectionId | None = None


class PaperSection(ContractModel):
    id: SectionId
    heading: Annotated[str, Field(min_length=1, max_length=150)]
    content: Annotated[str, Field(max_length=30000)]
    state: SectionState


class PaperDraft(ContractModel):
    schema_version: Literal[1]
    title: Annotated[str, Field(min_length=1, max_length=300)]
    abstract: Annotated[str, Field(max_length=6000)]
    keywords: Annotated[
        list[Annotated[str, Field(min_length=1, max_length=100)]],
        Field(max_length=10),
    ]
    sections: Annotated[
        list[PaperSection],
        Field(
            min_length=1,
            max_length=15,
            description="Section IDs must be unique within this paper draft.",
        ),
    ]
    references: Annotated[list[ReferenceInput], Field(max_length=50)]
    review_warnings: Annotated[list[ReviewWarning], Field(max_length=100)]

    @model_validator(mode="after")
    def section_ids_are_unique(self) -> "PaperDraft":
        ids = [section.id for section in self.sections]
        if len(ids) != len(set(ids)):
            raise ValueError("section IDs must be unique within a paper draft")
        return self


class GenerationMeta(ContractModel):
    provider_name: Annotated[str, Field(max_length=100)]
    model_name: Annotated[str, Field(max_length=100)]
    duration_ms: StrictInt = Field(ge=0)
    input_tokens: TokenCount | None = None
    output_tokens: TokenCount | None = None
    requested_words: int | None = Field(default=None, ge=0)
    generated_words: int | None = Field(default=None, ge=0)
    words_per_section: dict[str, int] | None = None
    completion_status: (
        Literal["completed", "partially_complete", "evidence_constrained", "under_generated"]
        | None
    ) = None
    missing_sections: list[str] | None = None
    evidence_restrictions: list[str] | None = None


class GenerationResponse(ContractModel):
    """Generation result; wrapper warnings repeat the paper's warning list."""

    schema_version: Literal[1]
    generation_id: UUID
    paper: PaperDraft
    review_warnings: Annotated[list[ReviewWarning], Field(max_length=100)]
    meta: GenerationMeta

    @model_validator(mode="after")
    def wrapper_warnings_match_paper(self) -> "GenerationResponse":
        if self.review_warnings != self.paper.review_warnings:
            raise ValueError("response and paper review_warnings must match")
        return self


class SectionRegenerationRequest(ContractModel):
    schema_version: Literal[1]
    generation_request: GenerationRequest
    current_paper: PaperDraft
    section_id: SectionId
    user_instruction: Annotated[str, Field(max_length=2000)]

    @model_validator(mode="after")
    def target_section_must_exist(self) -> "SectionRegenerationRequest":
        target = next(
            (section for section in self.current_paper.sections if section.id == self.section_id),
            None,
        )
        if target is None:
            raise ValueError("section_id must identify a section in current_paper")
        if target.state == "not_applicable":
            raise ValueError("a not_applicable section cannot be regenerated")
        return self


class SectionRegenerationResponse(ContractModel):
    schema_version: Literal[1]
    section: PaperSection
    review_warnings: Annotated[list[ReviewWarning], Field(max_length=100)]

    @model_validator(mode="after")
    def replacement_content_must_be_nonblank(self) -> "SectionRegenerationResponse":
        if not self.section.content.strip():
            raise ValueError("replacement section content must not be empty")
        if self.section.state == "not_applicable":
            raise ValueError("replacement section cannot be not_applicable")
        return self

    def validate_for_request(self, request: SectionRegenerationRequest) -> None:
        """Enforce the cross-object replacement identity declared by the API contract."""
        if self.section.id != request.section_id:
            raise ValueError("replacement section ID must match the requested section_id")


class ClarificationQuestion(ContractModel):
    id: Annotated[str, Field(min_length=1, max_length=50)]
    question: Annotated[str, Field(min_length=1, max_length=1000)]
    why_needed: Annotated[str, Field(min_length=1, max_length=1000)]
    is_essential: bool = True
    field_key: Annotated[str, Field(max_length=50)] | None = None
    default_value: Annotated[str, Field(max_length=1000)] | None = None


class AnalysisWarning(ContractModel):
    code: WarningCode
    severity: WarningSeverity
    message: Annotated[str, Field(min_length=1, max_length=1000)]
    why_it_matters: Annotated[str, Field(min_length=1, max_length=1000)]
    potential_impact: Annotated[str, Field(min_length=1, max_length=1000)]


class DynamicOutlineSection(ContractModel):
    id: SectionId
    heading: Annotated[str, Field(min_length=1, max_length=150)]
    rationale: Annotated[str, Field(min_length=1, max_length=1000)]


class ResearchAnalysisRequest(ContractModel):
    source_material: Annotated[
        str,
        Field(min_length=1, max_length=100000, pattern=NON_WHITESPACE_PATTERN),
    ]
    file_names: Annotated[list[str], Field(default_factory=list, max_length=20)]
    title_hint: Annotated[str, Field(max_length=300)] | None = None
    user_clarifications: dict[str, str] = Field(default_factory=dict)


class ResearchAnalysisResponse(ContractModel):
    schema_version: Literal[1] = 1
    inferred_title: Annotated[str, Field(min_length=1, max_length=300)]
    inferred_field: Annotated[str, Field(min_length=1, max_length=200)]
    inferred_question: Annotated[str, Field(min_length=1, max_length=4000)]
    inferred_objectives: Annotated[
        list[Annotated[str, Field(min_length=1, max_length=1000)]],
        Field(min_length=1, max_length=20),
    ]
    methodology_summary: Annotated[str, Field(max_length=12000)] | None = None
    dataset_summary: Annotated[str, Field(max_length=8000)] | None = None
    results_summary: Annotated[str, Field(max_length=12000)] | None = None
    limitations_summary: Annotated[str, Field(max_length=8000)] | None = None
    suggested_outline: Annotated[list[DynamicOutlineSection], Field(min_length=1, max_length=15)]
    questions: Annotated[list[ClarificationQuestion], Field(default_factory=list, max_length=20)]
    warnings: Annotated[list[AnalysisWarning], Field(default_factory=list, max_length=50)]
    can_proceed_directly: bool
    requires_clarification: bool
    extracted_references: Annotated[
        list[ReferenceInput], Field(default_factory=list, max_length=50)
    ]


class DocumentExtractRequest(ContractModel):
    file_name: Annotated[str, Field(min_length=1, max_length=255)]
    content_base64: str | None = None
    text_content: str | None = None


class DocumentExtractResponse(ContractModel):
    file_name: str
    format: str
    text: str
    char_count: int
    error: str | None = None
