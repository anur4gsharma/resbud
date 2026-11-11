"""Section-level academic prose generator with context preservation, depth directives, and grounding constraints."""

from __future__ import annotations

import json
import re
from typing import Any, cast

from resbud_api.domain.manuscript_plan import ManuscriptPlan, PlannedSection
from resbud_api.domain.models import PaperSection, SectionState
from resbud_api.providers.base import (
    GenerationPrompt,
    ProviderResult,
    ResearchBrief,
    SectionRegenerationInput,
)

SECTION_SYSTEM_INSTRUCTIONS = """You are an expert scientific researcher and senior academic author.
Write an exhaustive, rigorous, deeply developed, multi-paragraph academic section for a peer-reviewed research paper.

ACADEMIC RIGOR & DEPTH INVARIANTS:
1. Substantive Multi-Paragraph Development:
   * Actively write substantive academic prose to reach the allocated word budget (typically 400 to 1,500 words).
   * Never output a shallow summary or single paragraph. Fully develop technical reasoning across multiple substantive paragraphs.
   * Divide the section into logical subsections where specified in the section plan.

2. Continuous Academic Prose (Prose over Bullets):
   * Write predominantly in flowing, continuous academic prose.
   * Bulleted or numbered lists MUST comprise less than 15% of total lines, reserved strictly for explicit research questions or enumerated contributions.
   * Avoid outline-style writing, bullet-heavy summaries, or superficial checklists.

3. Strict Evidence Fidelity & Zero Hallucination:
   * Base all factual claims, metrics, and experimental numbers strictly on supplied research evidence.
   * Never invent fabricated empirical numbers, synthetic benchmarks, or falsified datasets.
   * If specific empirical findings or laboratory parameters were absent from the source material for this section,
     include an explicit notice in the text:
     "[Note: Specific <experimental results / methodology details / dataset / limitations> were not provided in the source document. Insert your verified empirical findings and technical parameters here.]"
     and set state to "needs_input".
   * For sections with provided empirical evidence, set state to "draft".

4. Academic Section Norms:
   * Introduction: Provide scientific context, research questions (RQ1, RQ2), enumerated contributions, and end with a structured paper roadmap ("The remainder of this paper is structured as follows...").
   * Related Work: Group literature into thematic categories or paradigms. Compare approaches rather than sequentially listing citations. Do not invent unprovided references.
   * Methodology: Detail reproducible research design, algorithms, formal evaluation metric equations, and statistical significance tests.
   * Results: Present data accurately with numeric fidelity and markdown tables where supported. Never invent uncollected data.
   * Discussion: Interpret findings, address trade-offs, and explicitly analyze threats to validity (internal, external, construct, conclusion).
   * Conclusion: Synthesize findings, acknowledge limitations, and outline concrete future research trajectories without new experimental claims.

5. Rich Formatting & Terminology:
   * Use formal mathematical notation ($k$, $\\mathcal{D}$, formulas) and structured markdown comparison tables (`| Column | Column |`) where academically relevant.
   * Maintain strict consistency with the canonical terminology glossary.

Return exactly one valid JSON object matching the PaperSection schema:
{
  "id": "<section_id>",
  "heading": "<section_heading>",
  "content": "<substantive multi-paragraph markdown text>",
  "state": "draft" | "needs_input" | "not_applicable"
}"""


