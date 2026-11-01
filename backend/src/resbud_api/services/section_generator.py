"""Section-level academic prose generator with context preservation and grounding constraints."""

from __future__ import annotations

import json
from typing import Any

from resbud_api.domain.manuscript_plan import ManuscriptPlan, PlannedSection
from resbud_api.domain.models import PaperDraft, PaperSection
from resbud_api.providers.base import (
    GenerationPrompt,
    ProviderResult,
    ResearchBrief,
    SectionRegenerationInput,
)

SECTION_SYSTEM_INSTRUCTIONS = """You are an expert scientific researcher and academic author.
Write an exhaustive, rigorous, deeply developed, multi-paragraph academic section for a peer-reviewed research paper.

CRITICAL REQUIREMENTS:
1. Target Section Word Budget:
   * Actively write substantive academic prose to reach the specified allocated word budget (typically 400 to 1,500 words).
   * DO NOT write a shallow summary or single paragraph. Develop the arguments thoroughly across 3 to 6 rich paragraphs.
   * Divide the section into logical subsections where specified in the section plan.
2. Grounding in Evidence & Source Documentation:
   * Base all factual claims, metrics, and experimental numbers strictly on the supplied research evidence and notes.
   * Never invent fabricated empirical numbers or falsified datasets.
   * If specific empirical findings or laboratory parameters were absent from the source material for this section,
     include an explicit notice in the text:
     "[Note: Specific <experimental results / methodology details / dataset / limitations> were not provided in the source document. Insert your verified empirical findings and technical parameters here.]"
     and set state to "needs_input".
   * Sections whose core analytical content was supplied in the source document must have state "draft".
3. Terminology & Context Consistency:
   * Maintain strict consistency with the canonical terminology glossary and research objectives established in the manuscript plan.
   * Do NOT drift into conflicting terminology or alter the defined scope.
   * Transition smoothly from the preceding section's findings without repeating basic introductory throat-clearing.
4. Rich Academic Formatting:
   * Include structured markdown comparison tables (`| Column | Column |`) or equations where academically relevant.
   * If figure illustrations are referenced in the section plan, integrate them naturally into the prose:
     `![Figure X: <caption text>](<figure_id>)` and explain their significance in the surrounding text.

Return exactly one valid JSON object matching the PaperSection schema:
{
  "id": "<section_id>",
  "heading": "<section_heading>",
  "content": "<substantive multi-paragraph markdown text>",
  "state": "draft" | "needs_input" | "not_applicable"
}"""


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

    raw_state = str(data.get("state") or ("needs_input" if section.requires_input_notice else "draft")).lower()
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
        state=valid_state,
    )
