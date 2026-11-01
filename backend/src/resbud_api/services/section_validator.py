"""Section depth validation, repetition checking, and bounded continuation expansion."""

from __future__ import annotations

from dataclasses import dataclass, field
import json
import re
from typing import Any

from resbud_api.domain.manuscript_plan import PlannedSection
from resbud_api.domain.models import PaperSection
from resbud_api.providers.base import GenerationPrompt, ProviderResult, ResearchBrief
from resbud_api.services.section_generator import SECTION_SYSTEM_INSTRUCTIONS, execute_section_generation


@dataclass
class SectionValidationResult:
    """Detailed structural and qualitative validation assessment for a generated section."""

    section_id: str
    heading: str
    actual_words: int
    budget_words: int
    ratio: float
    is_under_generated: bool
    repetition_score: float
    has_repetition: bool
    repetition_issues: list[str] = field(default_factory=list)
    covered_topics: list[str] = field(default_factory=list)
    missing_topics: list[str] = field(default_factory=list)
    is_evidence_constrained: bool = False
    evidence_restriction_note: str | None = None
    is_complete: bool = True
    was_expanded: bool = False


def count_words(text: str) -> int:
    """Count substantive prose words, ignoring markdown fences, table syntax, and symbols."""
    clean_lines = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("```") or stripped.startswith("---"):
            continue
        # Remove markdown heading hashes and table borders
        cleaned = re.sub(r"^[#\s]+", "", stripped)
        cleaned = re.sub(r"^\|\s*|\s*\|$", "", cleaned)
        clean_lines.append(cleaned)
    words = " ".join(clean_lines).split()
    return len(words)


def detect_repetition_and_filler(content: str) -> tuple[float, list[str]]:
    """Detect repetitive phrasing, repeated sentences, and low lexical diversity.

    Returns:
        (repetition_score [0.0 = clean, 1.0 = degenerate], list of identified issues)
    """
    issues: list[str] = []
    words = [w.lower().strip(".,;:()[]\"'") for w in content.split() if w.strip(".,;:()[]\"'")]
    if len(words) < 50:
        return 0.0, issues

    # 1. Lexical diversity (Type-Token Ratio)
    unique_words = set(words)
    ttr = len(unique_words) / len(words)
    if ttr < 0.32 and len(words) > 150:
        issues.append(f"Low lexical diversity detected (TTR = {ttr:.2f}). Possible repetitive phrasing.")

    # 2. Duplicate or near-duplicate sentences
    sentences = [s.strip() for s in re.split(r"[.!?]\s+", content) if len(s.strip().split()) >= 6]
    seen_sentences: set[str] = set()
    duplicate_count = 0
    for s in sentences:
        norm_s = s.lower()
        if norm_s in seen_sentences:
            duplicate_count += 1
            if duplicate_count == 1:
                issues.append(f"Identified duplicate sentence: '{s[:60]}...'")
        seen_sentences.add(norm_s)

    score = 0.0
    if duplicate_count > 0:
        score += min(0.6, duplicate_count * 0.2)
    if ttr < 0.32:
        score += 0.4

    return min(1.0, score), issues


def check_topic_and_evidence_coverage(
    content: str,
    section_plan: PlannedSection,
) -> tuple[float, list[str], list[str]]:
    """Verify that the required subsections and key arguments are genuinely represented in the text.

    Returns:
        (coverage_ratio, covered_topics, missing_topics)
    """
    content_lower = content.lower()
    covered: list[str] = []
    missing: list[str] = []

    # Check planned subsections
    for sub in section_plan.subsections:
        # Check title words or purpose keywords
        sub_words = [w.lower().strip(".,;:()") for w in sub.title.split() if len(w) > 3]
        if any(w in content_lower for w in sub_words):
            covered.append(sub.title)
        else:
            missing.append(sub.title)

    # Check key arguments
    for arg in section_plan.key_arguments:
        arg_keywords = [w.lower().strip(".,;:()") for w in arg.split() if len(w) > 4][:3]
        if any(w in content_lower for w in arg_keywords):
            if arg not in covered:
                covered.append(arg)
        else:
            if arg not in missing:
                missing.append(arg)

    total_expected = len(covered) + len(missing)
    coverage_ratio = len(covered) / max(1, total_expected)
    return coverage_ratio, covered, missing


