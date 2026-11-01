"""Academic quality evaluator assessing Depth, Integrity, and Structure dimensions.

This module evaluates academic writing rigor beyond superficial word counts:
- Depth: Substantive development, multi-paragraph progression, technical reasoning density, absence of filler.
- Integrity: Source grounding, numerical fidelity, citation fidelity, explicit unconducted experiment disclosures.
- Structure: Continuous prose over bullets (< 15%), research questions, paper roadmap, thematic literature categorization,
             mathematical/statistical rigor, validity analysis, and future trajectories.
"""

from __future__ import annotations

from dataclasses import dataclass, field
import re
from typing import Any

from resbud_api.domain.models import PaperDraft, PaperSection
from resbud_api.providers.base import ResearchBrief

_NUMBER = re.compile(r"\b\d+(?:[.,]\d+)*%?\b")

_FILLER_PHRASES = [
    "in today's world",
    "in today's fast-paced world",
    "at the end of the day",
    "needless to say",
    "first and foremost",
    "last but not least",
    "it is important to remember that",
    "as we all know",
    "it goes without saying",
    "throughout human history",
]

_TECHNICAL_VOCABULARY = [
    "algorithm",
    "architecture",
    "baseline",
    "benchmark",
    "contingency",
    "convergence",
    "correlation",
    "distribution",
    "empirical",
    "evaluation",
    "formulation",
    "hypothesis",
    "inference",
    "latency",
    "mcnemar",
    "metric",
    "p-value",
    "parameter",
    "precision",
    "probabilistic",
    "recall",
    "representation",
    "reproducibility",
    "significance",
    "statistical",
    "throughput",
    "validation",
    "variance",
]


@dataclass
class QualityDimensionScore:
    """Score and diagnostic report for an individual quality dimension."""

    dimension: str
    score: float  # 0.0 to 100.0
    passed: bool
    details: dict[str, Any] = field(default_factory=dict)
    deficiencies: list[str] = field(default_factory=list)
    strengths: list[str] = field(default_factory=list)


@dataclass
class AcademicQualityEvaluation:
    """Comprehensive academic quality report for a paper draft."""

    overall_score: float  # 0.0 to 100.0
    passed: bool
    depth: QualityDimensionScore
    integrity: QualityDimensionScore
    structure: QualityDimensionScore
    deficiencies: list[str] = field(default_factory=list)
    strengths: list[str] = field(default_factory=list)


def _get_substantive_paragraphs(text: str) -> list[str]:
    """Extract distinct non-heading, substantive prose paragraphs."""
    raw_paras = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]
    substantive = []
    for p in raw_paras:
        # Ignore markdown headers and table-only blocks
        lines = [line.strip() for line in p.splitlines() if line.strip()]
        if not lines:
            continue
        if all(line.startswith("#") for line in lines):
            continue
        if all(line.startswith("|") for line in lines):
            continue
        words = p.split()
        if len(words) >= 20:
            substantive.append(p)
    return substantive


def _calculate_ttr(text: str) -> float:
    """Compute Type-Token Ratio (lexical diversity) over lowercased word tokens."""
    tokens = [w.lower().strip(".,;:()[]\"'!?`") for w in text.split() if w.strip(".,;:()[]\"'!?`")]
    if not tokens:
        return 0.0
    return len(set(tokens)) / len(tokens)


