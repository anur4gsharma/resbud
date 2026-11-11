"""Internal domain models for structured manuscript planning and section-level budgets."""

from __future__ import annotations

from pydantic import BaseModel, Field


class PlannedSubsection(BaseModel):
    """Specific subsection planned within a major academic section."""

    title: str = Field(min_length=1, max_length=200)
    purpose: str = Field(min_length=1, max_length=500)
    target_words: int = Field(ge=50, le=3000)
    key_points: list[str] = Field(default_factory=list)


class PlannedSection(BaseModel):
    """Detailed structural specification and evidence allocation for one academic section."""

    id: str = Field(min_length=1, max_length=40)
    heading: str = Field(min_length=1, max_length=200)
    purpose: str = Field(min_length=1, max_length=800)
    allocated_words: int = Field(ge=100, le=4000)
    subsections: list[PlannedSubsection] = Field(default_factory=list)
    available_evidence: list[str] = Field(default_factory=list)
    relevant_references: list[str] = Field(default_factory=list)
    key_arguments: list[str] = Field(default_factory=list)
    missing_information: list[str] = Field(default_factory=list)
    requires_input_notice: bool = False


class ManuscriptPlan(BaseModel):
    """Validated architectural blueprint for long-form academic manuscript synthesis.

    Determines the document type, section hierarchy, allocated word budgets,
    evidence mapping, and terminology consistency rules before prose generation.
    """

    paper_type: str = Field(
        default="Empirical Research Article",
        description="Type of academic paper (e.g. Empirical Study, Theoretical Framework, System Architecture)",
    )
    intended_academic_structure: str = Field(
        default="Standard Peer-Reviewed Journal Format",
        description="Formal publication structure (e.g. IEEE / ACM Conference, Nature / Springer Journal)",
    )
    title: str = Field(min_length=1, max_length=300)
    abstract: str = Field(min_length=50, max_length=4000)
    keywords: list[str] = Field(min_length=2, max_length=10)
    total_target_words: int = Field(ge=500, le=8000)
    sections: list[PlannedSection] = Field(min_length=3, max_length=15)
    identified_limitations: list[str] = Field(default_factory=list)
    terminology_glossary: dict[str, str] = Field(
        default_factory=dict,
        description="Canonical technical terms, metrics, and abbreviations to enforce across sections",
    )
    cross_section_relationships: list[str] = Field(
        default_factory=list,
        description="Logical transition notes and analytical connections between sections",
    )

    @property
    def total_allocated_words(self) -> int:
        return sum(s.allocated_words for s in self.sections)
