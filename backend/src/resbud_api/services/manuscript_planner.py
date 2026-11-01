"""Manuscript Planning Service: constructs structured blueprints and section word budgets."""

from __future__ import annotations

import re
from typing import Any

from resbud_api.domain.manuscript_plan import (
    ManuscriptPlan,
    PlannedSection,
    PlannedSubsection,
)
from resbud_api.providers.base import ResearchBrief


def _normalize_title(brief: ResearchBrief) -> str:
    title = (brief.project.title or "").strip()
    if not title:
        title = "Empirical Research Investigation and Benchmark Analysis"
    return title[:300]


def _extract_domain_keywords(brief: ResearchBrief) -> list[str]:
    text = f"{brief.project.research_field} {brief.project.title} {brief.project.claimed_contribution} {brief.source_draft[:1000]}".lower()
    candidates = [
        ("retrieval-augmented generation", "Retrieval-Augmented Generation"),
        ("rag", "RAG Systems"),
        ("language models", "Large Language Models"),
        ("hallucination", "Hallucination Mitigation"),
        ("factual question answering", "Factual Question Answering"),
        ("surface codes", "Surface Codes"),
        ("quantum error correction", "Quantum Error Correction"),
        ("neural decoders", "Neural Decoders"),
        ("graph neural networks", "Graph Neural Networks"),
        ("equivariant", "Equivariant Deep Learning"),
        ("precision agriculture", "Precision Agriculture"),
        ("sensor telemetry", "Sensor Networks"),
        ("soil moisture", "Environmental Telemetry"),
        ("benchmark evaluation", "Empirical Evaluation"),
        ("statistical analysis", "Paired Hypothesis Testing"),
    ]
    extracted = []
    for term, label in candidates:
        if term in text and label not in extracted:
            extracted.append(label)
        if len(extracted) >= 6:
            break
    if len(extracted) < 3:
        if brief.project.research_field:
            extracted.append(brief.project.research_field.strip())
        extracted.extend(["Empirical Methodology", "Quantitative Benchmark", "System Evaluation"])
    return extracted[:6]


def _extract_terminology_glossary(brief: ResearchBrief) -> dict[str, str]:
    glossary: dict[str, str] = {}
    field = brief.project.research_field.strip()
    if field:
        glossary["Primary Domain"] = field

    if brief.project.claimed_contribution:
        glossary["Claimed Contribution"] = brief.project.claimed_contribution.strip()[:100]

    if brief.project.methodology:
        glossary["Primary Methodology"] = brief.project.methodology.strip()[:100]

    source = brief.source_draft
    # Extract numerical sample sizes / metrics / model names / statistical tests
    patterns = [
        (r"\b(\d+[\s-]*(?:benchmark|policy|sample|evaluation|test)[\s-]*(?:questions?|instances?|items?|cases?))\b", "Evaluation Sample Size"),
        (r"\b(Cohen['’]s kappa(?:\s*=\s*|\s*of\s*)[0-9.]+)\b", "Inter-Annotator Agreement"),
        (r"\b(Embed-Sim-v1|Sim-7B-Instruct|GPT-4o|Claude-3\.5|Llama-3|[A-Za-z0-9_-]+-7B)\b", "Evaluated Model Architecture"),
        (r"\b([0-9.]+\s*%\s*(?:accuracy|correctness|improvement|support))\b", "Primary Measured Metric"),
        (r"\b(McNemar(?:'s)?\s*test(?:\s*p-value\s*=?\s*[0-9.e-]+)?)\b", "Statistical Significance Test"),
        (r"\b(Retrieval-Augmented Generation|RAG)\b", "Core Architecture"),
    ]
    for pattern, label in patterns:
        match = re.search(pattern, source, flags=re.IGNORECASE)
        if match and label not in glossary:
            glossary[label] = match.group(1).strip()

    if not glossary:
        glossary["Target Framework"] = brief.project.title[:50]
        glossary["Primary Method"] = (brief.project.methodology or "Empirical Evaluation")[:50]
    return glossary


def _synthesize_abstract(brief: ResearchBrief, target_words: int) -> str:
    title = _normalize_title(brief)
    field = brief.project.research_field or "scientific inquiry"
    question = brief.project.research_question or "the core research problem"
    contribution = brief.project.claimed_contribution or "a structured methodological evaluation"
    method = brief.project.methodology or "a rigorous empirical comparison"
    results = brief.project.results or "quantitative improvements across primary benchmark indicators"
    limitations = brief.project.limitations or "specific boundary constraints and domain assumptions"

    abstract = (
        f"This study investigates {question} within the context of {field}. Addressing key challenges in "
        f"{title.lower()}, we present {contribution}. Through {method.lower()}, we examine operational behavior, "
        f"systematic failure modes, and statistical indicators under controlled experimental conditions. Empirical findings demonstrate "
        f"that {results.lower()}. While {limitations.lower()} present specific boundary conditions for deployment, these results "
        f"provide verifiable insights and establish foundational guidance for subsequent methodological refinement and reproducible scientific deployment."
    )
    return abstract


