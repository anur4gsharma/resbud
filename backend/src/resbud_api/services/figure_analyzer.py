"""Multimodal Figure Analysis Service: Categorization, duplicate detection, and section mapping."""

from __future__ import annotations

import hashlib
import re

from resbud_api.domain.models import (
    FigureCategory,
    StructuredFigure,
)
from resbud_api.providers.base import ResearchBrief

# Category detection keywords
CATEGORY_PATTERNS: list[tuple[FigureCategory, list[str]]] = [
    (
        "flowchart",
        [
            "flowchart",
            "workflow",
            "flow-chart",
            "pipeline",
            "sequence",
            "process_flow",
            "lifecycle",
            "state_machine",
        ],
    ),
    (
        "architecture_diagram",
        [
            "architecture",
            "framework",
            "block_diagram",
            "system_design",
            "overview_diagram",
            "module",
            "topology",
            "schematic",
            "network_diagram",
        ],
    ),
    (
        "screenshot",
        [
            "screenshot",
            "screen",
            "interface",
            "ui",
            "gui",
            "mobile_app",
            "web_app",
            "dashboard",
            "display",
        ],
    ),
    (
        "graph",
        [
            "graph",
            "plot",
            "curve",
            "distribution",
            "loss",
            "accuracy",
            "scatter",
            "histogram",
            "roc",
            "pr_curve",
            "confusion_matrix",
            "bar_chart",
        ],
    ),
    (
        "experimental_result",
        [
            "result",
            "benchmark",
            "performance",
            "comparison",
            "ablation",
            "speedup",
            "latency",
            "throughput",
            "metric",
            "empirical",
        ],
    ),
    (
        "photograph",
        [
            "photo",
            "photograph",
            "camera",
            "specimen",
            "apparatus",
            "microscopy",
            "hardware",
            "setup",
            "field",
        ],
    ),
    (
        "table_image",
        [
            "table",
            "tabular",
            "matrix",
            "summary_table",
        ],
    ),
]


def classify_figure_category(figure: StructuredFigure) -> FigureCategory:
    """Classify the figure category using filename, title, caption, and description keywords."""
    if figure.category and figure.category != "other":
        return figure.category

    combined_text = (
        f"{figure.filename} {figure.title or ''} {figure.caption} {figure.description or ''}"
    ).lower()

    for category, keywords in CATEGORY_PATTERNS:
        for kw in keywords:
            if re.search(r"\b" + re.escape(kw) + r"\b", combined_text) or kw in combined_text:
                return category

    return "other"


def infer_target_section(
    figure: StructuredFigure,
    available_sections: list[str],
) -> str | None:
    """Infer the most contextually relevant section for a figure based on its category and semantic metadata."""
    if figure.related_section and figure.related_section in available_sections:
        return figure.related_section

    combined_text = (
        f"{figure.filename} {figure.title or ''} {figure.caption} {figure.description or ''}"
    ).lower()

    # Normalize available sections
    norm_secs = {s.lower().replace("-", "_"): s for s in available_sections}

    # Find methodology / method
    method_sec = next(
        (
            orig
            for norm, orig in norm_secs.items()
            if "method" in norm or "system" in norm or "approach" in norm or "model" in norm
        ),
        None,
    )
    # Find results / experiment
    results_sec = next(
        (
            orig
            for norm, orig in norm_secs.items()
            if "result" in norm or "eval" in norm or "experiment" in norm or "benchmark" in norm
        ),
        None,
    )
    # Find discussion / limitations
    discussion_sec = next(
        (orig for norm, orig in norm_secs.items() if "disc" in norm or "analysis" in norm),
        None,
    )
    # Find introduction
    intro_sec = next((orig for norm, orig in norm_secs.items() if "intro" in norm), None)

    cat = classify_figure_category(figure)

    if cat in ("flowchart", "architecture_diagram"):
        return method_sec or intro_sec or (available_sections[0] if available_sections else None)

    if cat in ("graph", "experimental_result", "table_image"):
        return (
            results_sec
            or discussion_sec
            or method_sec
            or (available_sections[-1] if available_sections else None)
        )

    if cat == "screenshot":
        # Check if mobile app screenshot represents results/prototype or methodology
        if any(
            w in combined_text
            for w in ["app", "mobile", "interface", "prototype", "user", "client"]
        ):
            return (
                results_sec or method_sec or (available_sections[0] if available_sections else None)
            )
        return method_sec or results_sec or (available_sections[0] if available_sections else None)

    if cat == "photograph":
        return method_sec or results_sec or (available_sections[0] if available_sections else None)

    # Keyword fallback
    if any(
        w in combined_text for w in ["method", "algorithm", "architecture", "model", "pipeline"]
    ):
        return method_sec
    if any(w in combined_text for w in ["result", "accuracy", "performance", "metric", "score"]):
        return results_sec

    # Default to method or results if available
    return method_sec or results_sec or (available_sections[0] if available_sections else None)


