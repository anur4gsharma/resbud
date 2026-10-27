"""Deterministic, conservative checks for output and supplied evidence."""

import re
from collections import defaultdict

from resbud_api.domain.models import PaperDraft, ReviewWarning, WarningCode
from resbud_api.providers.base import ResearchBrief

_NUMBER = re.compile(r"\b\d+(?:[.,]\d+)*%?\b")
_LABELED_VALUE = re.compile(
    r"\b(accuracy|precision|recall|f1(?:\s+score)?|sample size|number of participants|"
    r"participants|dataset size)\s*(?:was|is|of|=|:)?\s*(\d+(?:[.,]\d+)*%?)\b",
    re.IGNORECASE,
)
_REFERENCE_PLACEHOLDER = re.compile(
    r"\b(?:TODO|TBD|citation needed|add (?:a |the )?(?:full )?reference)\b", re.IGNORECASE
)


def run_integrity_checks(
    brief: ResearchBrief,
    paper: PaperDraft,
    provider_name: str,
) -> list[ReviewWarning]:
    """Return safe, deterministic warnings without attempting semantic truth verification."""
    section_ids = {section.id for section in paper.sections}
    warnings: list[ReviewWarning] = []

    def add(code: WarningCode, message: str, section_id: str | None = None) -> None:
        warnings.append(
            ReviewWarning(
                code=code,
                severity="warning",
                message=message,
                section_id=section_id if section_id in section_ids else None,
            )
        )

    project = brief.project
    if project.methodology_status not in {"provided", "not_applicable"}:
        method_message = (
            "Methodology was marked unavailable. Add the actual method if it exists."
            if project.methodology_status == "not_available"
            else "Method details were not supplied. Add the actual method before submission."
        )
        add("MISSING_METHOD", method_message, "methodology")
    if project.dataset_or_materials_status not in {"provided", "not_applicable"}:
        dataset_message = (
            "Dataset or material details were marked unavailable. Confirm this status before "
            "submission."
            if project.dataset_or_materials_status == "not_available"
            else "Dataset or material details were not supplied. Add verified details before "
            "submission."
        )
        add("MISSING_DATASET_DETAILS", dataset_message, "methodology")
    if project.results_status not in {"provided", "not_applicable"}:
        result_message = (
            "Results were not collected. Do not describe outcomes without measured results."
            if project.results_status == "not_collected"
            else (
                "Results were marked unavailable. Confirm this status before submission."
                if project.results_status == "not_available"
                else "Results were not supplied. Add measured results before describing outcomes."
            )
        )
        add("MISSING_RESULTS", result_message, "results")
    if project.limitations_status not in {"provided", "not_applicable"}:
        limitation_message = (
            "No limitations have been identified. Review this status before submission."
            if project.limitations_status == "not_identified"
            else (
                "Limitations were marked unavailable. Confirm this status before submission."
                if project.limitations_status == "not_available"
                else "Limitations were not supplied. Identify and review limitations before "
                "submission."
            )
        )
        add("MISSING_LIMITATIONS", limitation_message, "limitations")

    if not brief.references:
        add(
            "CITATION_NEEDED",
            "No references were supplied. Add verified sources for claims that need citations.",
            "introduction",
        )
    for reference in brief.references:
        if not reference.text.strip() or _REFERENCE_PLACEHOLDER.search(reference.text):
            add(
                "REFERENCE_INCOMPLETE",
                "A supplied reference contains an empty or explicit placeholder. Complete it from "
                "a verified source.",
            )
            break

    if _input_conflicts(brief):
        add(
            "INPUT_CONFLICT",
            "Supplied material gives different values for the same labeled fact. Review and "
            "resolve the conflict before submission.",
        )
    if _has_unsupported_numeric_claim(brief, paper):
        add(
            "CLAIM_NEEDS_REVIEW",
            "The draft contains a numeric value not found in supplied materials. Verify it "
            "before use.",
        )

    # Provider warning text is untrusted. Preserve only supported warning categories and replace
    # their prose with stable, user-safe messages; evidence-based checks above remain authoritative.
    if any(warning.code == "INPUT_CONFLICT" for warning in paper.review_warnings) and not any(
        warning.code == "INPUT_CONFLICT" for warning in warnings
    ):
        add(
            "INPUT_CONFLICT",
            "The draft identified a possible conflict in the supplied material. Review it before "
            "submission.",
        )
    if any(warning.code == "REFERENCE_INCOMPLETE" for warning in paper.review_warnings) and not any(
        warning.code == "REFERENCE_INCOMPLETE" for warning in warnings
    ):
        add(
            "REFERENCE_INCOMPLETE",
            "A reference may be incomplete. Verify its author, title, venue, year, and locator.",
        )
    if any(warning.code == "CLAIM_NEEDS_REVIEW" for warning in paper.review_warnings) and not any(
        warning.code == "CLAIM_NEEDS_REVIEW" for warning in warnings
    ):
        add(
            "CLAIM_NEEDS_REVIEW",
            "The draft identified a claim that needs source verification. Review it before use.",
        )
    if provider_name == "fake":
        add(
            "GENERAL_REVIEW",
            "Deterministic fake-provider demo output; it is not a research analysis.",
        )
    return warnings


def has_meaningful_content(paper: PaperDraft) -> bool:
    """Reject structurally valid provider output that contains no draft or placeholder text."""
    return bool(paper.abstract.strip()) or any(
        section.content.strip() for section in paper.sections
    )


def _input_conflicts(brief: ResearchBrief) -> bool:
    values: dict[str, set[str]] = defaultdict(set)
    texts = (
        brief.source_draft,
        brief.project.claimed_contribution,
        brief.project.methodology or "",
        brief.project.dataset_or_materials or "",
        brief.project.results or "",
        brief.project.limitations or "",
    )
    for text in texts:
        for label, value in _LABELED_VALUE.findall(text):
            values[" ".join(label.casefold().split())].add(value.casefold())
    return any(len(label_values) > 1 for label_values in values.values())


def _has_unsupported_numeric_claim(brief: ResearchBrief, paper: PaperDraft) -> bool:
    project = brief.project
    supplied_text = " ".join(
        (
            project.title,
            project.research_field,
            project.research_question,
            *project.objectives,
            project.claimed_contribution,
            project.methodology or "",
            project.dataset_or_materials or "",
            project.results or "",
            project.limitations or "",
            brief.source_draft,
            *(reference.text for reference in brief.references),
        )
    )
    supplied_numbers = set(_NUMBER.findall(supplied_text))
    output_text = " ".join(
        (paper.title, paper.abstract, *(section.content for section in paper.sections))
    )
    return any(number not in supplied_numbers for number in _NUMBER.findall(output_text))