def create_manuscript_plan(
    brief: ResearchBrief,
    provider: Any | None = None,
) -> ManuscriptPlan:
    """Construct a validated ManuscriptPlan with rigorous word budgets and evidence mappings."""
    total_target = max(500, min(8000, brief.preferences.target_word_count))
    abstract_words = 200
    net_section_words = max(300, total_target - abstract_words)

    title = _normalize_title(brief)
    abstract = _synthesize_abstract(brief, total_target)
    keywords = _extract_domain_keywords(brief)
    glossary = _extract_terminology_glossary(brief)

    # 1. Determine Section Types and Headings
    desired = [s.strip() for s in brief.preferences.desired_sections if s.strip()]
    if not desired:
        # Synthesize domain-aware academic sections
        section_blueprints = [
            (
                "introduction",
                "1. Introduction and Problem Formulation",
                "Establish historical context, theoretical motivation, research gap, specific research questions, and explicit paper contributions.",
                0.18,
                [
                    ("Context & Motivation", "Broader scientific landscape and core engineering challenges."),
                    ("Problem Formulation", "Formal technical definition of the operational bottleneck."),
                    ("Research Questions & Contributions", "Explicit enumeration of questions (RQ1, RQ2) and specific contributions."),
                ],
            ),
            (
                "related_work",
                "2. Theoretical Foundations and Related Work",
                "Situate work within existing academic literature, contrasting prior methodologies with the current approach.",
                0.14,
                [
                    ("Classical & Baseline Approaches", "Historical algorithms and their scaling bounds."),
                    ("Recent Advances in the Domain", "Modern paradigms, algorithmic variants, and benchmark limits."),
                    ("Differentiation from Prior Art", "Specific limitations in existing literature addressed by this paper."),
                ],
            ),
            (
                "methodology",
                "3. System Architecture and Experimental Methodology",
                "Detail step-by-step technical architecture, parameters, data sampling protocols, and evaluation metrics.",
                0.28,
                [
                    ("System Architecture & Pipeline", "End-to-end component flow, module interfaces, and representations."),
                    ("Dataset Construction & Sampling", "Data curation, filtering criteria, and benchmark splits."),
                    ("Evaluation Metrics & Annotation Protocol", "Formal metrics, inter-annotator agreement, and scoring criteria."),
                ],
            ),
            (
                "results",
                "4. Empirical Results and Quantitative Evaluation",
                "Present empirical measurements, paired comparison tables, statistical significance tests, and ablation insights.",
                0.26,
                [
                    ("Primary Benchmark Findings", "Comparative performance tables against baseline conditions."),
                    ("Statistical Significance & Error Breakdown", "Hypothesis testing, p-values, discordant pair analysis."),
                    ("Ablation & Sensitivity Analysis", "Impact of architectural components, parameter sweeps, and failure modes."),
                ],
            ),
            (
                "discussion",
                "5. In-Depth Discussion and Critical Limitations",
                "Interpret findings, evaluate practical trade-offs, state explicit assumptions, and disclose limitations.",
                0.10,
                [
                    ("Analytical Interpretation", "Theoretical implications of observed performance differentials."),
                    ("Deployment Trade-offs", "Latency, computational cost, and engineering practicalities."),
                    ("Disclosed Limitations", "Corpus scope, synthetic artifacts, and unverified assumptions."),
                ],
            ),
            (
                "conclusion",
                "6. Conclusion and Future Directions",
                "Synthesize core conclusions, summarize validated takeaways, and outline prioritized future research avenues.",
                0.04,
                [
                    ("Summary of Contributions", "Concise restatement of validated empirical takeaways."),
                    ("Future Trajectories", "Prioritized avenues for scaling, generalization, and open questions."),
                ],
            ),
        ]
    else:
        # Map user desired section IDs to academic sections
        raw_map = {
            "abstract": (
                "abstract",
                "Abstract",
                "Formal synthesis of problem, method, and key findings.",
                0.05,
            ),
            "introduction": (
                "introduction",
                "1. Introduction",
                "Scientific context, research questions, and contributions.",
                0.20,
            ),
            "literature_review": (
                "literature_review",
                "2. Literature Review",
                "Theoretical background and comparative literature review.",
                0.15,
            ),
            "methodology": (
                "methodology",
                "3. Methodology",
                "System architecture, mathematical formulations, and experimental design.",
                0.30,
            ),
            "results": (
                "results",
                "4. Results",
                "Quantitative benchmarks, paired comparisons, and ablation findings.",
                0.25,
            ),
            "discussion": (
                "discussion",
                "5. Discussion",
                "Critical analysis of trade-offs, boundary conditions, and limitations.",
                0.15,
            ),
            "conclusion": (
                "conclusion",
                "6. Conclusion",
                "Synthesized conclusions and future trajectories.",
                0.05,
            ),
        }
        total_weight = sum(raw_map.get(s, (None, None, None, 0.20))[3] for s in desired)
        section_blueprints = []
        for s in desired:
            if s in raw_map:
                sec_id, heading, purpose, weight = raw_map[s]
            else:
                clean_heading = s.replace("_", " ").title()
                raw_sec = s.lower().replace("-", "_")[:40]
                sec_id = raw_sec if raw_sec and raw_sec[0].isalpha() else f"sec_{raw_sec}"
                heading = clean_heading
                purpose = f"Exhaustive academic analysis of {clean_heading}."
                weight = 0.20
            norm_weight = weight / total_weight if total_weight > 0 else (1.0 / len(desired))
            section_blueprints.append((sec_id, heading, purpose, norm_weight, []))

    # 2. Mathematically Compute Section Word Allocations
    planned_sections: list[PlannedSection] = []
    ref_ids = [r.id for r in brief.references]

    # Map available facts and limitations from ResearchBrief
    source_snippet = brief.source_draft[:3000]
    method_status = brief.project.methodology_status
    results_status = brief.project.results_status
    limitations_status = brief.project.limitations_status

    for sec_id, heading, purpose, weight, sub_specs in section_blueprints:
        alloc_words = max(100, int(round(net_section_words * weight)))

        # Subsections allocation
        subsections: list[PlannedSubsection] = []
        if sub_specs:
            sub_count = len(sub_specs)
            sub_word_budget = max(50, alloc_words // sub_count)
            for sub_title, sub_purpose in sub_specs:
                subsections.append(
                    PlannedSubsection(
                        title=sub_title,
                        purpose=sub_purpose,
                        target_words=sub_word_budget,
                        key_points=[f"Develop rigorous analysis of {sub_title.lower()}."],
                    )
                )

        evidence: list[str] = []
        missing_info: list[str] = []
        requires_notice = False

        if "intro" in sec_id:
            if brief.project.objectives:
                evidence.append(f"Research Objectives: {', '.join(brief.project.objectives)}")
            if brief.project.claimed_contribution:
                evidence.append(f"Contribution: {brief.project.claimed_contribution}")
        elif "method" in sec_id:
            if method_status == "provided" and brief.project.methodology:
                evidence.append(f"Methodology: {brief.project.methodology}")
            else:
                requires_notice = True
                missing_info.append("Specific experimental setup and sampling protocols not fully specified.")
            if brief.project.dataset_or_materials:
                evidence.append(f"Dataset/Materials: {brief.project.dataset_or_materials}")
        elif "result" in sec_id:
            if results_status == "provided" and brief.project.results:
                evidence.append(f"Results: {brief.project.results}")
            else:
                requires_notice = True
                missing_info.append("Specific empirical tables and measured numbers not provided in source.")
        elif "disc" in sec_id or "limit" in sec_id:
            if limitations_status == "provided" and brief.project.limitations:
                evidence.append(f"Limitations: {brief.project.limitations}")
            else:
                requires_notice = True
                missing_info.append("Explicit boundary limitations and failure cases not detailed in source.")

        planned_sections.append(
            PlannedSection(
                id=sec_id,
                heading=heading,
                purpose=purpose,
                allocated_words=alloc_words,
                subsections=subsections,
                available_evidence=evidence,
                relevant_references=ref_ids[:4],
                key_arguments=[
                    f"Rigorously develop {heading.split('. ')[-1]} in accordance with academic standards.",
                    "Ground all empirical arguments in the provided source documentation.",
                ],
                missing_information=missing_info,
                requires_input_notice=requires_notice,
            )
        )

    relationships = [
        "Section 1 establishes core research questions evaluated empirically in Sections 3 and 4.",
        "Section 3 outlines experimental controls directly measured in Section 4.",
        "Section 5 critically evaluates assumptions and threats to validity identified in Section 4.",
    ]

    limitations = []
    if brief.project.limitations:
        limitations.append(brief.project.limitations)
    if limitations_status != "provided":
        limitations.append("Source material lacked explicit disclosures of technical boundary limitations.")

    return ManuscriptPlan(
        paper_type="Empirical Benchmark & Evaluation Study",
        intended_academic_structure="Standard Peer-Reviewed Publication Format",
        title=title,
        abstract=abstract,
        keywords=keywords,
        total_target_words=total_target,
        sections=planned_sections,
        identified_limitations=limitations,
        terminology_glossary=glossary,
        cross_section_relationships=relationships,
    )
