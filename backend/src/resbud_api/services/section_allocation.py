"""Adaptive section-level word budgeting based on paper type, evidence status, and scope."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from resbud_api.providers.base import ResearchBrief


@dataclass(frozen=True)
class SectionBudgetPlan:
    """Computed section allocation with rationale and evidence restrictions."""

    section_id: str
    heading: str
    purpose: str
    target_words: int
    weight_pct: float
    evidence_status: str
    is_evidence_constrained: bool
    subsections: list[tuple[str, str]]


# Standard empirical academic baseline (Prompt 3 specification)
STANDARD_EMPIRICAL_WEIGHTS: dict[str, float] = {
    "introduction": 0.17,
    "related_work": 0.15,
    "methodology": 0.20,
    "results": 0.15,
    "discussion": 0.20,
    "conclusion": 0.08,
}

THEORETICAL_WEIGHTS: dict[str, float] = {
    "introduction": 0.20,
    "related_work": 0.25,
    "methodology": 0.25,
    "discussion": 0.20,
    "conclusion": 0.10,
}

SURVEY_REVIEW_WEIGHTS: dict[str, float] = {
    "introduction": 0.15,
    "related_work": 0.40,
    "methodology": 0.15,
    "discussion": 0.20,
    "conclusion": 0.10,
}


def detect_paper_type(brief: ResearchBrief) -> str:
    """Classify the paper archetype to select appropriate structural allocations."""
    project = brief.project
    title_lower = project.title.lower()
    source_lower = brief.source_draft.lower()

    if any(k in title_lower for k in ("survey", "review", "systematic review", "meta-analysis")):
        return "survey"
    if project.results_status in ("not_applicable",) or "conceptual" in source_lower:
        return "theoretical"
    if project.methodology_status == "not_applicable" and project.results_status == "not_applicable":
        return "theoretical"
    return "empirical"


def compute_adaptive_section_budgets(
    brief: ResearchBrief,
    total_target_words: int,
) -> tuple[int, list[SectionBudgetPlan], list[str]]:
    """Calculate mathematically allocated section word budgets adapted to evidence and discipline.

    Returns:
        (abstract_words, list of SectionBudgetPlan, list of evidence restriction notes)
    """
    evidence_restrictions: list[str] = []

    # 1. Abstract allocation: 4-5% of total budget (capped between 150 and 300 words)
    abstract_words = min(300, max(150, int(round(total_target_words * 0.05))))
    net_body_words = total_target_words - abstract_words

    paper_type = detect_paper_type(brief)
    desired_sections = [s.strip().lower() for s in brief.preferences.desired_sections if s.strip()]

    # 2. Select initial base weights based on paper type
    if paper_type == "survey":
        base_weights = dict(SURVEY_REVIEW_WEIGHTS)
    elif paper_type == "theoretical":
        base_weights = dict(THEORETICAL_WEIGHTS)
    else:
        base_weights = dict(STANDARD_EMPIRICAL_WEIGHTS)

    # 3. Adapt for Experimental Evidence Availability
    has_results = brief.project.results_status == "provided" and bool(brief.project.results)
    if not has_results and "results" in base_weights:
        # Cannot generate a full empirical results section without collected data
        evidence_restrictions.append(
            f"Experimental results not collected/provided (status: '{brief.project.results_status}'). "
            "Results budget reallocated to Methodology and Theoretical Discussion to prevent hallucination."
        )
        lost_results_weight = base_weights.pop("results")
        # Reallocate 60% to methodology and 40% to discussion
        if "methodology" in base_weights:
            base_weights["methodology"] += lost_results_weight * 0.60
        if "discussion" in base_weights:
            base_weights["discussion"] += lost_results_weight * 0.40

    if brief.project.methodology_status != "provided" and "methodology" in base_weights:
        evidence_restrictions.append(
            f"Methodology details not fully supplied (status: '{brief.project.methodology_status}'). "
            "Section will establish formal problem requirements and solicit parameter inputs."
        )

    # 4. Adapt for Research Discipline
    discipline = brief.project.research_field.lower()
    if any(k in discipline for k in ("computer science", "artificial intelligence", "machine learning", "engineering")):
        if "methodology" in base_weights:
            base_weights["methodology"] += 0.03
        if "introduction" in base_weights:
            base_weights["introduction"] = max(0.12, base_weights["introduction"] - 0.03)
    elif any(k in discipline for k in ("history", "humanities", "philosophy", "literature")):
        if "related_work" in base_weights:
            base_weights["related_work"] += 0.05
        if "discussion" in base_weights:
            base_weights["discussion"] += 0.03
        if "methodology" in base_weights:
            base_weights["methodology"] = max(0.10, base_weights["methodology"] - 0.08)

    # 5. Adapt for Target Length Scope
    if total_target_words <= 2000:
        # Short paper: streamline literature review, emphasize method and immediate takeaways
        if "related_work" in base_weights:
            excess = base_weights["related_work"] - 0.10
            if excess > 0:
                base_weights["related_work"] = 0.10
                if "methodology" in base_weights:
                    base_weights["methodology"] += excess
    elif total_target_words >= 6000:
        # Extended paper: expand literature review and analytical discussion
        if "discussion" in base_weights:
            base_weights["discussion"] += 0.02

    # 6. Filter by User Requested Sections (if supplied)
    if desired_sections:
        # If user explicitly requested sections, map to existing or custom
        mapped_weights: dict[str, float] = {}
        for s in desired_sections:
            if s == "abstract":
                continue
            canonical = s.replace("-", "_")
            if canonical in base_weights:
                mapped_weights[canonical] = base_weights[canonical]
            elif "intro" in canonical:
                mapped_weights[canonical] = base_weights.get("introduction", 0.18)
            elif "method" in canonical:
                mapped_weights[canonical] = base_weights.get("methodology", 0.22)
            elif "result" in canonical:
                mapped_weights[canonical] = 0.15 if has_results else 0.05
            elif "disc" in canonical:
                mapped_weights[canonical] = base_weights.get("discussion", 0.20)
            elif "relat" in canonical or "lit" in canonical:
                mapped_weights[canonical] = base_weights.get("related_work", 0.15)
            elif "concl" in canonical:
                mapped_weights[canonical] = base_weights.get("conclusion", 0.08)
            else:
                mapped_weights[canonical] = 0.15
        active_weights = mapped_weights
    else:
        active_weights = base_weights

    # Normalize active weights to sum exactly to 1.0
    sum_weights = sum(active_weights.values())
    normalized_weights = {k: v / sum_weights for k, v in active_weights.items()}

    # 7. Construct SectionBlueprints with Detailed Heading and Purpose
    section_specs: dict[str, dict[str, Any]] = {
        "introduction": {
            "heading": "1. Introduction and Problem Statement",
            "purpose": "Establish scientific motivation, operational context, specific research questions, and contributions.",
            "subsections": [
                ("Context & Motivation", "Broader scientific landscape and core engineering challenges."),
                ("Problem Formulation", "Formal technical definition of the operational bottleneck."),
                ("Research Questions & Contributions", "Explicit enumeration of questions (RQ1, RQ2) and specific contributions."),
            ],
        },
        "related_work": {
            "heading": "2. Related Work and Theoretical Foundations",
            "purpose": "Situate work within existing academic literature, contrasting prior methodologies with the current approach.",
            "subsections": [
                ("Baseline Approaches", "Historical algorithms and their scaling bounds."),
                ("Recent Advances in the Domain", "Modern paradigms, algorithmic variants, and benchmark limits."),
                ("Differentiation from Prior Art", "Specific limitations in existing literature addressed by this paper."),
            ],
        },
        "literature_review": {
            "heading": "2. Literature Review",
            "purpose": "Comprehensive review of theoretical background and comparative literature.",
            "subsections": [
                ("Foundational Concepts", "Core conceptual underpinnings."),
                ("Comparative Analysis of Prior Studies", "Strengths and weaknesses of prior work."),
                ("Synthesis & Research Gap", "Identification of open problems addressed herein."),
            ],
        },
        "methodology": {
            "heading": "3. System Architecture and Methodology",
            "purpose": "Detail step-by-step technical architecture, parameters, data sampling protocols, and evaluation metrics.",
            "subsections": [
                ("System Architecture & Pipeline", "End-to-end component flow, module interfaces, and representations."),
                ("Dataset Construction & Sampling", "Data curation, filtering criteria, and benchmark splits."),
                ("Evaluation Metrics & Experimental Protocol", "Formal metrics, inter-annotator agreement, and scoring criteria."),
            ],
        },
        "results": {
            "heading": "4. Empirical Results and Quantitative Evaluation",
            "purpose": "Present empirical measurements, paired comparison tables, statistical significance tests, and ablation insights.",
            "subsections": [
                ("Primary Benchmark Findings", "Comparative performance tables against baseline conditions."),
                ("Statistical Significance & Error Breakdown", "Hypothesis testing, p-values, discordant pair analysis."),
                ("Ablation & Sensitivity Analysis", "Impact of architectural components, parameter sweeps, and failure modes."),
            ],
        },
        "discussion": {
            "heading": "5. Discussion and Critical Limitations",
            "purpose": "Interpret findings, evaluate practical trade-offs, state explicit assumptions, and disclose limitations.",
            "subsections": [
                ("Analytical Interpretation", "Theoretical implications of observed performance differentials."),
                ("Deployment Trade-offs", "Latency, computational cost, and engineering practicalities."),
                ("Disclosed Limitations", "Corpus scope, synthetic artifacts, and unverified assumptions."),
            ],
        },
        "conclusion": {
            "heading": "6. Conclusion and Future Directions",
            "purpose": "Synthesize core conclusions, summarize validated takeaways, and outline prioritized future research avenues.",
            "subsections": [
                ("Summary of Contributions", "Concise restatement of validated empirical takeaways."),
                ("Future Trajectories", "Prioritized avenues for scaling, generalization, and open questions."),
            ],
        },
    }

    budget_plans: list[SectionBudgetPlan] = []
    accumulated_words = 0
    items = list(normalized_weights.items())

    for idx, (sec_id, weight) in enumerate(items):
        if idx == len(items) - 1:
            # Last section absorbs rounding difference so total equals exactly net_body_words
            alloc_words = max(100, net_body_words - accumulated_words)
        else:
            alloc_words = max(100, int(round(net_body_words * weight)))
            accumulated_words += alloc_words

        spec = section_specs.get(
            sec_id,
            {
                "heading": sec_id.replace("_", " ").title(),
                "purpose": f"Comprehensive academic analysis of {sec_id.replace('_', ' ')}.",
                "subsections": [("Analysis", "Detailed domain analysis.")],
            },
        )

        is_constrained = False
        evidence_status = "provided"
        if sec_id == "results" and not has_results:
            is_constrained = True
            evidence_status = brief.project.results_status
        elif sec_id == "methodology" and brief.project.methodology_status != "provided":
            is_constrained = True
            evidence_status = brief.project.methodology_status

        budget_plans.append(
            SectionBudgetPlan(
                section_id=sec_id,
                heading=spec["heading"],
                purpose=spec["purpose"],
                target_words=alloc_words,
                weight_pct=round(weight * 100, 1),
                evidence_status=evidence_status,
                is_evidence_constrained=is_constrained,
                subsections=spec["subsections"],
            )
        )

    return abstract_words, budget_plans, evidence_restrictions
