"""Academic manuscript editorial note stripping and optional author review notes appendix formatting."""

from __future__ import annotations

import re

from resbud_api.domain.models import PaperDraft, PaperSection

# Pattern matching bracketed editorial disclaimers, system placeholders, and review notes
# while strictly preserving citations ([1], [1-3], [Smith et al., 2024]) and math intervals ([0, 1]).
EDITORIAL_NOTE_PATTERN = re.compile(
    r"\[\s*(?:(?:Author|Editorial|Review|Methodological(?:\s+Scope)?|Scope)?\s*Note|Warning|Placeholder|Notice|Editor\'?s?\s*Note|TODO|Unresolved)\s*:[^\]]+\]",
    re.IGNORECASE,
)


def clean_editorial_notes_from_text(text: str) -> tuple[str, list[str]]:
    """Strip bracketed editorial notes from prose and return the sanitized text and extracted notes."""
    extracted_notes: list[str] = []

    def _replace(match: re.Match[str]) -> str:
        raw = match.group(0).strip("[] \t\r\n")
        extracted_notes.append(raw)
        return ""

    cleaned = EDITORIAL_NOTE_PATTERN.sub(_replace, text)
    # Clean up redundant spaces and whitespace preceding punctuation
    cleaned = re.sub(r"[ \t]+", " ", cleaned)
    cleaned = re.sub(r"[ \t]+([.,;:!?])", r"\1", cleaned)
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned)
    return cleaned.strip(), extracted_notes


def prepare_paper_for_export(
    paper: PaperDraft,
    include_review_notes_appendix: bool = False,
) -> tuple[PaperDraft, list[dict[str, str]]]:
    """Sanitize the paper's narrative by stripping bracketed editorial placeholders.

    If include_review_notes_appendix is True, returns a consolidated list of unresolved
    notes (extracted notes + structured review warnings) for the 'Author Review Notes' appendix.
    If False, returns an empty list so no appendix is generated.
    """
    all_notes: list[dict[str, str]] = []

    # Map section IDs to human-readable titles
    section_title_map: dict[str, str] = {
        section.id: re.sub(r"^\d+(?:\.\d+)*\.?\s*", "", section.heading).strip()
        for section in paper.sections
    }

    # 1. Clean Abstract
    cleaned_abstract, abstract_notes = clean_editorial_notes_from_text(paper.abstract)
    if include_review_notes_appendix:
        for note in abstract_notes:
            all_notes.append({"section": "Abstract", "message": note})

    # 2. Clean Sections
    sanitized_sections: list[PaperSection] = []
    for section in paper.sections:
        cleaned_content, sec_notes = clean_editorial_notes_from_text(section.content)
        sec_title = section_title_map.get(section.id, section.heading)
        if include_review_notes_appendix:
            for note in sec_notes:
                all_notes.append({"section": sec_title, "message": note})

        sanitized_sections.append(section.model_copy(update={"content": cleaned_content}))

    # 3. Incorporate Structured Review Warnings if requested
    if include_review_notes_appendix and paper.review_warnings:
        for warning in paper.review_warnings:
            target_sec = "General Review"
            if warning.section_id and warning.section_id in section_title_map:
                target_sec = section_title_map[warning.section_id]
            severity_tag = warning.severity.capitalize()
            msg = f"{severity_tag}: {warning.message}"
            all_notes.append({"section": target_sec, "message": msg})

    # Deduplicate notes while preserving encounter order
    seen: set[str] = set()
    deduped_notes: list[dict[str, str]] = []
    for entry in all_notes:
        key = f"{entry['section']}::{entry['message']}".lower()
        if key not in seen:
            seen.add(key)
            deduped_notes.append(entry)

    sanitized_paper = paper.model_copy(
        update={
            "abstract": cleaned_abstract,
            "sections": sanitized_sections,
        }
    )

    return sanitized_paper, deduped_notes if include_review_notes_appendix else []
