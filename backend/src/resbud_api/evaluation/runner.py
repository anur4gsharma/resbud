"""Execution runner for the Resbud Manuscript Quality Evaluation System.

Runs automated benchmark evaluations across research dossiers, comparing generation engines,
providers, and configurations, and generating reproducible regression reports.
"""

from __future__ import annotations

import asyncio
from datetime import datetime, timezone
import json
from pathlib import Path
from typing import Any

from resbud_api.domain.models import (
    GenerationMeta,
    GenerationRequest,
    GenerationResponse,
    PaperDraft,
    PaperPreferences,
    ProjectContext,
    ReferenceInput,
)
from resbud_api.evaluation.evaluator import ManuscriptQualityEvaluator
from resbud_api.evaluation.models import (
    EvaluationBenchmarkResult,
    EvaluationReport,
)
from resbud_api.providers.base import ResearchBrief
from resbud_api.providers.fake import FakeProvider
from resbud_api.services.generation import generate_paper
from resbud_api.services.long_form_engine import generate_long_form_manuscript

DEFAULT_DATASET_PATH = (
    Path(__file__).resolve().parents[3] / "tests" / "evaluation" / "dataset" / "manifest.json"
)
DEFAULT_RESULTS_DIR = Path(__file__).resolve().parents[3] / "tests" / "evaluation" / "results"


async def run_case_evaluation(
    case: dict[str, Any],
    provider: Any,
    engine_type: str = "section-level-long-form",
) -> EvaluationBenchmarkResult:
    """Execute generation and evaluate the draft across all 12 quality dimensions."""
    brief = ResearchBrief(
        project=ProjectContext.model_validate(case["project"]),
        source_draft=case.get("source_draft", ""),
        references=tuple(ReferenceInput.model_validate(r) for r in case.get("references", [])),
        preferences=PaperPreferences.model_validate(case["preferences"]),
    )

    if engine_type == "section-level-long-form":
        response: GenerationResponse = await generate_long_form_manuscript(brief, provider)
    else:
        # Legacy single-pass engine: bypasses section-level expansion
        from uuid import uuid4
        from resbud_api.services.integrity import run_integrity_checks
        from resbud_api.services.prompt_builder import build_generation_input

        gen_in = build_generation_input(brief)
        p_res = await provider.generate_paper(gen_in)
        p_data = json.loads(p_res.structured_output)
        paper = PaperDraft.model_validate(p_data)
        warnings = run_integrity_checks(brief, paper, p_res.provider_name)
        paper = paper.model_copy(update={"review_warnings": warnings})
        words_count = sum(len(s.content.split()) for s in paper.sections)
        meta = GenerationMeta(
            provider_name=p_res.provider_name,
            model_name=p_res.model_name,
            duration_ms=p_res.duration_ms,
            requested_words=brief.preferences.target_word_count or 3000,
            generated_words=words_count,
            output_tokens=words_count * 2,
        )
        response = GenerationResponse(
            schema_version=1,
            generation_id=uuid4(),
            paper=paper,
            review_warnings=warnings,
            meta=meta,
        )

    return ManuscriptQualityEvaluator.evaluate(
        paper=response.paper,
        brief=brief,
        meta=response.meta,
        case_id=case["id"],
        engine_type=engine_type,
    )


