"""Domain models and data structures for the 12-dimension Manuscript Quality Evaluation System."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum
from typing import Any


class EvaluationDimension(StrEnum):
    """The 12 primary dimensions for objective manuscript quality evaluation."""

    FACT_PRESERVATION = "fact_preservation"
    CITATION_PRESERVATION = "citation_preservation"
    SECTION_COMPLETENESS = "section_completeness"
    WORD_COUNT_ADHERENCE = "word_count_adherence"
    METHODOLOGICAL_DETAIL = "methodological_detail"
    TECHNICAL_DEPTH = "technical_depth"
    ARGUMENT_COHERENCE = "argument_coherence"
    SECTION_CONSISTENCY = "section_consistency"
    REPETITION_AND_FILLER = "repetition_and_filler"
    UNSUPPORTED_CLAIMS = "unsupported_claims"
    NUMERICAL_ACCURACY = "numerical_accuracy"
    OVERALL_READABILITY = "overall_readability"


# Standard public pricing estimates (USD per 1M tokens) for cost estimation
PROVIDER_PRICING = {
    "gemini-2.5-flash": {"input_per_m": 0.075, "output_per_m": 0.30},
    "gemini-3.1-flash-lite": {"input_per_m": 0.05, "output_per_m": 0.20},
    "gpt-4o-mini": {"input_per_m": 0.15, "output_per_m": 0.60},
    "deterministic-demo": {"input_per_m": 0.0, "output_per_m": 0.0},
    "fake": {"input_per_m": 0.0, "output_per_m": 0.0},
}


@dataclass
class DimensionScore:
    """Evaluation score and diagnostic details for a single quality dimension."""

    dimension: EvaluationDimension
    score: float  # 0.0 to 100.0
    passed: bool
    weight: float = 1.0
    details: dict[str, Any] = field(default_factory=dict)
    deficiencies: list[str] = field(default_factory=list)
    strengths: list[str] = field(default_factory=list)


@dataclass
class EvaluationBenchmarkResult:
    """Benchmark outcome for a single evaluation case under a specific generation configuration."""

    case_id: str
    paper_title: str
    engine_type: str  # "section-level-long-form" | "single-pass-legacy"
    provider_name: str
    model_name: str
    timestamp: str
    requested_words: int
    generated_words: int
    word_count_ratio: float
    duration_ms: int
    input_tokens: int | None = None
    output_tokens: int | None = None
    estimated_cost_usd: float | None = None
    overall_score: float = 0.0  # 0.0 to 100.0
    passed: bool = False
    dimension_scores: dict[str, DimensionScore] = field(default_factory=dict)
    review_warnings: list[str] = field(default_factory=list)
    scientific_disclaimer: str = (
        "Automated evaluation scores are structural, factual, and linguistic heuristics. "
        "They must never be represented as objective scientific verification or proof of empirical truth."
    )

    def to_dict(self) -> dict[str, Any]:
        """Convert benchmark result to a serializable dictionary."""
        return {
            "case_id": self.case_id,
            "paper_title": self.paper_title,
            "engine_type": self.engine_type,
            "provider_name": self.provider_name,
            "model_name": self.model_name,
            "timestamp": self.timestamp,
            "requested_words": self.requested_words,
            "generated_words": self.generated_words,
            "word_count_ratio": round(self.word_count_ratio, 3),
            "duration_ms": self.duration_ms,
            "input_tokens": self.input_tokens,
            "output_tokens": self.output_tokens,
            "estimated_cost_usd": round(self.estimated_cost_usd, 6) if self.estimated_cost_usd else 0.0,
            "overall_score": round(self.overall_score, 2),
            "passed": self.passed,
            "dimension_scores": {
                k: {
                    "score": round(v.score, 2),
                    "passed": v.passed,
                    "weight": v.weight,
                    "details": v.details,
                    "deficiencies": v.deficiencies,
                    "strengths": v.strengths,
                }
                for k, v in self.dimension_scores.items()
            },
            "review_warnings": self.review_warnings,
            "scientific_disclaimer": self.scientific_disclaimer,
        }


@dataclass
class EvaluationReport:
    """Comprehensive regression and comparison report across a suite of evaluation cases."""

    run_id: str
    date: str
    active_engine: str
    active_model: str
    comparator_engine: str | None = None
    comparator_model: str | None = None
    results: list[EvaluationBenchmarkResult] = field(default_factory=list)
    comparator_results: list[EvaluationBenchmarkResult] = field(default_factory=list)
    summary_metrics: dict[str, Any] = field(default_factory=dict)
    regression_passed: bool = False
    scientific_disclaimer: str = (
        "Automated evaluation scores are structural, factual, and linguistic heuristics. "
        "They must never be represented as objective scientific verification or proof of empirical truth."
    )

    def to_dict(self) -> dict[str, Any]:
        """Convert report to serializable format."""
        return {
            "run_id": self.run_id,
            "date": self.date,
            "active_engine": self.active_engine,
            "active_model": self.active_model,
            "comparator_engine": self.comparator_engine,
            "comparator_model": self.comparator_model,
            "results": [r.to_dict() for r in self.results],
            "comparator_results": [r.to_dict() for r in self.comparator_results],
            "summary_metrics": self.summary_metrics,
            "regression_passed": self.regression_passed,
            "scientific_disclaimer": self.scientific_disclaimer,
        }