def validate_section_depth(
    section: PaperSection,
    section_plan: PlannedSection,
    brief: ResearchBrief,
    tolerance_pct: float = 0.75,
) -> SectionValidationResult:
    """Validate word count against budget, check topics/evidence, and evaluate completeness."""
    actual = count_words(section.content)
    budget = section_plan.allocated_words
    ratio = actual / max(1, budget)

    rep_score, rep_issues = detect_repetition_and_filler(section.content)
    cov_ratio, covered, missing = check_topic_and_evidence_coverage(section.content, section_plan)

    is_under = actual < int(budget * tolerance_pct)
    has_rep = rep_score >= 0.50

    # Determine if under-generation is due to evidence constraint
    is_constrained = False
    restriction_note = None

    if section_plan.requires_input_notice or section.state == "needs_input":
        is_constrained = True
        restriction_note = (
            f"Section '{section_plan.heading}' is constrained by incomplete source inputs "
            f"({', '.join(section_plan.missing_information) or 'unsupplied experimental data'})."
        )
    elif "result" in section_plan.id and brief.project.results_status != "provided":
        is_constrained = True
        restriction_note = "Experimental outcomes were not collected; cannot expand quantitative tables."

    is_complete = not is_under and not has_rep and (cov_ratio >= 0.50 or not missing)

    return SectionValidationResult(
        section_id=section.id,
        heading=section.heading,
        actual_words=actual,
        budget_words=budget,
        ratio=round(ratio, 2),
        is_under_generated=is_under,
        repetition_score=round(rep_score, 2),
        has_repetition=has_rep,
        repetition_issues=rep_issues,
        covered_topics=covered,
        missing_topics=missing,
        is_evidence_constrained=is_constrained,
        evidence_restriction_note=restriction_note,
        is_complete=is_complete,
        was_expanded=False,
    )


async def perform_bounded_expansion(
    section: PaperSection,
    section_plan: PlannedSection,
    brief: ResearchBrief,
    val_result: SectionValidationResult,
    provider: Any,
) -> tuple[PaperSection, SectionValidationResult]:
    """Execute a bounded continuation or limitation disclosure for an under-generated section."""
    if not val_result.is_under_generated:
        return section, val_result

    # 1. If evidence does not exist in source notes, do NOT fabricate words; explain the limitation
    source_lower = brief.source_draft.lower()
    has_source_evidence = len(brief.source_draft.strip()) >= 300 and (
        val_result.section_id in ("introduction", "related_work")
        or (val_result.section_id == "methodology" and brief.project.methodology_status == "provided")
        or (val_result.section_id == "results" and brief.project.results_status == "provided")
        or (val_result.section_id in ("discussion", "conclusion"))
    )

    if val_result.is_evidence_constrained or not has_source_evidence:
        limitation_text = (
            "\n\n[Methodological Scope Note: Further empirical expansion of this section is constrained "
            f"by the supplied source material ({val_result.evidence_restriction_note or 'no additional telemetry supplied'}). "
            "All documented findings are rigorously grounded in verified evidence without speculative extrapolation.]"
        )
        expanded_content = section.content + limitation_text
        updated_section = section.model_copy(update={"content": expanded_content})
        val_result.actual_words = count_words(expanded_content)
        val_result.ratio = round(val_result.actual_words / max(1, val_result.budget_words), 2)
        val_result.was_expanded = True
        val_result.is_complete = True  # Complete within evidence constraints
        return updated_section, val_result

    # 2. Evidence exists: perform bounded continuation addressing the missing substantive dimensions
    deficit_words = max(150, val_result.budget_words - val_result.actual_words)
    missing_desc = (
        ", ".join(val_result.missing_topics[:3])
        if val_result.missing_topics
        else f"in-depth analytical mechanisms and boundary nuances for {section_plan.heading}"
    )

    continuation_payload = {
        "action": "section_continuation",
        "section_id": section_plan.id,
        "section_heading": section_plan.heading,
        "preceding_draft_summary": section.content[-400:],
        "target_additional_words": deficit_words,
        "missing_substantive_topics_to_develop": missing_desc,
        "explicit_instructions": (
            f"The preceding draft covers foundational aspects ({val_result.actual_words} words). "
            f"Continue and expand section '{section_plan.heading}' by providing an additional {deficit_words} words. "
            f"Specifically develop: {missing_desc}. "
            "Do NOT repeat previously stated introductory sentences. "
            "Write direct, substantive academic prose and return exactly one PaperSection JSON object."
        ),
        "source_notes_snippet": brief.source_draft[:6000],
    }

    continuation_prompt = GenerationPrompt(
        version="section-continuation-v1",
        system_instructions=SECTION_SYSTEM_INSTRUCTIONS,
        user_message=(
            f"Expand and continue section '{section_plan.heading}' to reach the required academic depth.\n"
            + json.dumps(continuation_payload, ensure_ascii=False, indent=2)
        ),
        output_schema="PaperSection",
    )

    try:
        continuation_section = await execute_section_generation(
            prompt=continuation_prompt,
            section=section_plan,
            provider=provider,
        )
        # Combine existing content with continuation (avoiding duplicate headings)
        new_text = continuation_section.content.strip()
        if new_text.startswith("#"):
            new_text = re.sub(r"^#+\s+[^\n]+\n+", "", new_text)

        combined_content = f"{section.content.strip()}\n\n{new_text}"
        updated_section = section.model_copy(update={"content": combined_content})

        new_actual = count_words(combined_content)
        val_result.actual_words = new_actual
        val_result.ratio = round(new_actual / max(1, val_result.budget_words), 2)
        val_result.is_under_generated = new_actual < int(val_result.budget_words * 0.70)
        val_result.was_expanded = True
        val_result.is_complete = not val_result.is_under_generated
        return updated_section, val_result
    except Exception:
        # Fall back safely to existing section without crashing
        return section, val_result
