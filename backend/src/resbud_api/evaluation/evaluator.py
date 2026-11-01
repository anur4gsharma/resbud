"""Core 12-Dimension Manuscript Quality Evaluator.

This module executes automated, deterministic, and structured evaluation across:
1. Research fact preservation
2. Citation and reference preservation
3. Section completeness
4. Requested word-count adherence
5. Methodological detail
6. Technical explanation depth
7. Argument coherence
8. Consistency across sections
9. Repetition and filler
10. Unsupported factual claims
11. Numerical accuracy
12. Overall manuscript readability

SCIENTIFIC VERIFICATION DISCLAIMER:
Automated evaluation scores are structural, factual, and linguistic heuristics.
They must NEVER be represented as objective scientific verification or proof of empirical truth.
"""

from __future__ import annotations

from datetime import datetime, timezone
import json
import re
from typing import Any

from resbud_api.domain.models import GenerationMeta, PaperDraft, PaperSection
from resbud_api.evaluation.models import (
    DimensionScore,
    EvaluationBenchmarkResult,
    EvaluationDimension,
    PROVIDER_PRICING,
)
from resbud_api.providers.base import ResearchBrief

_NUMBER_PATTERN = re.compile(r"\b\d+(?:[.,]\d+)*%?\b")
_STRUCTURAL_NUMBERS = {str(i) for i in range(1, 20)}

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
    "in this day and age",
]

_TECHNICAL_LEXICON = {
    "ablation",
    "algorithm",
    "analytical",
    "architecture",
    "asymptotic",
    "baseline",
    "benchmark",
    "coherence",
    "complexity",
    "contingency",
    "convergence",
    "correlation",
    "decomposition",
    "distribution",
    "empirical",
    "entropy",
    "equilibrium",
    "equivariance",
    "evaluation",
    "formulation",
    "grounding",
    "heuristic",
    "hypothesis",
    "inductive",
    "inference",
    "invariant",
    "latency",
    "lipschitz",
    "manifold",
    "mcnemar",
    "metric",
    "monotonic",
    "optimization",
    "parameter",
    "parametric",
    "precision",
    "probabilistic",
    "recall",
    "regularization",
    "reproducibility",
    "residual",
    "robustness",
    "significance",
    "statistical",
    "stochastic",
    "throughput",
    "topology",
    "validation",
    "variance",
}

_STOP_WORDS = {
    "a", "an", "the", "and", "or", "in", "on", "at", "to", "for", "with", "by", "from",
    "is", "are", "was", "were", "be", "been", "being", "have", "has", "had", "do", "does",
    "did", "of", "that", "this", "these", "those", "it", "its", "we", "our", "us", "they",
    "their", "them", "which", "who", "whom", "what", "where", "when", "why", "how", "as",
}


def _count_syllables(word: str) -> int:
    """Heuristic syllable counter for Flesch-Kincaid readability scoring."""
    word = word.lower().strip(".,;:()[]\"'!?`")
    if not word:
        return 0
    if len(word) <= 3:
        return 1
    # Count vowel groups
    count = len(re.findall(r"[aeiouy]+", word))
    # Discard silent 'e' at end
    if word.endswith("e") and not word.endswith("le") and count > 1:
        count -= 1
    return max(1, count)


def _compute_readability(text: str) -> tuple[float, float, float]:
    """Compute (Flesch-Kincaid Grade Level, Flesch Reading Ease, Average Sentence Length)."""
    # Clean text
    clean_lines = [
        line.strip()
        for line in text.splitlines()
        if line.strip() and not line.strip().startswith(("#", "|", "---", "```"))
    ]
    clean_text = " ".join(clean_lines)

    sentences = [s.strip() for s in re.split(r"[.!?]+", clean_text) if s.strip()]
    words = [w.strip(".,;:()[]\"'!?`") for w in clean_text.split() if w.strip(".,;:()[]\"'!?`")]

    if not sentences or not words:
        return 12.0, 50.0, 20.0

    total_words = len(words)
    total_sentences = len(sentences)
    total_syllables = sum(_count_syllables(w) for w in words)

    asl = total_words / max(1, total_sentences)
    asw = total_syllables / max(1, total_words)

    # Standard Flesch-Kincaid formulas
    fkgl = 0.39 * asl + 11.8 * asw - 15.59
    fre = 206.835 - (1.015 * asl) - (84.6 * asw)

    return round(fkgl, 2), round(fre, 2), round(asl, 2)