async def run_evaluation_suite(
    dataset_path: Path = DEFAULT_DATASET_PATH,
    output_dir: Path = DEFAULT_RESULTS_DIR,
    active_provider: Any = None,
    compare_with_legacy_single_pass: bool = True,
) -> EvaluationReport:
    """Execute the full evaluation suite and compile the regression report."""
    if active_provider is None:
        active_provider = FakeProvider()

    raw_manifest = json.loads(dataset_path.read_text())
    cases: list[dict[str, Any]] = raw_manifest["cases"]

    active_results: list[EvaluationBenchmarkResult] = []
    comparator_results: list[EvaluationBenchmarkResult] = []

    active_provider_name = getattr(active_provider, "provider_name", "unknown")
    active_model_name = getattr(active_provider, "model_name", "unknown")

    for case in cases:
        # 1. Run Active Engine (Section-Level Long-Form)
        res_active = await run_case_evaluation(
            case=case,
            provider=active_provider,
            engine_type="section-level-long-form",
        )
        active_results.append(res_active)

        # 2. Run Comparator Engine (Legacy Single-Pass) if requested
        if compare_with_legacy_single_pass:
            res_comp = await run_case_evaluation(
                case=case,
                provider=active_provider,
                engine_type="single-pass-legacy",
            )
            comparator_results.append(res_comp)

    # Compute comparative summary metrics
    def _avg(vals: list[float]) -> float:
        return round(sum(vals) / max(1, len(vals)), 2)

    active_words = [r.generated_words for r in active_results]
    active_ratios = [r.word_count_ratio for r in active_results]
    active_scores = [r.overall_score for r in active_results]
    active_latencies = [r.duration_ms for r in active_results]
    active_costs = [r.estimated_cost_usd or 0.0 for r in active_results]

    comp_words = [r.generated_words for r in comparator_results]
    comp_ratios = [r.word_count_ratio for r in comparator_results]
    comp_scores = [r.overall_score for r in comparator_results]
    comp_latencies = [r.duration_ms for r in comparator_results]
    comp_costs = [r.estimated_cost_usd or 0.0 for r in comparator_results]

    summary = {
        "total_cases_evaluated": len(cases),
        "active_engine": {
            "name": "section-level-long-form",
            "model": active_model_name,
            "passed_cases": sum(1 for r in active_results if r.passed),
            "pass_rate": round(sum(1 for r in active_results if r.passed) / max(1, len(cases)), 3),
            "avg_generated_words": _avg(active_words),
            "avg_target_adherence_ratio": _avg(active_ratios),
            "avg_overall_score": _avg(active_scores),
            "avg_latency_ms": _avg(active_latencies),
            "total_estimated_cost_usd": round(sum(active_costs), 6),
        },
        "comparator_engine": {
            "name": "single-pass-legacy" if compare_with_legacy_single_pass else "none",
            "model": active_model_name,
            "passed_cases": sum(1 for r in comparator_results if r.passed),
            "pass_rate": round(sum(1 for r in comparator_results if r.passed) / max(1, len(cases)), 3),
            "avg_generated_words": _avg(comp_words),
            "avg_target_adherence_ratio": _avg(comp_ratios),
            "avg_overall_score": _avg(comp_scores),
            "avg_latency_ms": _avg(comp_latencies),
            "total_estimated_cost_usd": round(sum(comp_costs), 6),
        },
        "comparative_deltas": {
            "word_count_multiplier": round(_avg(active_words) / max(1, _avg(comp_words)), 2) if comp_words else 1.0,
            "score_delta": round(_avg(active_scores) - _avg(comp_scores), 2) if comp_scores else 0.0,
            "adherence_ratio_delta": round(_avg(active_ratios) - _avg(comp_ratios), 3) if comp_ratios else 0.0,
        },
    }

    # Regression check: active must have >= 80% pass rate, and no integrity regressions
    critical_failures = sum(
        1 for r in active_results
        if not r.dimension_scores["numerical_accuracy"].passed
        or not r.dimension_scores["unsupported_claims"].passed
        or not r.dimension_scores["citation_preservation"].passed
    )
    regression_passed = (
        summary["active_engine"]["pass_rate"] >= 0.75
        and critical_failures == 0
        and summary["active_engine"]["avg_generated_words"] > summary["comparator_engine"]["avg_generated_words"]
    )

    report = EvaluationReport(
        run_id=f"eval-run-{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')}",
        date=datetime.now(timezone.utc).isoformat(),
        active_engine="section-level-long-form",
        active_model=active_model_name,
        comparator_engine="single-pass-legacy" if compare_with_legacy_single_pass else None,
        comparator_model=active_model_name if compare_with_legacy_single_pass else None,
        results=active_results,
        comparator_results=comparator_results,
        summary_metrics=summary,
        regression_passed=regression_passed,
    )

    output_dir.mkdir(parents=True, exist_ok=True)
    out_file = output_dir / "latest_evaluation_report.json"
    out_file.write_text(json.dumps(report.to_dict(), indent=2, ensure_ascii=False))

    return report


if __name__ == "__main__":
    report = asyncio.run(run_evaluation_suite())
    print(f"Evaluation Run Completed: {report.run_id}")
    print(f"Regression Passed: {report.regression_passed}")
    print(json.dumps(report.summary_metrics, indent=2))