def get_section_academic_directives(
    section_id: str,
    section_heading: str,
    has_results: bool = True,
    brief: ResearchBrief | None = None,
) -> dict[str, Any]:
    """Provide specialized academic directives based on the section's canonical academic role."""
    norm_id = section_id.lower().replace("-", "_")
    norm_heading = section_heading.lower()

    if "intro" in norm_id or "intro" in norm_heading:
        return {
            "section_type": "introduction",
            "academic_purpose": "Establish scientific context, define problem & motivation, formulate research questions, enumerate contributions, and provide paper roadmap.",
            "mandatory_elements": [
                "Technical and scientific background context without conversational filler.",
                "Explicit problem formulation and research motivation.",
                "Research gap identified in existing paradigms.",
                "Formal Research Questions (e.g., RQ1 and RQ2).",
                "Itemized primary research contributions.",
                "Paper organization roadmap paragraph ('The remainder of this paper is structured as follows: Section 2 reviews related work...').",
            ],
            "style_invariants": [
                "Write in continuous, authoritative academic prose.",
                "Bullet points must comprise < 15% of lines, reserved strictly for explicit research questions or contributions.",
                "Avoid empty introductory cliches (e.g., 'In today's fast-paced world').",
            ],
        }
    elif (
        "related" in norm_id
        or "lit" in norm_id
        or "related" in norm_heading
        or "literature" in norm_heading
    ):
        return {
            "section_type": "related_work",
            "academic_purpose": "Thematically categorize prior literature, contrast methodologies and limitations based strictly on provided material.",
            "mandatory_elements": [
                "Thematic grouping of provided references into conceptual paradigms or subsections.",
                "Comparative analysis of methodologies, strengths, and limitations across references.",
                "Explicit contrast of how this work addresses limitations in prior approaches.",
            ],
            "style_invariants": [
                "Cite provided references using [ref_id] bracket notation.",
                "Never invent external citations or publications not in the brief.",
                "Do not claim an exhaustive literature review was conducted.",
                "Maintain continuous academic comparative prose.",
            ],
        }
    elif (
        "method" in norm_id
        or "approach" in norm_id
        or "system" in norm_id
        or "method" in norm_heading
    ):
        return {
            "section_type": "methodology",
            "academic_purpose": "Provide a rigorous, reproducible account of research design, data curation, algorithms, formal metrics, and statistical methods.",
            "mandatory_elements": [
                "Research design and experimental architecture.",
                "Dataset characteristics, sample size, and preprocessing procedures.",
                "Algorithmic formulation and formal pipelines.",
                "Baseline comparisons and experimental controls.",
                "Mathematical formulations for evaluation metrics (e.g., Precision, Recall, F1, McNemar).",
                "Explicit statistical significance testing methods and error bounds.",
            ],
            "style_invariants": [
                "Use formal mathematical notation ($k$, $\\mathcal{D}$, formulas) where appropriate.",
                "Never invent unreported hyperparameters or dataset features; note omitted parameters explicitly.",
                "Detail reproducibility factors without hand-waving.",
            ],
        }
    elif (
        "result" in norm_id
        or "eval" in norm_id
        or "result" in norm_heading
        or "finding" in norm_heading
    ):
        if has_results:
            return {
                "section_type": "results",
                "academic_purpose": "Present empirical findings with numerical fidelity, comparative tables, and statistical significance.",
                "mandatory_elements": [
                    "Preserve all numerical values, percentages, and units exactly as reported.",
                    "Structured markdown comparison table (| Condition | Metric | Value |) contrasting baselines.",
                    "Statistical significance reports (e.g., p-values, confidence intervals).",
                    "Ablation or condition-by-condition analysis where supported.",
                ],
                "style_invariants": [
                    "Never invent benchmark numbers or fabricated metrics.",
                    "Report both primary and secondary findings objectively.",
                ],
            }
        else:
            return {
                "section_type": "results",
                "academic_purpose": "Explicitly disclose that experiments were not performed, outline analytical expectations, and flag for researcher input.",
                "mandatory_elements": [
                    "Explicit declaration that empirical experiments have not been conducted.",
                    "Analytical framework or anticipated empirical outcomes based on methodology.",
                    "Mandatory insertion notice: '[Note: Specific experimental results were not provided in the source document. Insert your verified empirical findings and technical parameters here.]'",
                ],
                "style_invariants": [
                    "Set section state to 'needs_input'.",
                    "Do NOT fabricate hypothetical numbers as verified facts.",
                ],
            }
    elif "discuss" in norm_id or "discuss" in norm_heading:
        return {
            "section_type": "discussion",
            "academic_purpose": "Provide critical interpretation of results, theoretical/practical implications, trade-offs, and threats to validity.",
            "mandatory_elements": [
                "Direct interpretation answering the research questions (RQ1, RQ2).",
                "Comparison of findings against related work (agreements and divergences).",
                "Underlying mechanisms explaining the observed performance or trade-offs.",
                "Practical engineering and theoretical implications.",
                "Comprehensive Threats to Validity: Internal, External, Construct, and Conclusion validity.",
            ],
            "style_invariants": [
                "Strictly demarcate verified findings from analytical speculation.",
                "Address unexpected anomalies or trade-offs candidly.",
            ],
        }
    elif "conclus" in norm_id or "conclus" in norm_heading:
        return {
            "section_type": "conclusion",
            "academic_purpose": "Synthesize main contributions, summarize core limitations, and outline actionable future research trajectories.",
            "mandatory_elements": [
                "Succinct synthesis of demonstrated contributions and key takeaways.",
                "Direct acknowledgment of boundary conditions and foundational limitations.",
                "Concrete, actionable future research directions.",
            ],
            "style_invariants": [
                "Do NOT introduce new experimental findings or claims.",
                "Avoid merely restating the abstract; synthesize scientific significance.",
            ],
        }
    else:
        return {
            "section_type": "general",
            "academic_purpose": f"Develop a rigorous, deeply reasoned academic analysis of {section_heading}.",
            "mandatory_elements": [
                f"In-depth substantive discussion of {section_heading}.",
                "Grounding in supplied source material and logical argumentation.",
            ],
            "style_invariants": [
                "Continuous academic prose.",
                "Bullet lines < 15%.",
            ],
        }


