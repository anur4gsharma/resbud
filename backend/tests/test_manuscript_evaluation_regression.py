"""Automated regression test suite verifying manuscript quality across 12 dimensions."""

from __future__ import annotations

import json
from pathlib import Path
import pytest

from resbud_api.evaluation.evaluator import ManuscriptQualityEvaluator
from resbud_api.evaluation.models import EvaluationDimension
from resbud_api.evaluation.runner import run_case_evaluation, run_evaluation_suite
from resbud_api.providers.fake import FakeProvider

DATASET_PATH = Path(__file__).resolve().parents[1] / "src" / "resbud_api" / ".." / ".." / "tests" / "evaluation" / "dataset" / "manifest.json"
MANIFEST = json.loads(DATASET_PATH.resolve().read_text())


def test_evaluation_dataset_manifest_validity() -> None:
    """Verify evaluation test dataset covers all 9 required varied research profiles."""
    cases = MANIFEST["cases"]
    assert len(cases) == 9

    case_ids = [c["id"] for c in cases]
    assert len(case_ids) == len(set(case_ids))

    expected_profiles = {
        "complete-empirical-research",
        "incomplete-experimental-research",
        "uncollected-quantitative-results",
        "technical-research-with-equations",
        "extensive-reference-material",
        "conflicting-source-information",
        "long-research-dossier",
        "short-project-notes",
        "explicit-simulated-data",
    }
    assert set(case_ids) == expected_profiles


@pytest.mark.anyio
async def test_twelve_evaluation_dimensions_evaluated() -> None:
    """Verify evaluator computes scores for all 12 dimensions on a representative case."""
    provider = FakeProvider()
    case = MANIFEST["cases"][0]  # complete-empirical-research

    result = await run_case_evaluation(case, provider, engine_type="section-level-long-form")
    assert result.passed is True
    assert result.overall_score >= 85.0

    # Verify all 12 dimensions are present
    assert len(result.dimension_scores) == 12
    for dim in EvaluationDimension:
        assert dim.value in result.dimension_scores
        score_obj = result.dimension_scores[dim.value]
        assert 0.0 <= score_obj.score <= 100.0

    # Verify mandatory scientific disclaimer
    assert "never be represented as objective scientific verification" in result.scientific_disclaimer


@pytest.mark.anyio
async def test_regression_benchmark_all_dataset_cases_pass() -> None:
    """Run full evaluation suite and verify 100% pass rate and zero integrity regressions."""
    report = await run_evaluation_suite(active_provider=FakeProvider())

    assert report.regression_passed is True
    assert report.summary_metrics["active_engine"]["pass_rate"] == 1.0
    assert report.summary_metrics["active_engine"]["passed_cases"] == 9
    assert report.summary_metrics["active_engine"]["avg_overall_score"] >= 90.0

    # Verify critical integrity dimensions across all cases
    for res in report.results:
        num_score = res.dimension_scores[EvaluationDimension.NUMERICAL_ACCURACY]
        assert num_score.passed is True, f"Case '{res.case_id}' failed numerical accuracy: {num_score.deficiencies}"

        claim_score = res.dimension_scores[EvaluationDimension.UNSUPPORTED_CLAIMS]
        assert claim_score.passed is True, f"Case '{res.case_id}' failed unsupported claims: {claim_score.deficiencies}"

        cite_score = res.dimension_scores[EvaluationDimension.CITATION_PRESERVATION]
        assert cite_score.passed is True, f"Case '{res.case_id}' failed citation preservation: {cite_score.deficiencies}"


@pytest.mark.anyio
async def test_section_level_engine_outperforms_legacy_single_pass() -> None:
    """Verify section-level long-form engine substantially outperforms legacy single-pass generation."""
    report = await run_evaluation_suite(active_provider=FakeProvider(), compare_with_legacy_single_pass=True)

    summary = report.summary_metrics
    active = summary["active_engine"]
    comparator = summary["comparator_engine"]
    deltas = summary["comparative_deltas"]

    # Section-level engine generates multi-thousand words meeting target budgets
    assert active["avg_generated_words"] >= 3500
    assert comparator["avg_generated_words"] <= 1200
    assert deltas["word_count_multiplier"] >= 3.0

    # Target adherence: section-level ~95%+ vs single-pass ~25%
    assert active["avg_target_adherence_ratio"] >= 0.85
    assert comparator["avg_target_adherence_ratio"] <= 0.40

    # Overall quality score: section-level is substantially higher
    assert active["avg_overall_score"] > comparator["avg_overall_score"]
    assert deltas["score_delta"] >= 15.0


@pytest.mark.anyio
async def test_conflicting_information_triggers_warning() -> None:
    """Verify case with conflicting empirical values triggers the INPUT_CONFLICT review warning."""
    case = next(c for c in MANIFEST["cases"] if c["id"] == "conflicting-source-information")
    result = await run_case_evaluation(case, FakeProvider(), engine_type="section-level-long-form")

    assert "INPUT_CONFLICT" in result.review_warnings


@pytest.mark.anyio
async def test_uncollected_results_flagged_with_needs_input() -> None:
    """Verify case with uncollected results sets needs_input state and includes disclosure."""
    case = next(c for c in MANIFEST["cases"] if c["id"] == "uncollected-quantitative-results")
    result = await run_case_evaluation(case, FakeProvider(), engine_type="section-level-long-form")

    unsupported_dim = result.dimension_scores[EvaluationDimension.UNSUPPORTED_CLAIMS]
    assert unsupported_dim.passed is True
    assert any("unconducted" in s.lower() for s in unsupported_dim.strengths)
