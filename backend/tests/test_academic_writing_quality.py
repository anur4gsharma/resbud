"""Automated test suite verifying Academic Writing Quality across Depth, Integrity, and Structure."""

from __future__ import annotations

import json
from pathlib import Path
import re
import pytest

from resbud_api.domain.models import (
    GenerationRequest,
    PaperDraft,
    PaperPreferences,
    PaperSection,
    ProjectContext,
    ReferenceInput,
)
from resbud_api.providers.base import ResearchBrief
from resbud_api.providers.fake import FakeProvider
from resbud_api.services.academic_quality_validator import (
    evaluate_academic_quality,
    evaluate_depth,
    evaluate_integrity,
    evaluate_structure,
)
from resbud_api.services.long_form_engine import generate_long_form_manuscript
from resbud_api.services.manuscript_planner import create_manuscript_plan
from resbud_api.services.section_generator import (
    build_section_prompt,
    get_section_academic_directives,
)

EVALUATION_V2_PATH = Path(__file__).parent / "evaluation" / "v2" / "manifest.json"
MANIFEST = json.loads(EVALUATION_V2_PATH.read_text())


def test_v2_manifest_structure_and_profiles() -> None:
    """Verify evaluation set v2 manifest conforms to specifications."""
    assert MANIFEST["evaluation_set"] == "resbud-backend-academic-quality-v2"
    assert MANIFEST["engine_type"] == "long-form-section-level"
    assert set(MANIFEST["quality_dimensions"]) == {"depth", "integrity", "structure"}
    assert len(MANIFEST["cases"]) == 4

    case_ids = [c["id"] for c in MANIFEST["cases"]]
    assert case_ids == [
        "empirical-benchmark-evaluation",
        "proposed-framework-uncollected-results",
        "comparative-literature-survey",
        "multimodal-clinical-architecture",
    ]


def test_academic_directives_generation() -> None:
    """Verify get_section_academic_directives generates section-specific requirements."""
    # 1. Introduction
    intro_dir = get_section_academic_directives("introduction", "Introduction")
    assert intro_dir["section_type"] == "introduction"
    elements_str = " ".join(intro_dir["mandatory_elements"]).lower()
    assert "roadmap" in elements_str
    assert "research questions" in elements_str
    assert "contributions" in elements_str

    # 2. Related Work
    rel_dir = get_section_academic_directives("related_work", "Related Literature")
    assert rel_dir["section_type"] == "related_work"
    assert any("thematic" in el.lower() for el in rel_dir["mandatory_elements"])
    assert any("never invent" in rule.lower() for rule in rel_dir["style_invariants"])

    # 3. Methodology
    meth_dir = get_section_academic_directives("methodology", "Methodology")
    assert meth_dir["section_type"] == "methodology"
    assert any("statistical significance" in el.lower() for el in meth_dir["mandatory_elements"])
    assert any("formal" in rule.lower() or "mathematical" in rule.lower() for rule in meth_dir["style_invariants"])

    # 4. Results (with and without results)
    res_provided = get_section_academic_directives("results", "Results", has_results=True)
    assert res_provided["section_type"] == "results"
    assert any("numerical values" in el.lower() for el in res_provided["mandatory_elements"])

    res_uncollected = get_section_academic_directives("results", "Results", has_results=False)
    assert res_uncollected["section_type"] == "results"
    assert any("needs_input" in rule for rule in res_uncollected["style_invariants"])
    assert any("not conducted" in el.lower() or "not provided" in el.lower() for el in res_uncollected["mandatory_elements"])

    # 5. Discussion
    disc_dir = get_section_academic_directives("discussion", "Discussion")
    assert disc_dir["section_type"] == "discussion"
    assert any("threats to validity" in el.lower() for el in disc_dir["mandatory_elements"])

    # 6. Conclusion
    conc_dir = get_section_academic_directives("conclusion", "Conclusion")
    assert conc_dir["section_type"] == "conclusion"
    assert any("future research" in el.lower() for el in conc_dir["mandatory_elements"])
    assert any("do not introduce new experimental" in rule.lower() for rule in conc_dir["style_invariants"])


def test_section_generator_embeds_directives_into_prompt() -> None:
    """Verify build_section_prompt includes section_academic_directives in user payload."""
    case = MANIFEST["cases"][0]
    brief = ResearchBrief(
        project=ProjectContext.model_validate(case["project"]),
        source_draft=case["source_draft"],
        references=tuple(ReferenceInput.model_validate(r) for r in case["references"]),
        preferences=PaperPreferences.model_validate(case["preferences"]),
    )
    provider = FakeProvider()
    plan = create_manuscript_plan(brief, provider)
    intro_section = plan.sections[0]

    prompt = build_section_prompt(brief, plan, intro_section)
    assert "section_academic_directives" in prompt.user_message
    payload = json.loads(prompt.user_message.split("\n", 1)[1])
    assert payload["section_academic_directives"]["section_type"] == "introduction"
    assert "roadmap" in " ".join(payload["section_academic_directives"]["mandatory_elements"]).lower()