def _estimate_cost_usd(model_name: str, input_tokens: int | None, output_tokens: int | None) -> float:
    """Calculate estimated dollar cost from model token usage."""
    if not input_tokens and not output_tokens:
        return 0.0
    rates = PROVIDER_PRICING.get(model_name, {"input_per_m": 0.10, "output_per_m": 0.40})
    inp_cost = ((input_tokens or 0) / 1_000_000) * rates["input_per_m"]
    out_cost = ((output_tokens or 0) / 1_000_000) * rates["output_per_m"]
    return round(inp_cost + out_cost, 6)


class ManuscriptQualityEvaluator:
    """Automated evaluation suite assessing 12 quality dimensions."""

    @classmethod
    def evaluate(
        cls,
        paper: PaperDraft,
        brief: ResearchBrief,
        meta: GenerationMeta | None = None,
        case_id: str = "custom_case",
        engine_type: str = "section-level-long-form",
    ) -> EvaluationBenchmarkResult:
        """Run all 12 evaluation dimensions and return a structured benchmark result."""
        scores: dict[str, DimensionScore] = {}

        # 1. Fact preservation
        scores[EvaluationDimension.FACT_PRESERVATION] = cls._eval_fact_preservation(paper, brief)

        # 2. Citation preservation
        scores[EvaluationDimension.CITATION_PRESERVATION] = cls._eval_citation_preservation(paper, brief)

        # 3. Section completeness
        scores[EvaluationDimension.SECTION_COMPLETENESS] = cls._eval_section_completeness(paper, brief)

        # 4. Word-count adherence
        scores[EvaluationDimension.WORD_COUNT_ADHERENCE] = cls._eval_word_count_adherence(paper, brief, meta)

        # 5. Methodological detail
        scores[EvaluationDimension.METHODOLOGICAL_DETAIL] = cls._eval_methodological_detail(paper, brief)

        # 6. Technical explanation depth
        scores[EvaluationDimension.TECHNICAL_DEPTH] = cls._eval_technical_depth(paper, brief)

        # 7. Argument coherence
        scores[EvaluationDimension.ARGUMENT_COHERENCE] = cls._eval_argument_coherence(paper, brief)

        # 8. Section consistency
        scores[EvaluationDimension.SECTION_CONSISTENCY] = cls._eval_section_consistency(paper, brief)

        # 9. Repetition and filler
        scores[EvaluationDimension.REPETITION_AND_FILLER] = cls._eval_repetition_and_filler(paper, brief)

        # 10. Unsupported claims
        scores[EvaluationDimension.UNSUPPORTED_CLAIMS] = cls._eval_unsupported_claims(paper, brief)

        # 11. Numerical accuracy
        scores[EvaluationDimension.NUMERICAL_ACCURACY] = cls._eval_numerical_accuracy(paper, brief)

        # 12. Overall readability
        scores[EvaluationDimension.OVERALL_READABILITY] = cls._eval_readability(paper, brief)

        # Overall weighted score
        total_weight = sum(s.weight for s in scores.values())
        weighted_sum = sum(s.score * s.weight for s in scores.values())
        overall_score = round(weighted_sum / total_weight, 2)

        # Critical integrity dimensions must pass
        critical_passed = (
            scores[EvaluationDimension.NUMERICAL_ACCURACY].passed
            and scores[EvaluationDimension.UNSUPPORTED_CLAIMS].passed
            and scores[EvaluationDimension.CITATION_PRESERVATION].passed
        )
        passed = overall_score >= 75.0 and critical_passed and all(s.score >= 50.0 for s in scores.values())

        actual_words = sum(len(s.content.split()) for s in paper.sections)
        target_words = (
            meta.requested_words
            if meta and meta.requested_words
            else (brief.preferences.target_word_count or 3000)
        )
        ratio = actual_words / max(1, target_words)

        provider_name = meta.provider_name if meta else "unknown"
        model_name = meta.model_name if meta else "unknown"
        duration_ms = meta.duration_ms if meta else 0
        input_tokens = meta.input_tokens if meta else None
        output_tokens = meta.output_tokens if meta else None
        cost_usd = _estimate_cost_usd(model_name, input_tokens, output_tokens)

        warnings_list = [w.code for w in paper.review_warnings]

        return EvaluationBenchmarkResult(
            case_id=case_id,
            paper_title=paper.title,
            engine_type=engine_type,
            provider_name=provider_name,
            model_name=model_name,
            timestamp=datetime.now(timezone.utc).isoformat(),
            requested_words=target_words,
            generated_words=actual_words,
            word_count_ratio=ratio,
            duration_ms=duration_ms,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            estimated_cost_usd=cost_usd,
            overall_score=overall_score,
            passed=passed,
            dimension_scores=scores,
            review_warnings=warnings_list,
        )

    # --------------------------------------------------------------------------
    # Individual Dimension Evaluators
    # --------------------------------------------------------------------------

    @classmethod
    def _eval_fact_preservation(cls, paper: PaperDraft, brief: ResearchBrief) -> DimensionScore:
        """Dimension 1: Evaluate preservation of researcher-supplied facts and propositions."""
        deficiencies = []
        strengths = []
        combined_text = " ".join(s.content for s in paper.sections).lower()

        # Extract key factual concepts from project objectives and contributions
        target_concepts = []
        for obj in brief.project.objectives:
            target_concepts.extend([w.lower().strip(".,;:()") for w in obj.split() if len(w) > 4 and w.lower() not in _STOP_WORDS])
        if brief.project.claimed_contribution:
            target_concepts.extend([w.lower().strip(".,;:()") for w in brief.project.claimed_contribution.split() if len(w) > 4 and w.lower() not in _STOP_WORDS])

        unique_concepts = list(set(target_concepts))
        if not unique_concepts:
            return DimensionScore(
                dimension=EvaluationDimension.FACT_PRESERVATION,
                score=100.0,
                passed=True,
                weight=1.2,
                details={"recalled_concepts_ratio": 1.0},
                strengths=["Source factual context preserved."],
            )

        recalled = [c for c in unique_concepts if c in combined_text]
        recall_ratio = len(recalled) / len(unique_concepts)
        score = min(100.0, max(0.0, recall_ratio * 100.0))

        if recall_ratio >= 0.70:
            strengths.append(f"High fact preservation: {len(recalled)}/{len(unique_concepts)} key concepts retained.")
        else:
            deficiencies.append(f"Low fact preservation: only {len(recalled)}/{len(unique_concepts)} key concepts recalled.")

        return DimensionScore(
            dimension=EvaluationDimension.FACT_PRESERVATION,
            score=round(score, 2),
            passed=score >= 70.0,
            weight=1.2,
            details={"recalled_count": len(recalled), "total_concepts": len(unique_concepts), "ratio": round(recall_ratio, 3)},
            deficiencies=deficiencies,
            strengths=strengths,
        )

    @classmethod
    def _eval_citation_preservation(cls, paper: PaperDraft, brief: ResearchBrief) -> DimensionScore:
        """Dimension 2: Evaluate reference preservation and absence of fabricated citations."""
        deficiencies = []
        strengths = []
        supplied_ids = {r.id for r in brief.references}
        paper_ref_ids = {r.id for r in paper.references}
        combined_content = " ".join(s.content for s in paper.sections)

        # Check references list preservation
        preserved_refs = supplied_ids & paper_ref_ids
        unpreserved = supplied_ids - paper_ref_ids

        # Check bracketed citations in text [ref_X]
        found_markers = set(re.findall(r"\[(ref_[a-zA-Z0-9_\-]+)\]", combined_content))
        invented_markers = found_markers - supplied_ids

        score = 100.0
        if unpreserved:
            penalty = (len(unpreserved) / max(1, len(supplied_ids))) * 30.0
            score -= penalty
            deficiencies.append(f"Supplied references missing from paper: {', '.join(unpreserved)}")

        if invented_markers:
            score -= min(60.0, len(invented_markers) * 30.0)
            deficiencies.append(f"Fabricated or unsupplied citation markers found in text: {', '.join(invented_markers)}")
        elif supplied_ids:
            strengths.append("Zero fabricated or unsupplied citations introduced.")

        if supplied_ids and preserved_refs == supplied_ids:
            strengths.append(f"All {len(supplied_ids)} supplied references preserved.")

        passed = score >= 75.0 and len(invented_markers) == 0
        return DimensionScore(
            dimension=EvaluationDimension.CITATION_PRESERVATION,
            score=round(max(0.0, score), 2),
            passed=passed,
            weight=1.2,
            details={"supplied": len(supplied_ids), "preserved": len(preserved_refs), "invented": len(invented_markers)},
            deficiencies=deficiencies,
            strengths=strengths,
        )

    @classmethod
    def _eval_section_completeness(cls, paper: PaperDraft, brief: ResearchBrief) -> DimensionScore:
        """Dimension 3: Evaluate section presence and multi-paragraph completeness."""
        deficiencies = []
        strengths = []
        desired = brief.preferences.desired_sections or [s.id for s in paper.sections]
        paper_sections_map = {s.id: s for s in paper.sections}

        missing = [sid for sid in desired if sid not in paper_sections_map]
        empty = [sid for sid, sec in paper_sections_map.items() if not sec.content.strip()]
        shallow = [
            sid for sid, sec in paper_sections_map.items()
            if len(sec.content.split()) < 80 and sid not in {"references", "abstract"}
        ]

        score = 100.0
        if missing:
            score -= min(50.0, len(missing) * 20.0)
            deficiencies.append(f"Required sections missing: {', '.join(missing)}")
        if empty:
            score -= min(40.0, len(empty) * 20.0)
            deficiencies.append(f"Sections with empty content: {', '.join(empty)}")
        if shallow:
            score -= min(20.0, len(shallow) * 10.0)
            deficiencies.append(f"Sections under-developed (< 80 words): {', '.join(shallow)}")

        if not missing and not empty and not shallow:
            strengths.append(f"All {len(paper.sections)} sections fully present with substantive multi-paragraph content.")

        return DimensionScore(
            dimension=EvaluationDimension.SECTION_COMPLETENESS,
            score=round(max(0.0, score), 2),
            passed=score >= 70.0 and not missing and not empty,
            weight=1.0,
            details={"total_sections": len(paper.sections), "missing": missing, "shallow": shallow},
            deficiencies=deficiencies,
            strengths=strengths,
        )

    @classmethod
    def _eval_word_count_adherence(
        cls, paper: PaperDraft, brief: ResearchBrief, meta: GenerationMeta | None
    ) -> DimensionScore:
        """Dimension 4: Compare actual generated words against requested target budget."""
        deficiencies = []
        strengths = []
        actual_words = sum(len(s.content.split()) for s in paper.sections)
        target_words = (
            meta.requested_words
            if meta and meta.requested_words
            else (brief.preferences.target_word_count or 3000)
        )

        ratio = actual_words / max(1, target_words)
        is_constrained = meta and meta.completion_status == "evidence_constrained"

        if 0.80 <= ratio <= 1.25:
            score = 100.0
            strengths.append(f"Optimal word-count adherence: {actual_words} words ({ratio:.1%} of {target_words} target).")
        elif 0.65 <= ratio < 0.80 or 1.25 < ratio <= 1.40:
            score = 80.0
            strengths.append(f"Acceptable length variance: {actual_words} words ({ratio:.1%} of {target_words} target).")
        elif 0.50 <= ratio < 0.65:
            score = 65.0 if is_constrained else 50.0
            deficiencies.append(f"Under-generated manuscript: {actual_words} words ({ratio:.1%} of {target_words} target).")
        else:
            score = min(50.0, max(20.0, ratio * 70.0))
            deficiencies.append(f"Significant length shortfall: {actual_words} words ({ratio:.1%} of {target_words} target).")

        return DimensionScore(
            dimension=EvaluationDimension.WORD_COUNT_ADHERENCE,
            score=round(score, 2),
            passed=score >= 60.0 or is_constrained,
            weight=1.0,
            details={"actual_words": actual_words, "target_words": target_words, "ratio": round(ratio, 3)},
            deficiencies=deficiencies,
            strengths=strengths,
        )

    @classmethod
    def _eval_methodological_detail(cls, paper: PaperDraft, brief: ResearchBrief) -> DimensionScore:
        """Dimension 5: Evaluate reproducible procedural, algorithmic, and statistical specifications."""
        deficiencies = []
        strengths = []
        meth_sec = next((s for s in paper.sections if "method" in s.id.lower() or "system" in s.id.lower()), None)

        if not meth_sec:
            # If methodology was not requested or non-experimental
            if brief.project.methodology_status == "not_applicable":
                return DimensionScore(
                    dimension=EvaluationDimension.METHODOLOGICAL_DETAIL,
                    score=100.0,
                    passed=True,
                    weight=1.0,
                    details={"status": "not_applicable"},
                    strengths=["Methodology marked not applicable for conceptual analysis."],
                )
            return DimensionScore(
                dimension=EvaluationDimension.METHODOLOGICAL_DETAIL,
                score=0.0,
                passed=False,
                weight=1.0,
                deficiencies=["Methodology section missing from paper."],
            )

        content = meth_sec.content.lower()
        has_design = any(w in content for w in ["architecture", "pipeline", "framework", "formulation", "design"])
        has_dataset = any(w in content for w in ["dataset", "sample", "corpus", "partition", "cohort", "data", "benchmark"])
        has_metrics = any(w in content for w in ["metric", "accuracy", "precision", "recall", "f1", "loss", "mcnemar", "t-test", "$", "\\chi^2"])
        has_stats = any(w in content for w in ["statistical", "significance", "p-value", "confidence", "interval", "controls", "reproducibility", "\\alpha"])

        elements_found = sum([has_design, has_dataset, has_metrics, has_stats])
        score = (elements_found / 4.0) * 100.0

        if elements_found >= 3:
            strengths.append(f"Rigorous methodological specification ({elements_found}/4 core components verified).")
        else:
            deficiencies.append(f"Methodological detail lacking ({elements_found}/4 components found).")

        return DimensionScore(
            dimension=EvaluationDimension.METHODOLOGICAL_DETAIL,
            score=round(score, 2),
            passed=score >= 70.0,
            weight=1.0,
            details={"has_design": has_design, "has_dataset": has_dataset, "has_metrics": has_metrics, "has_stats": has_stats},
            deficiencies=deficiencies,
            strengths=strengths,
        )

    @classmethod
    def _eval_technical_depth(cls, paper: PaperDraft, brief: ResearchBrief) -> DimensionScore:
        """Dimension 6: Evaluate technical domain vocabulary density and mathematical reasoning."""
        deficiencies = []
        strengths = []
        combined_text = " ".join(s.content for s in paper.sections).lower()

        found_lexicon = [t for t in _TECHNICAL_LEXICON if t in combined_text]
        has_math = bool(re.search(r"(\$|\\chi\^2|\\mathcal|\\sim|\\in|\\le|\\ge|\\mathbb|p\s*=)", combined_text))
        has_tables = "|" in combined_text

        # Scoring
        vocab_score = min(60.0, len(found_lexicon) * 3.0)
        math_score = 25.0 if has_math else 10.0
        table_score = 15.0 if has_tables else 0.0

        total_score = min(100.0, vocab_score + math_score + table_score)
        if len(found_lexicon) >= 12:
            strengths.append(f"Dense academic domain terminology ({len(found_lexicon)} concepts verified).")
        else:
            deficiencies.append(f"Sparse technical domain vocabulary ({len(found_lexicon)} concepts identified).")

        if has_math:
            strengths.append("Incorporates formal mathematical formulations and notation.")

        return DimensionScore(
            dimension=EvaluationDimension.TECHNICAL_DEPTH,
            score=round(total_score, 2),
            passed=total_score >= 65.0,
            weight=1.0,
            details={"vocab_count": len(found_lexicon), "has_math": has_math, "has_tables": has_tables},
            deficiencies=deficiencies,
            strengths=strengths,
        )

    @classmethod
    def _eval_argument_coherence(cls, paper: PaperDraft, brief: ResearchBrief) -> DimensionScore:
        """Dimension 7: Verify logical progression from problem and RQs to findings and interpretation."""
        deficiencies = []
        strengths = []
        coherence_pts = 0.0

        intro_sec = next((s for s in paper.sections if "intro" in s.id.lower()), None)
        disc_sec = next((s for s in paper.sections if "discuss" in s.id.lower()), None)
        conc_sec = next((s for s in paper.sections if "conclus" in s.id.lower()), None)

        if intro_sec:
            content = intro_sec.content.lower()
            has_rq = bool(re.search(r"\b(rq\d+|research question|research questions)\b", content))
            has_contributions = bool(re.search(r"\b(contribution|contributions|we propose|this work contributes)\b", content))
            has_roadmap = bool(re.search(r"\b(remainder of this paper|paper is (organized|structured) as follows)\b", content))
            if has_rq:
                coherence_pts += 25.0
                strengths.append("Introduction establishes explicit Research Questions.")
            else:
                deficiencies.append("Introduction missing explicit Research Questions.")
            if has_contributions:
                coherence_pts += 20.0
            if has_roadmap:
                coherence_pts += 25.0
                strengths.append("Formal academic roadmap structures subsequent argumentation.")
            else:
                deficiencies.append("Introduction lacks a paper roadmap paragraph.")

        if disc_sec:
            content = disc_sec.content.lower()
            interprets_rq = bool(re.search(r"\b(rq\d+|research question|findings|results demonstrate|hypotheses)\b", content))
            has_validity = bool(re.search(r"\b(threats? to validity|internal validity|external validity|limitations?)\b", content))
            if interprets_rq:
                coherence_pts += 15.0
            if has_validity:
                coherence_pts += 15.0
                strengths.append("Discussion systematically addresses threats to validity.")

        return DimensionScore(
            dimension=EvaluationDimension.ARGUMENT_COHERENCE,
            score=round(min(100.0, coherence_pts), 2),
            passed=coherence_pts >= 65.0,
            weight=1.0,
            details={"coherence_points": coherence_pts},
            deficiencies=deficiencies,
            strengths=strengths,
        )

    @classmethod
    def _eval_section_consistency(cls, paper: PaperDraft, brief: ResearchBrief) -> DimensionScore:
        """Dimension 8: Ensure terminological and numerical consistency across all sections."""
        deficiencies = []
        strengths = []
        score = 100.0

        # Numerical consistency check between Results and other sections
        results_sec = next((s for s in paper.sections if "result" in s.id.lower()), None)
        if results_sec:
            res_numbers = set(re.findall(r"\b\d+([.,]\d+)?%\b", results_sec.content))
            disc_sec = next((s for s in paper.sections if "discuss" in s.id.lower()), None)
            if disc_sec:
                disc_numbers = set(re.findall(r"\b\d+([.,]\d+)?%\b", disc_sec.content))
                # Any percentage in discussion should match or be a subset of results
                discrepant = disc_numbers - res_numbers
                if discrepant:
                    # Minor check: discussion should not introduce new benchmark percentages
                    score -= min(25.0, len(discrepant) * 10.0)
                    deficiencies.append(f"Discussion introduces metric percentages absent from Results: {', '.join(discrepant)}")

        if score >= 90.0:
            strengths.append("Consistent terminology and cross-section metric harmony maintained.")

        return DimensionScore(
            dimension=EvaluationDimension.SECTION_CONSISTENCY,
            score=round(max(0.0, score), 2),
            passed=score >= 70.0,
            weight=1.0,
            details={"consistency_score": score},
            deficiencies=deficiencies,
            strengths=strengths,
        )

    @classmethod
    def _eval_repetition_and_filler(cls, paper: PaperDraft, brief: ResearchBrief) -> DimensionScore:
        """Dimension 9: Detect low lexical diversity, repeated phrasing, and conversational platitudes."""
        deficiencies = []
        strengths = []
        combined_text = " ".join(s.content for s in paper.sections).lower()

        # Type-Token Ratio
        tokens = [w.strip(".,;:()[]\"'!?`") for w in combined_text.split() if w.strip(".,;:()[]\"'!?`")]
        total_tokens = len(tokens)
        ttr = len(set(tokens)) / max(1, total_tokens)

        # Document-length adjusted threshold (Herdan's law)
        threshold = 0.12 if total_tokens >= 3500 else (0.18 if total_tokens >= 1500 else 0.28)

        score = 100.0
        if ttr < threshold:
            score -= 30.0
            deficiencies.append(f"Low lexical diversity (TTR {ttr:.2f} < {threshold:.2f} indicates boilerplate repetition).")
        else:
            strengths.append(f"High lexical diversity (TTR {ttr:.2f}).")

        # Conversational platitudes check
        platitudes = [p for p in _FILLER_PHRASES if p in combined_text]
        if platitudes:
            score -= min(40.0, len(platitudes) * 15.0)
            deficiencies.append(f"Conversational platitudes detected: {', '.join(platitudes)}")
        else:
            strengths.append("Zero empty conversational platitudes or throat-clearing cliches.")

        return DimensionScore(
            dimension=EvaluationDimension.REPETITION_AND_FILLER,
            score=round(max(0.0, score), 2),
            passed=score >= 70.0,
            weight=1.0,
            details={"ttr": round(ttr, 3), "platitudes_count": len(platitudes), "total_tokens": total_tokens},
            deficiencies=deficiencies,
            strengths=strengths,
        )

    @classmethod
    def _eval_unsupported_claims(cls, paper: PaperDraft, brief: ResearchBrief) -> DimensionScore:
        """Dimension 10: Strict verification against hallucinated outcomes and missing evidence disclosure."""
        deficiencies = []
        strengths = []
        score = 100.0

        is_results_uncollected = brief.project.results_status in {"not_collected", "not_available", "unknown"} and not (
            brief.project.results and brief.project.results.strip()
        )
        results_sec = next((s for s in paper.sections if "result" in s.id.lower()), None)

        if is_results_uncollected and results_sec:
            has_disclosure = "[Note:" in results_sec.content or "not conducted" in results_sec.content.lower()
            if results_sec.state == "needs_input" and has_disclosure:
                strengths.append("Properly declared unconducted empirical status with explicit researcher input notice.")
            else:
                score = 0.0
                deficiencies.append(
                    "Results were not collected, but the draft failed to set state 'needs_input' or omit fabricated metrics."
                )
        elif not is_results_uncollected and results_sec:
            if results_sec.state == "draft":
                strengths.append("Supplied empirical results preserved under draft state.")

        passed = score >= 75.0 and len(deficiencies) == 0
        return DimensionScore(
            dimension=EvaluationDimension.UNSUPPORTED_CLAIMS,
            score=round(score, 2),
            passed=passed,
            weight=1.2,
            details={"is_results_uncollected": is_results_uncollected},
            deficiencies=deficiencies,
            strengths=strengths,
        )

    @classmethod
    def _eval_numerical_accuracy(cls, paper: PaperDraft, brief: ResearchBrief) -> DimensionScore:
        """Dimension 11: Exact preservation of supplied numbers and zero hallucinated statistics."""
        deficiencies = []
        strengths = []

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
        supplied_numbers = set(_NUMBER_PATTERN.findall(input_text))
        paper_numbers = set(_NUMBER_PATTERN.findall(" ".join(s.content for s in paper.sections)))

        # Exclude structural numbering
        unsupported = {n for n in paper_numbers if n not in supplied_numbers and n not in _STRUCTURAL_NUMBERS}
        metric_hallucinations = [n for n in unsupported if "%" in n or "." in n]

        score = 100.0
        if metric_hallucinations:
            score = max(0.0, 100.0 - (len(metric_hallucinations) * 35.0))
            deficiencies.append(f"Fabricated metric/statistical values not present in source context: {', '.join(sorted(metric_hallucinations)[:5])}")
        elif unsupported:
            score = max(50.0, 100.0 - (len(unsupported) * 10.0))
            deficiencies.append(f"Unverified integer counts in draft: {', '.join(sorted(unsupported)[:5])}")
        else:
            strengths.append("Strict numerical fidelity: 100% of reported statistics grounded in supplied evidence.")

        passed = score >= 75.0 and len(metric_hallucinations) == 0
        return DimensionScore(
            dimension=EvaluationDimension.NUMERICAL_ACCURACY,
            score=round(score, 2),
            passed=passed,
            weight=1.3,
            details={"supplied_count": len(supplied_numbers), "unsupported_metrics_count": len(metric_hallucinations)},
            deficiencies=deficiencies,
            strengths=strengths,
        )

    @classmethod
    def _eval_readability(cls, paper: PaperDraft, brief: ResearchBrief) -> DimensionScore:
        """Dimension 12: Continuous academic prose ratio (< 15% bullets) and Flesch-Kincaid grade level."""
        deficiencies = []
        strengths = []
        combined_text = "\n".join(s.content for s in paper.sections)

        # 1. Bullet line ratio
        all_lines = []
        bullet_lines = 0
        for line in combined_text.splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith(("#", "|", "---", "```")):
                continue
            all_lines.append(stripped)
            if re.match(r"^([*+-]|\d+\.)\s+", stripped):
                bullet_lines += 1

        total_lines = max(1, len(all_lines))
        bullet_ratio = bullet_lines / total_lines

        # 2. Readability indices
        fkgl, fre, asl = _compute_readability(combined_text)

        score = 100.0
        if bullet_ratio > 0.15:
            excess = bullet_ratio - 0.15
            score -= min(50.0, (excess / 0.15) * 50.0)
            deficiencies.append(f"Excessive bullet points: {bullet_ratio:.1%} of lines are bullets (must be < 15%).")
        else:
            strengths.append(f"Continuous academic prose maintained ({bullet_ratio:.1%} bullet lines, well under 15% threshold).")

        # Academic register: FKGL between 10.0 and 18.0 is optimal
        if fkgl < 9.0:
            score -= 15.0
            deficiencies.append(f"Prose register overly colloquial (FKGL {fkgl} < 9.0).")
        elif fkgl > 20.0:
            score -= 10.0
            deficiencies.append(f"Prose register overly convoluted (FKGL {fkgl} > 20.0).")
        else:
            strengths.append(f"Authoritative academic readability (FKGL {fkgl}, Avg sentence length {asl} words).")

        return DimensionScore(
            dimension=EvaluationDimension.OVERALL_READABILITY,
            score=round(max(0.0, score), 2),
            passed=score >= 70.0 and bullet_ratio <= 0.15,
            weight=1.0,
            details={"bullet_ratio": round(bullet_ratio, 3), "fkgl": fkgl, "fre": fre, "asl": asl},
            deficiencies=deficiencies,
            strengths=strengths,
        )
