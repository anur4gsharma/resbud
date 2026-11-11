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
from resbud_api.services.section_allocation import compute_adaptive_section_budgets


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


def _clean_academic_phrase(text: str, fallback: str) -> str:
    cleaned = (text or "").strip()
    residue_patterns = [
        r"synthesize and evaluate the research claims presented in the source document\.?",
        r"synthesize and evaluate the research claims\.?",
        r"insert your verified empirical findings.*",
        r"investigation and manuscript synthesis based on the supplied research dossier\.?",
        r"write a detailed introduction.*",
        r"add relevant discussion.*",
        r"provide more information.*",
    ]
    for pattern in residue_patterns:
        cleaned = re.sub(pattern, "", cleaned, flags=re.IGNORECASE).strip()
    return cleaned if cleaned else fallback


def _synthesize_abstract(brief: ResearchBrief, target_words: int) -> str:
    title = _normalize_title(brief)
    field = brief.project.research_field or "scientific inquiry"
    question = _clean_academic_phrase(
        brief.project.research_question,
        f"the comparative trade-offs in {title.lower()}",
    )
    contribution = _clean_academic_phrase(
        brief.project.claimed_contribution,
        "a controlled comparative evaluation and reproducible benchmark architecture",
    )
    method = brief.project.methodology or "a rigorous empirical comparison"
    limitations = brief.project.limitations or "specific boundary constraints and domain assumptions"

    has_results = (
        brief.project.results_status == "provided"
        and bool(brief.project.results and brief.project.results.strip())
    )
    if has_results:
        findings_clause = f"Empirical findings demonstrate that {brief.project.results.strip().lower()}."
    else:
        findings_clause = (
            "Although empirical benchmarking experiments remain proposed without collected evaluation data, "
            "the protocol formalizes standardized baseline controls, evaluation metrics, and operational boundaries."
        )

    abstract = (
        f"This study investigates {question} within the context of {field}. Addressing key challenges in "
        f"{title.lower()}, we present {contribution}. Through {method.lower()}, we examine operational behavior, "
        f"systematic failure modes, and statistical indicators under controlled experimental conditions. {findings_clause} "
        f"While {limitations.lower()} present specific boundary conditions for deployment, these results "
        f"provide verifiable insights and establish foundational guidance for subsequent methodological refinement and reproducible scientific deployment."
    )
    return abstract


def create_manuscript_plan(
    brief: ResearchBrief,
    provider: Any | None = None,
) -> ManuscriptPlan:
    """Construct a validated ManuscriptPlan with rigorous adaptive word budgets and evidence mappings."""
    total_target = max(500, min(8000, brief.preferences.target_word_count))
    abstract_words, budget_plans, evidence_restrictions = compute_adaptive_section_budgets(
        brief, total_target
    )

    title = _normalize_title(brief)
    abstract = _synthesize_abstract(brief, total_target)
    keywords = _extract_domain_keywords(brief)
    glossary = _extract_terminology_glossary(brief)

    # Mathematically Map Adaptive Plans to PlannedSections
    planned_sections: list[PlannedSection] = []
    ref_ids = [r.id for r in brief.references]

    method_status = brief.project.methodology_status
    results_status = brief.project.results_status
    limitations_status = brief.project.limitations_status

    for plan in budget_plans:
        sec_id = plan.section_id
        alloc_words = plan.target_words

        # Subsections allocation
        subsections: list[PlannedSubsection] = []
        if plan.subsections:
            sub_count = len(plan.subsections)
            sub_word_budget = max(50, alloc_words // sub_count)
            for sub_title, sub_purpose in plan.subsections:
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
        requires_notice = plan.is_evidence_constrained

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
                heading=plan.heading,
                purpose=plan.purpose,
                allocated_words=alloc_words,
                subsections=subsections,
                available_evidence=evidence,
                relevant_references=ref_ids[:4],
                key_arguments=[
                    f"Rigorously develop {plan.heading.split('. ')[-1]} in accordance with academic standards.",
                    "Ground all empirical arguments in the provided source documentation.",
                ],
                missing_information=missing_info,
                requires_input_notice=requires_notice,
            )
        )

    relationships = [
        "Section 1 establishes core research questions evaluated empirically in subsequent sections.",
        "Methodology outlines experimental controls directly measured in empirical analyses.",
        "Discussion critically evaluates assumptions, trade-offs, and threats to validity.",
    ]

    limitations = list(evidence_restrictions)
    if brief.project.limitations:
        limitations.append(brief.project.limitations)
    if limitations_status != "provided" and "limitations" not in limitations:
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