@pytest.mark.anyio
async def test_academic_writing_quality_on_v2_evaluation_cases() -> None:
    """Verify all v2 evaluation cases satisfy Depth, Integrity, and Structure requirements."""
    provider = FakeProvider()

    for case in MANIFEST["cases"]:
        brief = ResearchBrief(
            project=ProjectContext.model_validate(case["project"]),
            source_draft=case["source_draft"],
            references=tuple(ReferenceInput.model_validate(r) for r in case["references"]),
            preferences=PaperPreferences.model_validate(case["preferences"]),
        )

        response = await generate_long_form_manuscript(brief, provider)
        paper = response.paper
        evaluation = evaluate_academic_quality(paper, brief)

        exp = case["expected_quality"]
        assert evaluation.passed is True, (
            f"Case '{case['id']}' failed academic quality evaluation: "
            f"Overall: {evaluation.overall_score}, Deficiencies: {evaluation.deficiencies}"
        )
        assert evaluation.depth.score >= exp["min_depth_score"], (
            f"Case '{case['id']}' depth score {evaluation.depth.score} < {exp['min_depth_score']}. "
            f"Deficiencies: {evaluation.depth.deficiencies}"
        )
        assert evaluation.integrity.score >= exp["min_integrity_score"], (
            f"Case '{case['id']}' integrity score {evaluation.integrity.score} < {exp['min_integrity_score']}. "
            f"Deficiencies: {evaluation.integrity.deficiencies}"
        )
        assert evaluation.structure.score >= exp["min_structure_score"], (
            f"Case '{case['id']}' structure score {evaluation.structure.score} < {exp['min_structure_score']}. "
            f"Deficiencies: {evaluation.structure.deficiencies}"
        )

        invariants = exp["required_invariants"]
        intro_sec = next((s for s in paper.sections if "intro" in s.id.lower()), None)
        if invariants.get("has_introduction_roadmap") and intro_sec:
            assert "remainder of this paper" in intro_sec.content.lower() or "structured as follows" in intro_sec.content.lower()

        if invariants.get("has_explicit_rqs") and intro_sec:
            assert "rq1" in intro_sec.content.lower() or "research question" in intro_sec.content.lower()

        if invariants.get("results_state_needs_input"):
            res_sec = next((s for s in paper.sections if "result" in s.id.lower()), None)
            assert res_sec is not None
            assert res_sec.state == "needs_input"
            assert "[Note:" in res_sec.content

        if invariants.get("bullet_line_ratio_under") is not None:
            assert evaluation.structure.details["bullet_ratio"] < invariants["bullet_line_ratio_under"]

        if invariants.get("zero_unsupplied_citations"):
            assert evaluation.integrity.details["citation_score"] == 30.0

        if invariants.get("has_threats_to_validity"):
            disc_sec = next((s for s in paper.sections if "discuss" in s.id.lower()), None)
            assert disc_sec is not None
            assert "validity" in disc_sec.content.lower()


def test_academic_quality_not_evaluated_by_word_count_alone() -> None:
    """Verify that high word count alone does NOT pass when depth, integrity, or structure are deficient."""
    case = MANIFEST["cases"][0]
    brief = ResearchBrief(
        project=ProjectContext.model_validate(case["project"]),
        source_draft=case["source_draft"],
        references=tuple(ReferenceInput.model_validate(r) for r in case["references"]),
        preferences=PaperPreferences.model_validate(case["preferences"]),
    )

    # 1. Deficient Depth: 5,000 words composed of repetitive empty platitudes
    repetitive_paras = [
        "In today's fast-paced world, it goes without saying that research is very important for everyone. "
        "Needless to say, at the end of the day, first and foremost, we must remember that computers are everywhere. "
        "As we all know, things are changing quickly throughout human history."
    ] * 60
    platitude_paper = PaperDraft(
        schema_version=1,
        title="Repetitive Study",
        abstract="Empty abstract.",
        keywords=["k1", "k2"],
        sections=[
            PaperSection(
                id="introduction",
                heading="Introduction",
                content="\n\n".join(repetitive_paras),
                state="draft",
            )
        ],
        references=[],
        review_warnings=[],
    )
    depth_res = evaluate_depth(platitude_paper, brief)
    assert depth_res.passed is False
    assert depth_res.score < 50.0
    assert any("platitudes" in d for d in depth_res.deficiencies)

    # 2. Deficient Integrity: 5,000 words with hallucinated numbers and invented citations
    hallucinated_paper = PaperDraft(
        schema_version=1,
        title="Hallucinated Study",
        abstract="Abstract.",
        keywords=["k1"],
        sections=[
            PaperSection(
                id="results",
                heading="Results",
                content=(
                    "Our model achieved a remarkable 99.8% precision and 97.4% F1-score across 15,000 unverified test instances. "
                    "These state-of-the-art results significantly outperform baseline models [ref_unsupplied_invented_999]."
                ),
                state="draft",
            )
        ],
        references=[],
        review_warnings=[],
    )
    integrity_res = evaluate_integrity(hallucinated_paper, brief)
    assert integrity_res.passed is False
    assert integrity_res.score < 50.0
    assert any("unsupported" in d.lower() for d in integrity_res.deficiencies)
    assert any("invented" in d.lower() for d in integrity_res.deficiencies)

    # 3. Deficient Structure: 5,000 words written exclusively as bullet list (outline style)
    bullet_lines = [f"- Bullet point item number {i}: discussing various operational features." for i in range(1, 200)]
    bullet_paper = PaperDraft(
        schema_version=1,
        title="Bullet Paper",
        abstract="Abstract.",
        keywords=["k1"],
        sections=[
            PaperSection(
                id="introduction",
                heading="Introduction",
                content="\n".join(bullet_lines),
                state="draft",
            )
        ],
        references=[],
        review_warnings=[],
    )
    structure_res = evaluate_structure(bullet_paper, brief)
    assert structure_res.passed is False
    assert structure_res.details["bullet_ratio"] > 0.80
    assert any("Excessive bullet points" in d for d in structure_res.deficiencies)
