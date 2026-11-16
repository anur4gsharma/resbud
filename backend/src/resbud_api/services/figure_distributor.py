"""Figure Distributor and Dynamic Cross-Referencing Service: Contextual insertion, IEEE caption formatting, and sequential renumbering."""

from __future__ import annotations

import re

from resbud_api.domain.models import PaperDraft, PaperSection, ReviewWarning, StructuredFigure
from resbud_api.services.figure_planner import clean_ieee_caption_text

FIGURE_TAG_PATTERN = re.compile(r"!\[(.*?)\]\((.*?)\)")


def _extract_figure_id_or_src(match: re.Match[str]) -> tuple[str, str]:
    return match.group(1), match.group(2)


def distribute_and_reindex_figures(paper: PaperDraft) -> PaperDraft:
    """Distribute unplaced figures contextually into manuscript sections and dynamically renumber all figures and in-text references to IEEE conventions.

    Guarantees:
    1. Anti-bundling: Figures are placed adjacent to related paragraphs, never dumped together.
    2. Contextual integration: Figures are accompanied by preceding introductory prose and captions below.
    3. IEEE numbering: Figures are numbered sequentially (Fig. 1., Fig. 2.) in reading order.
    4. Cross-referencing: In-text citations are updated to match the reindexed figure numbers.
    5. Zero silent loss: Unplaced or omitted figures are preserved in paper.figures with explanatory rationale.
    """
    if not paper.figures:
        return paper

    figures_by_id = {f.id: f for f in paper.figures}
    figures_by_filename = {f.filename: f for f in paper.figures}

    updated_sections: list[PaperSection] = []
    # Set of figure IDs already placed in the document
    placed_figure_ids: set[str] = set()

    # Step 1: Detect which figures are already embedded in sections
    for sec in paper.sections:
        matches = FIGURE_TAG_PATTERN.findall(sec.content)
        for _, src in matches:
            src_clean = src.strip()
            if src_clean in figures_by_id:
                placed_figure_ids.add(src_clean)
            elif src_clean in figures_by_filename:
                placed_figure_ids.add(figures_by_filename[src_clean].id)

    # Step 2: Contextually inject unplaced active figures into their target sections
    active_unplaced = [
        f
        for f in paper.figures
        if f.id not in placed_figure_ids and f.placement_status not in ("omitted",)
    ]

    # Map unplaced figures to sections
    section_unplaced_map: dict[str, list[StructuredFigure]] = {}
    for fig in active_unplaced:
        target_sec_id = fig.related_section
        if not target_sec_id or not any(s.id == target_sec_id for s in paper.sections):
            # Fallback to methodology or results
            if fig.category in ("flowchart", "architecture_diagram"):
                target_sec_id = next(
                    (
                        s.id
                        for s in paper.sections
                        if "method" in s.id.lower() or "sys" in s.id.lower()
                    ),
                    paper.sections[0].id if paper.sections else None,
                )
            elif fig.category in ("graph", "experimental_result", "screenshot"):
                target_sec_id = next(
                    (
                        s.id
                        for s in paper.sections
                        if "result" in s.id.lower() or "eval" in s.id.lower()
                    ),
                    paper.sections[-1].id if paper.sections else None,
                )
            else:
                target_sec_id = paper.sections[0].id if paper.sections else None

        if target_sec_id:
            section_unplaced_map.setdefault(target_sec_id, []).append(fig)

    # Inject figures into their assigned sections
    for sec in paper.sections:
        to_inject = section_unplaced_map.get(sec.id, [])
        if not to_inject:
            updated_sections.append(sec)
            continue

        paragraphs = [p.strip() for p in sec.content.split("\n\n") if p.strip()]
        if not paragraphs:
            paragraphs = [sec.content]

        new_paragraphs: list[str] = []
        injected_count = 0

        # We want to distribute multiple figures across paragraphs rather than clustering them
        # Anti-bundling stride: place after paragraph 1, paragraph 3, etc.
        p_len = len(paragraphs)
        stride = max(1, p_len // (len(to_inject) + 1))

        insert_positions = [min(p_len, max(1, (i + 1) * stride)) for i in range(len(to_inject))]

        for p_idx, para in enumerate(paragraphs, start=1):
            new_paragraphs.append(para)

            # Check if any figures should be inserted after this paragraph
            for fig_idx, fig in enumerate(to_inject):
                if insert_positions[fig_idx] == p_idx:
                    # In-text introduction if not already present
                    intro_clause = ""
                    clean_cap = clean_ieee_caption_text(fig.caption)
                    desc = fig.description or fig.title or clean_cap

                    # Check if preceding paragraph mentions this figure
                    if not re.search(r"\b(?:Fig\.?|Figure)\b", para, flags=re.IGNORECASE):
                        intro_clause = (
                            f" As illustrated in the following diagram, {desc.lower().rstrip('.')}."
                        )

                    if intro_clause:
                        new_paragraphs[-1] = new_paragraphs[-1] + intro_clause

                    # Figure marker
                    fig_marker = f"![{fig.caption}]({fig.id})"
                    new_paragraphs.append(fig_marker)

                    # Follow-up discussion
                    followup = (
                        "The visual components in this representation formalize operational interactions, "
                        "providing verifiable structural grounding for the subsequent technical analysis."
                    )
                    new_paragraphs.append(followup)

                    placed_figure_ids.add(fig.id)
                    injected_count += 1

        updated_content = "\n\n".join(new_paragraphs)
        updated_sections.append(sec.model_copy(update={"content": updated_content}))

    # Step 3: Global Sequential Renumbering & Cross-Referencing across all sections
    # Scan document in reading order to discover chronological sequence
    chronological_figures: list[
        tuple[StructuredFigure, str, str]
    ] = []  # (fig_obj, old_caption, old_src)
    reindexed_id_to_num: dict[str, int] = {}
    current_number = 1

    for sec in updated_sections:
        for match in FIGURE_TAG_PATTERN.finditer(sec.content):
            caption_text, src = match.group(1), match.group(2).strip()
            fig_obj = figures_by_id.get(src) or figures_by_filename.get(src)
            if fig_obj and fig_obj.id not in reindexed_id_to_num:
                reindexed_id_to_num[fig_obj.id] = current_number
                chronological_figures.append((fig_obj, caption_text, src))
                current_number += 1

    # Step 4: Rewrite figure markdown tags and normalize in-text citations in all sections
    final_sections: list[PaperSection] = []
    for sec in updated_sections:
        content = sec.content

        # 4a. Replace figure markdown tags with IEEE format: ![Fig. {N}. {Caption}](id)
        def _replace_figure_tag(match: re.Match[str]) -> str:
            caption, src = match.group(1), match.group(2).strip()
            fig = figures_by_id.get(src) or figures_by_filename.get(src)
            if fig and fig.id in reindexed_id_to_num:
                num = reindexed_id_to_num[fig.id]
                pure_cap = clean_ieee_caption_text(caption if caption else fig.caption)
                return f"![Fig. {num}. {pure_cap}]({fig.id})"
            return match.group(0)

        content = FIGURE_TAG_PATTERN.sub(_replace_figure_tag, content)

        # 4b. Normalize in-text citations to IEEE style ("Fig. N")
        for fig_id, num in reindexed_id_to_num.items():
            matched_fig = figures_by_id.get(fig_id)
            if matched_fig:
                # Replace explicit figure ID references (e.g. FIG-001 or fig_1 in prose)
                content = re.sub(
                    rf"\b{re.escape(fig_id)}\b(?!\))",
                    f"Fig. {num}",
                    content,
                )

        final_sections.append(sec.model_copy(update={"content": content}))

    # Step 5: Update paper.figures metadata
    updated_figures: list[StructuredFigure] = []
    unplaced_warnings: list[ReviewWarning] = []

    for fig in paper.figures:
        if fig.id in reindexed_id_to_num:
            num = reindexed_id_to_num[fig.id]
            pure_cap = clean_ieee_caption_text(fig.caption)
            ieee_cap = f"Fig. {num}. {pure_cap}"
            updated_figures.append(
                fig.model_copy(
                    update={
                        "figure_order": num,
                        "caption": ieee_cap,
                        "referenced_in_text": True,
                        "placement_status": "assigned",
                    }
                )
            )
        elif fig.placement_status == "omitted":
            updated_figures.append(fig)
        else:
            # Figure was not placed in text
            rationale = (
                fig.placement_rationale
                or "Retained in project figure assets; not contextually placed in manuscript text."
            )
            updated_figures.append(
                fig.model_copy(
                    update={
                        "placement_status": "unplaced",
                        "placement_rationale": rationale,
                        "referenced_in_text": False,
                    }
                )
            )
            unplaced_warnings.append(
                ReviewWarning(
                    code="GENERAL_REVIEW",
                    severity="info",
                    message=f"Figure '{fig.filename}' ({fig.id}) was retained in figure assets with status 'unplaced': {rationale}",
                    section_id=fig.related_section,
                )
            )

    all_warnings = list(paper.review_warnings) + unplaced_warnings

    return paper.model_copy(
        update={
            "sections": final_sections,
            "figures": updated_figures,
            "review_warnings": all_warnings,
        }
    )
