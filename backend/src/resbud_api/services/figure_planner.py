"""Figure Placement Planner: Constructs structured figure distribution plans across manuscript sections."""

from __future__ import annotations

import re

from resbud_api.domain.models import StructuredFigure


def clean_ieee_caption_text(raw_caption: str) -> str:
    """Strip any existing 'Figure X:', 'Fig. X.', 'Fig X:' prefixes to obtain the pure descriptive caption."""
    cleaned = re.sub(
        r"^(?:Figure|Fig\.?)\s*\d+[\s.:\-–—]*",
        "",
        raw_caption.strip(),
        flags=re.IGNORECASE,
    ).strip()
    return cleaned if cleaned else raw_caption.strip()


def plan_figure_placements(
    figures: list[StructuredFigure],
    section_ids: list[str],
) -> list[StructuredFigure]:
    """Plan intelligent, distributed figure placements avoiding bundling or single-page overload.

    Invariants:
    1. Anti-bundling: Distribute figures across appropriate sections (e.g., Methodology, Results).
    2. Column span: Determine column_width vs full_width based on category and aspect ratio.
    3. Target anchors: Assign logical content anchors within target sections.
    4. Sequential order: Assign reading-order sequence numbers (1, 2, ...).
    5. IEEE caption normalization: Ensure captions follow 'Fig. {N}. {Description}'.
    """
    if not figures:
        return []

    # Filter out omitted (duplicate) figures
    active_figures = [f for f in figures if f.placement_status != "omitted"]
    omitted_figures = [f for f in figures if f.placement_status == "omitted"]

    # Normalize section IDs
    norm_secs = {s.lower().replace("-", "_"): s for s in section_ids}
    method_sec = next(
        (
            orig
            for norm, orig in norm_secs.items()
            if "method" in norm or "system" in norm or "approach" in norm
        ),
        section_ids[0] if section_ids else "methodology",
    )
    results_sec = next(
        (
            orig
            for norm, orig in norm_secs.items()
            if "result" in norm or "eval" in norm or "experiment" in norm
        ),
        section_ids[-1] if section_ids else "results",
    )

    # Distribute active figures across sections according to semantic purpose
    section_buckets: dict[str, list[StructuredFigure]] = {s: [] for s in section_ids}

    for fig in active_figures:
        target = fig.related_section
        if not target or target not in section_buckets:
            # Fallback mapping
            if fig.category in ("flowchart", "architecture_diagram"):
                target = method_sec
            elif fig.category in ("graph", "experimental_result", "screenshot"):
                target = results_sec
            else:
                target = (
                    method_sec
                    if len(section_buckets.get(method_sec, []))
                    <= len(section_buckets.get(results_sec, []))
                    else results_sec
                )

        section_buckets.setdefault(target, []).append(fig)

    # Anti-bundling balancing: If all figures ended up in one section and results_sec is empty, balance them!
    if len(active_figures) >= 3 and section_ids:
        for s_id, bucket in list(section_buckets.items()):
            if len(bucket) == len(active_figures) and len(section_ids) > 1:
                # Move experimental results or graphs or screenshots to results section
                remaining: list[StructuredFigure] = []
                for f in bucket:
                    if (
                        f.category in ("graph", "experimental_result", "screenshot")
                        and s_id != results_sec
                    ):
                        section_buckets.setdefault(results_sec, []).append(f)
                    else:
                        remaining.append(f)
                section_buckets[s_id] = remaining

    # Order figures sequentially across sections following manuscript reading order
    planned_ordered: list[StructuredFigure] = []
    current_order = 1

    for s_id in section_ids:
        figs_in_sec = section_buckets.get(s_id, [])
        for idx, fig in enumerate(figs_in_sec):
            clean_caption = clean_ieee_caption_text(fig.caption)
            ieee_caption = f"Fig. {current_order}. {clean_caption}"

            # Target anchor formulation
            if not fig.target_anchor:
                if idx == 0:
                    anchor = f"Immediately after the overview of {s_id.replace('_', ' ')}."
                elif idx == 1:
                    anchor = f"Following the detailed discussion of {fig.title or fig.category.replace('_', ' ')}."
                else:
                    anchor = f"Following the quantitative analysis in {s_id.replace('_', ' ')}."
            else:
                anchor = fig.target_anchor

            # Determine column_span
            column_span = fig.column_span
            if fig.category == "architecture_diagram" and (
                fig.width > fig.height * 1.8 or "broad" in (fig.description or "").lower()
            ):
                column_span = "full_width"
            elif fig.category in ("screenshot", "flowchart") and fig.height >= fig.width:
                column_span = "column_width"

            planned_fig = fig.model_copy(
                update={
                    "related_section": s_id,
                    "figure_order": current_order,
                    "caption": ieee_caption,
                    "target_anchor": anchor,
                    "column_span": column_span,
                    "preferred_placement": fig.preferred_placement or "after_paragraph",
                    "placement_status": "assigned",
                    "placement_rationale": (
                        fig.placement_rationale
                        or f"Contextually placed in {s_id.replace('_', ' ')} ({anchor})"
                    ),
                }
            )
            planned_ordered.append(planned_fig)
            current_order += 1

    return planned_ordered + omitted_figures