def evaluate_depth(paper: PaperDraft, brief: ResearchBrief) -> QualityDimensionScore:
    """Evaluate substantive coverage, technical reasoning, and meaningful discussion."""
    deficiencies: list[str] = []
    strengths: list[str] = []
    details: dict[str, Any] = {}

    # 1. Paragraph Development (40 pts)
    # Major sections must have multi-paragraph development (>= 2 substantive paragraphs)
    total_major_sections = 0
    well_developed_sections = 0
    for section in paper.sections:
        if section.id in {"references", "abstract"}:
            continue
        total_major_sections += 1
        paras = _get_substantive_paragraphs(section.content)
        if len(paras) >= 2:
            well_developed_sections += 1
        else:
            deficiencies.append(
                f"Section '{section.heading}' lacks multi-paragraph progression ({len(paras)} substantive paragraphs)."
            )

    dev_ratio = well_developed_sections / max(1, total_major_sections)
    paragraph_pts = dev_ratio * 40.0
    if dev_ratio >= 0.8:
        strengths.append(f"Strong paragraph progression across {well_developed_sections}/{total_major_sections} sections.")
    details["paragraph_score"] = round(paragraph_pts, 2)
    details["well_developed_sections"] = f"{well_developed_sections}/{total_major_sections}"

    # 2. Technical Density and Reasoning (30 pts)
    combined_text = " ".join(s.content for s in paper.sections).lower()
    found_tech_terms = [t for t in _TECHNICAL_VOCABULARY if t in combined_text]
    has_math = bool(re.search(r"(\$|\\chi\^2|\\mathcal|\\sim|\\in|\\le|\\ge|p\s*=\s*0\.)", combined_text))

    tech_score = min(20.0, len(found_tech_terms) * 2.0)
    if has_math:
        tech_score += 10.0
        strengths.append("Incorporates formal mathematical / statistical notations.")
    else:
        tech_score = min(30.0, tech_score * 1.5)

    if len(found_tech_terms) >= 8:
        strengths.append(f"High technical vocabulary density ({len(found_tech_terms)} domain concepts).")
    else:
        deficiencies.append(f"Low technical vocabulary density ({len(found_tech_terms)} domain concepts identified).")
    details["technical_score"] = round(tech_score, 2)
    details["technical_terms_count"] = len(found_tech_terms)

    # 3. Substantive Tone & Absence of Platitudes (30 pts)
    ttr = _calculate_ttr(combined_text)
    platitudes_found = [p for p in _FILLER_PHRASES if p in combined_text]
    total_tokens = len(combined_text.split())
    # Account for document length (Herdan's law): long papers (>= 2500 words) have naturally lower raw TTR
    ttr_threshold = 0.12 if total_tokens >= 3500 else (0.20 if total_tokens >= 1500 else 0.35)

    tone_score = 30.0
    if ttr < ttr_threshold:
        tone_score -= 15.0
        deficiencies.append(f"Low lexical diversity (Type-Token Ratio {ttr:.2f} < {ttr_threshold:.2f} indicates repetitive phrasing).")
    else:
        strengths.append(f"High lexical diversity (Type-Token Ratio {ttr:.2f}).")

    if platitudes_found:
        penalty = min(20.0, len(platitudes_found) * 10.0)
        tone_score -= penalty
        deficiencies.append(f"Contains conversational platitudes or filler: {', '.join(platitudes_found)}")

    tone_score = max(0.0, tone_score)
    details["tone_score"] = round(tone_score, 2)
    details["ttr"] = round(ttr, 3)
    details["platitudes_count"] = len(platitudes_found)

    total_depth_score = min(100.0, paragraph_pts + tech_score + tone_score)
    passed = total_depth_score >= 60.0 and len(deficiencies) <= 1

    return QualityDimensionScore(
        dimension="depth",
        score=round(total_depth_score, 2),
        passed=passed,
        details=details,
        deficiencies=deficiencies,
        strengths=strengths,
    )


def evaluate_integrity(paper: PaperDraft, brief: ResearchBrief) -> QualityDimensionScore:
    """Evaluate evidence fidelity, zero hallucinated numbers, citation validity, and uncollected data safeguards."""
    deficiencies: list[str] = []
    strengths: list[str] = []
    details: dict[str, Any] = {}

    # 1. Numerical & Evidence Fidelity (40 pts)
    input_text = " ".join(
        filter(
            None,
            (
                brief.project.title,
                brief.project.research_question,
                brief.project.results,
                brief.project.methodology,
                brief.project.dataset_or_materials,
                brief.source_draft,
            ),
        )
    )
    supplied_numbers = set(_NUMBER.findall(input_text))
    paper_numbers = set(_NUMBER.findall(" ".join(s.content for s in paper.sections)))

    # Identify unsupported numbers (excluding section heading numbers, e.g. 1, 2, 3)
    unsupported_numbers = {
        n for n in paper_numbers if n not in supplied_numbers and not re.match(r"^[1-9]$", n)
    }

    numeric_score = 40.0
    if unsupported_numbers:
        # If unsupported numbers are percentages or decimal metrics, severe penalty
        metric_hallucinations = [n for n in unsupported_numbers if "%" in n or "." in n]
        if metric_hallucinations:
            numeric_score = max(0.0, 40.0 - (len(metric_hallucinations) * 15.0))
            deficiencies.append(
                f"Draft contains unsupported numerical/metric claims: {', '.join(sorted(metric_hallucinations)[:5])}"
            )
        else:
            numeric_score = max(20.0, 40.0 - (len(unsupported_numbers) * 5.0))
    else:
        strengths.append("Zero hallucinated numerical metrics or fabricated benchmark statistics.")
    details["numeric_score"] = round(numeric_score, 2)
    details["unsupported_numbers_count"] = len(unsupported_numbers)

    # 2. Citation Fidelity (30 pts)
    supplied_ref_ids = {r.id for r in brief.references}
    combined_content = " ".join(s.content for s in paper.sections)
    found_ref_markers = set(re.findall(r"\[(ref_[a-zA-Z0-9_\-]+)\]", combined_content))

    citation_score = 30.0
    invented_refs = found_ref_markers - supplied_ref_ids
    if invented_refs:
        citation_score = 0.0
        deficiencies.append(f"Draft references invented or unsupplied citation IDs: {', '.join(invented_refs)}")
    elif found_ref_markers:
        strengths.append(f"All citations ({len(found_ref_markers)}) strictly match supplied reference keys.")
    details["citation_score"] = round(citation_score, 2)

    # 3. Unconducted / Missing Experiment Safeguard (30 pts)
    unconducted_score = 30.0
    is_results_uncollected = brief.project.results_status in {"not_collected", "not_available", "unknown"} and not (
        brief.project.results and brief.project.results.strip()
    )

    results_section = next((s for s in paper.sections if "result" in s.id.lower()), None)
    if is_results_uncollected and results_section:
        # Must declare unconducted and state must be needs_input
        has_disclosure = "[Note:" in results_section.content or "not conducted" in results_section.content.lower()
        if results_section.state == "needs_input" and has_disclosure:
            strengths.append("Explicitly declared unconducted experimental status without fabricating results.")
        else:
            unconducted_score = 0.0
            deficiencies.append(
                "Results were not collected, but the results section failed to include an explicit limitation notice "
                "or was not flagged with state 'needs_input'."
            )
    elif not is_results_uncollected and results_section:
        if results_section.state == "draft":
            strengths.append("Supplied empirical results accurately preserved in draft state.")
    details["unconducted_safeguard_score"] = round(unconducted_score, 2)

    total_integrity_score = min(100.0, numeric_score + citation_score + unconducted_score)
    passed = total_integrity_score >= 70.0 and len(deficiencies) == 0

    return QualityDimensionScore(
        dimension="integrity",
        score=round(total_integrity_score, 2),
        passed=passed,
        details=details,
        deficiencies=deficiencies,
        strengths=strengths,
    )