def build_section_prompt(
    brief: ResearchBrief,
    plan: ManuscriptPlan,
    section: PlannedSection,
    previous_section_summary: str | None = None,
) -> GenerationPrompt:
    """Build a targeted, context-preserving prompt for generating a single academic section."""
    all_headings = [s.heading for s in plan.sections]

    subsections_desc = [
        f"  - Subsection: '{sub.title}' (Target ~{sub.target_words} words). Purpose: {sub.purpose}"
        for sub in section.subsections
    ]

    references_desc = [
        f"  - [{r.id}]: {r.text}"
        for r in brief.references
        if r.id in section.relevant_references or not section.relevant_references
    ]

    has_results = (
        brief.project.results_status == "provided"
        or bool(brief.project.results and brief.project.results.strip())
        or bool(re.search(r"\b\d+(?:\.\d+)?%", brief.source_draft))
    )

    directives = get_section_academic_directives(
        section_id=section.id,
        section_heading=section.heading,
        has_results=has_results,
        brief=brief,
    )

    user_payload: dict[str, Any] = {
        "global_manuscript_context": {
            "title": plan.title,
            "abstract": plan.abstract,
            "keywords": plan.keywords,
            "paper_type": plan.paper_type,
            "intended_structure": plan.intended_academic_structure,
            "document_sections_outline": all_headings,
            "terminology_glossary": plan.terminology_glossary,
        },
        "target_section_specification": {
            "id": section.id,
            "heading": section.heading,
            "purpose": section.purpose,
            "allocated_target_words": section.allocated_words,
            "planned_subsections": subsections_desc,
            "available_evidence": section.available_evidence,
            "key_arguments_to_develop": section.key_arguments,
            "missing_source_information": section.missing_information,
            "relevant_references": references_desc[:5],
            "requires_input_notice": section.requires_input_notice,
        },
        "section_academic_directives": directives,
        "continuity_and_transition": {
            "preceding_section_takeaway": previous_section_summary
            or "This is the opening section of the manuscript.",
            "directive": (
                "Do NOT repeat the general introductory context already established. Directly analyze "
                f"the specific designated scope of '{section.heading}'."
                if previous_section_summary
                else "Establish authoritative scientific context, research questions, and explicit contributions."
            ),
        },
        "source_research_notes": brief.source_draft[:12000],
    }

    return GenerationPrompt(
        version="section-v2",
        system_instructions=SECTION_SYSTEM_INSTRUCTIONS,
        user_message=(
            f"Synthesize the complete academic text for section '{section.heading}' (Target: {section.allocated_words} words).\n"
            + json.dumps(user_payload, ensure_ascii=False, indent=2)
        ),
        output_schema="PaperSection",
    )


async def execute_section_generation(
    prompt: GenerationPrompt,
    section: PlannedSection,
    provider: Any,
) -> PaperSection:
    """Execute section generation with provider adapters, supporting Gemini, OpenAI, Fake, and custom providers."""
    # 1. Direct adapter call if supported (e.g. GeminiProvider._request or generate_section)
    if hasattr(provider, "generate_section"):
        result: ProviderResult = await provider.generate_section(prompt)
        data = json.loads(result.structured_output)
    elif hasattr(provider, "_request"):
        result = await provider._request(prompt, PaperSection)
        data = json.loads(result.structured_output)
    elif hasattr(provider, "regenerate_section"):
        # Adapt to existing SectionRegenerationInput protocol
        from resbud_api.domain.models import PaperDraft, ProjectContext

        dummy_paper = PaperDraft(
            schema_version=1,
            title="Draft",
            abstract="Draft",
            keywords=["k1", "k2"],
            sections=[
                PaperSection(
                    id=section.id,
                    heading=section.heading,
                    content="Draft",
                    state="draft",
                )
            ],
            references=[],
            review_warnings=[],
        )
        dummy_brief = ResearchBrief(
            project=ProjectContext(
                title="Draft",
                research_field="CS",
                research_question="Q",
                objectives=[],
                claimed_contribution="C",
                methodology_status="unknown",
                dataset_or_materials_status="unknown",
                results_status="unknown",
                limitations_status="unknown",
            ),
            source_draft="",
            references=(),
            preferences=dummy_paper.references and None or None,  # type: ignore[arg-type]
        )
        regen_input = SectionRegenerationInput(
            brief=dummy_brief,
            current_paper=dummy_paper,
            target_section=dummy_paper.sections[0],
            user_instruction=f"Generate {section.heading} to target {section.allocated_words} words",
            prompt=prompt,
        )
        result = await provider.regenerate_section(regen_input)
        data = json.loads(result.structured_output)
    else:
        raise ValueError(f"Provider {type(provider)} does not support section generation.")

    # 2. Sanitize and validate returned PaperSection
    content = str(data.get("content") or "").strip()
    if not content:
        raise ValueError(f"Provider returned empty content for section {section.id}")

    raw_state = str(
        data.get("state") or ("needs_input" if section.requires_input_notice else "draft")
    ).lower()
    valid_state = raw_state if raw_state in {"draft", "needs_input", "not_applicable"} else "draft"
    if section.requires_input_notice and "[Note:" not in content:
        content = (
            f"{content}\n\n[Note: Specific experimental findings and technical parameters were not "
            f"fully detailed in the source document. Insert your verified data here.]"
        )
        valid_state = "needs_input"

    return PaperSection(
        id=section.id,
        heading=section.heading,
        content=content,
        state=cast(SectionState, valid_state),
    )