def compute_figure_hash(figure: StructuredFigure) -> str:
    """Compute deterministic hash of figure content or key attributes for duplicate detection."""
    if figure.data_uri:
        clean = re.sub(r"^data:[^;]+;base64,", "", figure.data_uri).strip()
        return hashlib.sha256(clean.encode("utf-8")).hexdigest()
    if figure.storage_key:
        return hashlib.sha256(figure.storage_key.encode("utf-8")).hexdigest()
    # Fallback to filename + dimensions
    key = f"{figure.filename}:{figure.width}:{figure.height}:{figure.caption.strip().lower()}"
    return hashlib.sha256(key.encode("utf-8")).hexdigest()


def detect_duplicate_figures(figures: list[StructuredFigure]) -> list[StructuredFigure]:
    """Identify duplicate uploaded figures and mark duplicates as omitted."""
    seen_hashes: dict[str, str] = {}
    result: list[StructuredFigure] = []

    for fig in figures:
        fig_hash = compute_figure_hash(fig)
        if fig_hash in seen_hashes:
            dup_of = seen_hashes[fig_hash]
            result.append(
                fig.model_copy(
                    update={
                        "placement_status": "omitted",
                        "placement_rationale": f"Identified as duplicate of figure {dup_of}.",
                    }
                )
            )
        else:
            seen_hashes[fig_hash] = fig.id
            result.append(fig)

    return result


def analyze_figures(
    figures: list[StructuredFigure],
    brief: ResearchBrief | None = None,
    available_sections: list[str] | None = None,
) -> list[StructuredFigure]:
    """Analyze all uploaded figures independently, infer categories, detect duplicates, and map sections."""
    if not figures:
        return []

    sections = available_sections or (
        [s.id for s in getattr(brief.preferences, "desired_sections", [])]
        if brief and hasattr(brief, "preferences")
        else ["introduction", "methodology", "results", "discussion", "conclusion"]
    )

    # 1. Detect duplicates
    analyzed = detect_duplicate_figures(figures)

    # 2. Categorize and infer section mappings
    updated: list[StructuredFigure] = []
    for fig in analyzed:
        if fig.placement_status == "omitted":
            updated.append(fig)
            continue

        cat = classify_figure_category(fig)
        target_sec = infer_target_section(fig, sections)

        # Flag unclear or ambiguous figures
        is_ambiguous = (
            cat == "other"
            and not fig.title
            and (not fig.description or len(fig.description.strip()) < 10)
            and not fig.related_section
        )

        status = (
            "unplaced"
            if is_ambiguous
            else (fig.placement_status if fig.placement_status != "unplaced" else "suggested")
        )
        rationale = (
            "Flagged for user review: contextual purpose unclear from provided visual metadata."
            if is_ambiguous
            else (
                fig.placement_rationale
                or f"Contextually mapped to {target_sec or 'manuscript'} based on {cat} categorization."
            )
        )

        # Broad architecture diagrams or wide comparison charts default to full_width
        column_span = fig.column_span
        if cat == "architecture_diagram" and "broad" in (fig.description or "").lower():
            column_span = "full_width"

        updated.append(
            fig.model_copy(
                update={
                    "category": cat,
                    "related_section": target_sec,
                    "placement_status": status,
                    "placement_rationale": rationale,
                    "column_span": column_span,
                }
            )
        )

    return updated