def evaluate_structure(paper: PaperDraft, brief: ResearchBrief) -> QualityDimensionScore:
    """Evaluate continuous prose ratio (< 15% bullets), introduction roadmap, and academic structure."""
    deficiencies: list[str] = []
    strengths: list[str] = []
    details: dict[str, Any] = {}

    # 1. Continuous Academic Prose over Bullets (< 15% bullets) (30 pts)
    all_lines = []
    bullet_lines = 0
    for section in paper.sections:
        for line in section.content.splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#") or stripped.startswith("|") or stripped.startswith("---"):
                continue
            all_lines.append(stripped)
            if re.match(r"^([*+-]|\d+\.)\s+", stripped):
                bullet_lines += 1

    total_prose_lines = max(1, len(all_lines))
    bullet_ratio = bullet_lines / total_prose_lines
    details["bullet_ratio"] = round(bullet_ratio, 3)
    details["bullet_lines"] = bullet_lines
    details["total_prose_lines"] = total_prose_lines

    prose_score = 30.0
    if bullet_ratio > 0.15:
        excess = bullet_ratio - 0.15
        penalty = min(30.0, (excess / 0.15) * 30.0)
        prose_score -= penalty
        deficiencies.append(
            f"Excessive bullet points: {bullet_ratio:.1%} of prose lines are bullets (limit is < 15%)."
        )
    else:
        strengths.append(f"Continuous academic prose maintained ({bullet_ratio:.1%} bullet lines, well below 15% ceiling).")
    details["prose_score"] = round(prose_score, 2)

    # 2. Introduction Structure & Roadmap (35 pts)
    intro_score = 35.0
    intro_section = next((s for s in paper.sections if "intro" in s.id.lower()), None)
    if intro_section:
        intro_content = intro_section.content.lower()
        has_rq = bool(re.search(r"\b(rq\d+|research question|research questions)\b", intro_content))
        has_contributions = bool(re.search(r"\b(contribution|contributions|we propose|this paper contributes)\b", intro_content))
        has_roadmap = bool(
            re.search(
                r"\b(remainder of this paper|paper is (organized|structured) as follows|the rest of this paper)\b",
                intro_content,
            )
        )

        if not has_rq:
            intro_score -= 10.0
            deficiencies.append("Introduction lacks explicit Research Questions (e.g. RQ1, RQ2).")
        else:
            strengths.append("Explicitly articulates structured Research Questions in the Introduction.")

        if not has_contributions:
            intro_score -= 10.0
            deficiencies.append("Introduction lacks an itemized list of research contributions.")
        else:
            strengths.append("Identifies clear scientific contributions in the Introduction.")

        if not has_roadmap:
            intro_score -= 15.0
            deficiencies.append("Introduction lacks a formal paper roadmap paragraph ('The remainder of this paper...').")
        else:
            strengths.append("Contains a formal academic roadmap paragraph structuring subsequent sections.")
    else:
        intro_score = 0.0
    details["intro_score"] = round(intro_score, 2)

    # 3. Section-Specific Academic Rigor (35 pts)
    # Check related work, methodology, results, discussion, conclusion
    section_rigor_score = 35.0
    rigor_deductions = 0.0

    # Related work: thematic grouping
    rel_section = next((s for s in paper.sections if "related" in s.id.lower() or "lit" in s.id.lower()), None)
    if rel_section:
        rel_content = rel_section.content.lower()
        has_subsections = "###" in rel_section.content or "##" in rel_section.content
        has_comparative_terms = bool(
            re.search(r"\b(contrast|conversely|in contrast|whereas|paradigms?|limitations?)\b", rel_content)
        )
        if not (has_subsections or has_comparative_terms):
            rigor_deductions += 7.0
            deficiencies.append("Related Work lacks thematic categorization or comparative synthesis.")
        else:
            strengths.append("Related Work organized into comparative thematic categories.")

    # Methodology: formal metrics / math / statistical tests
    method_section = next((s for s in paper.sections if "method" in s.id.lower() or "system" in s.id.lower()), None)
    if method_section:
        method_content = method_section.content.lower()
        has_formal_eval = bool(
            re.search(r"(\$|mcnemar|t-test|p-value|metric|precision|recall|accuracy|f1|chi\^2|p\s*<)", method_content)
        )
        if not has_formal_eval:
            rigor_deductions += 7.0
            deficiencies.append("Methodology lacks formal evaluation metric definitions or statistical test specifications.")
        else:
            strengths.append("Methodology includes formal metric definitions and statistical significance specifications.")

    # Results: structured comparison / tables
    results_section = next((s for s in paper.sections if "result" in s.id.lower()), None)
    if results_section and results_section.state == "draft":
        has_table = "|" in results_section.content
        has_quantitative_comparison = bool(re.search(r"\b\d+([.,]\d+)?%\b", results_section.content))
        if not (has_table or has_quantitative_comparison):
            rigor_deductions += 7.0
            deficiencies.append("Results section lacks quantitative comparative tables or structured metrics.")
        else:
            strengths.append("Results section presents findings in a structured comparative format.")

    # Discussion: threats to validity
    disc_section = next((s for s in paper.sections if "discuss" in s.id.lower()), None)
    if disc_section:
        disc_content = disc_section.content.lower()
        has_validity = bool(
            re.search(r"\b(threats? to validity|internal validity|external validity|construct validity|limitations?)\b", disc_content)
        )
        if not has_validity:
            rigor_deductions += 7.0
            deficiencies.append("Discussion section lacks an analysis of threats to validity (internal/external/construct).")
        else:
            strengths.append("Discussion systematically addresses threats to validity and technical trade-offs.")

    # Conclusion: synthesis and future directions
    conc_section = next((s for s in paper.sections if "conclus" in s.id.lower()), None)
    if conc_section:
        conc_content = conc_section.content.lower()
        has_future_work = bool(re.search(r"\b(future (work|directions|trajectories|research)|extensions)\b", conc_content))
        if not has_future_work:
            rigor_deductions += 7.0
            deficiencies.append("Conclusion lacks concrete actionable future research directions.")
        else:
            strengths.append("Conclusion articulates concrete, actionable future research trajectories.")

    section_rigor_score = max(0.0, section_rigor_score - rigor_deductions)
    details["section_rigor_score"] = round(section_rigor_score, 2)

    total_structure_score = min(100.0, prose_score + intro_score + section_rigor_score)
    passed = total_structure_score >= 60.0 and len(deficiencies) <= 1

    return QualityDimensionScore(
        dimension="structure",
        score=round(total_structure_score, 2),
        passed=passed,
        details=details,
        deficiencies=deficiencies,
        strengths=strengths,
    )


def evaluate_academic_quality(paper: PaperDraft, brief: ResearchBrief) -> AcademicQualityEvaluation:
    """Execute complete 3-dimensional academic quality evaluation across Depth, Integrity, and Structure."""
    depth_res = evaluate_depth(paper, brief)
    integrity_res = evaluate_integrity(paper, brief)
    structure_res = evaluate_structure(paper, brief)

    overall_score = round((depth_res.score + integrity_res.score + structure_res.score) / 3.0, 2)
    passed = overall_score >= 70.0 and depth_res.passed and integrity_res.passed and structure_res.passed

    all_deficiencies = depth_res.deficiencies + integrity_res.deficiencies + structure_res.deficiencies
    all_strengths = depth_res.strengths + integrity_res.strengths + structure_res.strengths

    return AcademicQualityEvaluation(
        overall_score=overall_score,
        passed=passed,
        depth=depth_res,
        integrity=integrity_res,
        structure=structure_res,
        deficiencies=all_deficiencies,
        strengths=all_strengths,
    )
