"""IEEE Mathematical Typesetting and Equation Management Engine.

Provides:
- Detection and extraction of mathematical display blocks and inline expressions.
- Consecutive 1-based equation indexing (1), (2), (3)... across manuscript sections.
- Automatic synchronization of in-text equation cross-references (Equation (1), Eq. (1), (1), [eq-...], \ref{eq:...}).
- Support for multiline and aligned equation structures (aligned, align, gather, matrix, cases).
- Zero collision column boundary layout and stable internal equation identifiers.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field
from typing import Literal

from resbud_api.domain.models import PaperDraft, PaperSection, ReviewWarning
from resbud_api.services.math_omml import (
    clean_math_delimiters,
    validate_latex_math,
)

logger = logging.getLogger(__name__)

# Pattern detecting display math blocks with optional trailing equation numbers
# Matches $$, \[, or \begin{...} environments
DISPLAY_MATH_BLOCK_RE = re.compile(
    r"(?P<block>"
    r"(?:\$\$(?P<content_dollar>[\s\S]*?)\$\$|"
    r"\\\[(?P<content_bracket>[\s\S]*?)\\\]|"
    r"\\begin\{(?P<env>equation|align|aligned|gather|matrix|pmatrix|bmatrix|vmatrix|cases)\*?}"
    r"(?P<content_env>[\s\S]*?)"
    r"\\end\{(?P=env)\*?})"
    r")"
    r"(?:\s*(?:<!--\s*eq:\s*(?P<html_label>[a-zA-Z0-9_-]+)\s*-->|"
    r"\[eq:?\s*(?P<bracket_label>[a-zA-Z0-9_-]+)\]|"
    r"\((?:[Ee]q\.?\s*)?(?P<trailing_num>[0-9]+)\)))?",
    re.IGNORECASE,
)

# LaTeX internal label and tag patterns
LABEL_RE = re.compile(r"\\label\{([^{}]+)\}")
TAG_RE = re.compile(r"\\tag\{([^{}]+)\}")

BIG_INLINE_MATH_RE = re.compile(
    r"(?<![\$\\])\$(?![\$\s])((?:[^$\n\\]|\\.)+?)(?<![\$\s])\$(?![0-9\$])(?:\s*\((?P<num>\d+)\))?"
)


def is_big_inline_equation(latex_str: str) -> bool:
    """Check if an inline math expression contains structural relations and operators
    characteristic of a standalone display equation (e.g. definition with fraction/sum/etc)."""
    inner = clean_math_delimiters(latex_str.strip())
    return (
        any(rel in inner for rel in ("=", ":=", r"\equiv", r"\approx"))
        and len(inner) >= 15
        and any(op in inner for op in (r"\sum", r"\prod", r"\int", r"\frac", r"\sqrt"))
    )


def promote_big_inline_equations(content: str) -> str:
    """Promote standalone/definition equations delimited by single dollars into display blocks."""
    def repl(m: re.Match[str]) -> str:
        raw = m.group(0)
        inner = m.group(1).strip()
        num = m.group("num")
        if is_big_inline_equation(inner):
            if num:
                return f"\n\n$${inner}$$\n({num})\n\n"
            return f"\n\n$${inner}$$\n\n"
        return raw

    return BIG_INLINE_MATH_RE.sub(repl, content)

# In-text equation cross-reference patterns
IN_TEXT_EQ_REF_RE = re.compile(
    r"(?P<prefix>\b(?:Equations?|eqs?\.?|Equations?|EQS?\.?)\s*)?"
    r"(?:"
    r"\((?P<num>\d+)\)|"
    r"\[(?:eq[-:]\s*|eq\s+)?(?P<bracket_id>[a-zA-Z0-9_:-]+)\]|"
    r"\\(?:eq)?ref\{(?P<latex_ref>[a-zA-Z0-9_:-]+)\}"
    r")",
    re.IGNORECASE,
)

STANDALONE_PAREN_REF_RE = re.compile(
    r"\b(?P<trigger>given by|defined in|as in|from|see|using|via|in|equation|eq\.)\s+\((?P<num>\d+)\)",
    re.IGNORECASE,
)


@dataclass
class StructuredEquation:
    """Structured representation of a display mathematical equation in the manuscript."""

    id: str
    latex: str
    equation_number: int | None = None
    prior_number: int | None = None
    label: str | None = None
    section_id: str | None = None
    display_type: Literal["display", "environment", "aligned"] = "display"
    is_multiline: bool = False
    rendering_status: Literal["ok", "warning", "error"] = "ok"
    validation_warnings: list[str] = field(default_factory=list)


def clean_equation_latex(raw_latex: str) -> tuple[str, str | None, str | None]:
    """Clean raw equation LaTeX and extract internal \\label and \\tag if present.

    Returns (cleaned_latex, label, tag).
    """
    clean = clean_math_delimiters(raw_latex.strip())

    label: str | None = None
    tag: str | None = None

    lbl_match = LABEL_RE.search(clean)
    if lbl_match:
        label = lbl_match.group(1).strip()
        clean = LABEL_RE.sub("", clean).strip()

    tag_match = TAG_RE.search(clean)
    if tag_match:
        tag_val = tag_match.group(1).strip()
        # Strip outer parens if author typed \tag{(1)}
        if tag_val.startswith("(") and tag_val.endswith(")"):
            tag_val = tag_val[1:-1].strip()
        tag = tag_val
        clean = TAG_RE.sub("", clean).strip()

    return clean, label, tag


def is_multiline_equation(latex_str: str) -> bool:
    """Check if equation uses multiline structures (aligned, gather, matrix, cases, \\)."""
    return bool(
        r"\\" in latex_str
        or re.search(
            r"\\begin\{(?:align|aligned|gather|matrix|pmatrix|bmatrix|vmatrix|cases|split|multline)\*?\}",
            latex_str,
        )
    )


def extract_equations_from_section(
    section_id: str,
    content: str,
    start_index: int = 1,
) -> list[StructuredEquation]:
    """Scan section markdown content and extract all display equations with stable IDs."""
    equations: list[StructuredEquation] = []
    idx = start_index

    promoted_content = promote_big_inline_equations(content)
    for match in DISPLAY_MATH_BLOCK_RE.finditer(promoted_content):
        raw_formula = (
            match.group("content_dollar")
            or match.group("content_bracket")
            or match.group("content_env")
            or match.group("block")
        )
        env = match.group("env")
        if env:
            raw_formula = f"\\begin{{{env}}}{raw_formula}\\end{{{env}}}"

        clean_latex, extracted_label, extracted_tag = clean_equation_latex(raw_formula)
        html_label = match.group("html_label")
        bracket_label = match.group("bracket_label")
        trailing_num = match.group("trailing_num")

        # Stable equation identifier
        eq_label = extracted_label or html_label or bracket_label or extracted_tag or None
        if eq_label:
            # Strip eq: prefix if present
            if eq_label.lower().startswith("eq:"):
                eq_label = eq_label[3:]
            elif eq_label.lower().startswith("eq-"):
                eq_label = eq_label[3:]
            eq_id = f"eq-{eq_label}"
        else:
            eq_id = f"eq-{section_id}-{idx}"

        is_multi = is_multiline_equation(clean_latex)
        display_type: Literal["display", "environment", "aligned"] = (
            "aligned" if is_multi else ("environment" if env else "display")
        )

        status, val_err = validate_latex_math(clean_latex)
        warnings: list[str] = [val_err] if val_err else []

        prior_num = None
        if trailing_num and trailing_num.isdigit():
            prior_num = int(trailing_num)
        elif extracted_tag and extracted_tag.isdigit():
            prior_num = int(extracted_tag)

        equations.append(
            StructuredEquation(
                id=eq_id,
                latex=clean_latex,
                equation_number=None,
                prior_number=prior_num,
                label=eq_label,
                section_id=section_id,
                display_type=display_type,
                is_multiline=is_multi,
                rendering_status=status,
                validation_warnings=warnings,
            )
        )
        idx += 1

    return equations


def renumber_and_synchronize_equations(
    sections: list[PaperSection],
) -> tuple[list[PaperSection], list[StructuredEquation], list[ReviewWarning]]:
    """Assign consecutive 1-based equation numbers across all sections.

    Synchronizes in-text cross-references so that (1), Equation (1), Eq. (1)
    and [eq-...] match the resolved sequential equation order.
    """
    all_equations: list[StructuredEquation] = []
    eq_global_num = 1

    # First pass: collect all equations and assign sequential numbers
    for sec in sections:
        sec_eqs = extract_equations_from_section(
            sec.id, sec.content, start_index=len(all_equations) + 1
        )
        for eq in sec_eqs:
            eq.equation_number = eq_global_num
            eq_global_num += 1
            all_equations.append(eq)

    if not all_equations:
        return sections, [], []

    # Build reference mapping dictionaries
    # Maps any label, prior number, or eq_id to the resolved sequential equation number
    id_to_num: dict[str, int] = {}
    label_to_num: dict[str, int] = {}
    old_num_to_new_num: dict[int, int] = {}

    for eq in all_equations:
        assert eq.equation_number is not None
        id_to_num[eq.id] = eq.equation_number
        if eq.prior_number is not None:
            old_num_to_new_num[eq.prior_number] = eq.equation_number
        if eq.label:
            clean_l = eq.label.lower()
            label_to_num[clean_l] = eq.equation_number
            label_to_num[f"eq:{clean_l}"] = eq.equation_number
            label_to_num[f"eq-{clean_l}"] = eq.equation_number
        # Also map simple index
        id_to_num[f"eq-{eq.equation_number}"] = eq.equation_number

    warnings: list[ReviewWarning] = []
    new_sections: list[PaperSection] = []
    current_eq_idx = 0

    # Second pass: Rewrite section content with consecutive numbers and synchronized references
    for sec in sections:
        content = promote_big_inline_equations(sec.content)

        # 1. Replace display equation blocks with numbered blocks
        def replace_eq_block(match: re.Match[str]) -> str:
            nonlocal current_eq_idx
            if current_eq_idx >= len(all_equations):
                return match.group(0)

            curr_eq = all_equations[current_eq_idx]
            current_eq_idx += 1
            eq_num = curr_eq.equation_number

            # Preserve multiline environment if originally formatted as environment
            latex = curr_eq.latex
            if curr_eq.display_type == "environment" or (
                curr_eq.is_multiline and "\\begin{" in latex
            ):
                return f"\n\n$${latex}$$\n({eq_num})\n\n"
            else:
                return f"\n\n$${latex}$$\n({eq_num})\n\n"

        updated_content = DISPLAY_MATH_BLOCK_RE.sub(replace_eq_block, content)

        # 2. Synchronize in-text cross-references (Equation (1), Eq. (1), \ref{eq:foo}, [eq-foo])
        def replace_in_text_ref(m: re.Match[str]) -> str:
            prefix = m.group("prefix") or ""
            num_str = m.group("num")
            bracket_id = m.group("bracket_id")
            latex_ref = m.group("latex_ref")

            resolved_num: int | None = None

            if bracket_id:
                clean_b = bracket_id.lower().strip()
                if clean_b.startswith("eq-"):
                    clean_b = clean_b[3:]
                elif clean_b.startswith("eq:"):
                    clean_b = clean_b[3:]
                resolved_num = (
                    label_to_num.get(clean_b)
                    or id_to_num.get(f"eq-{clean_b}")
                    or label_to_num.get(f"eq:{clean_b}")
                    or label_to_num.get(f"eq-{clean_b}")
                )
            elif latex_ref:
                clean_l = latex_ref.lower().strip()
                if clean_l.startswith("eq:"):
                    clean_l = clean_l[3:]
                elif clean_l.startswith("eq-"):
                    clean_l = clean_l[3:]
                resolved_num = (
                    label_to_num.get(clean_l)
                    or label_to_num.get(f"eq:{clean_l}")
                    or id_to_num.get(f"eq-{clean_l}")
                )
            elif num_str:
                n = int(num_str)
                # First check if this was a prior number that got remapped
                if n in old_num_to_new_num:
                    resolved_num = old_num_to_new_num[n]
                elif 1 <= n <= len(all_equations):
                    resolved_num = n

            if resolved_num is not None:
                if prefix:
                    # Normalize prefix: "Eq. " or "Equation "
                    norm_prefix = prefix.strip()
                    if norm_prefix.lower() in ("eq", "eq.", "eqs", "eqs."):
                        p_str = "Eq. " if not norm_prefix.endswith("s.") else "Eqs. "
                    else:
                        p_str = (
                            "Equation "
                            if not norm_prefix.lower().startswith("eqs")
                            else "Equations "
                        )
                    return f"{p_str}({resolved_num})"
                else:
                    return f"({resolved_num})"

            # If no equation resolved and it had a prefix, return as-is
            return m.group(0)

        # Apply in-text equation replacement only on lines that are NOT display equations
        lines = updated_content.split("\n")
        reconstructed_lines: list[str] = []
        in_display_math = False

        for line in lines:
            trimmed = line.strip()
            if trimmed.startswith("$$") and trimmed.endswith("$$") and len(trimmed) > 4:
                reconstructed_lines.append(line)
                continue
            if trimmed.startswith("$$"):
                in_display_math = True
                reconstructed_lines.append(line)
                continue
            if in_display_math:
                if "$$" in trimmed:
                    in_display_math = False
                reconstructed_lines.append(line)
                continue

            # Skip lines that are just equation numbers like (1)
            if re.match(r"^\([0-9]+\)$", trimmed):
                reconstructed_lines.append(line)
                continue

            # Update in-text cross references
            updated_line = IN_TEXT_EQ_REF_RE.sub(replace_in_text_ref, line)
            reconstructed_lines.append(updated_line)

        final_content = "\n".join(reconstructed_lines)

        # Clean any consecutive empty lines
        final_content = re.sub(r"\n{3,}", "\n\n", final_content)

        new_sections.append(sec.model_copy(update={"content": final_content}))

    # Add warnings for any equation syntax errors
    for eq in all_equations:
        if eq.rendering_status in ("warning", "error"):
            msg = f"Equation [{eq.id}] in section '{eq.section_id or 'unknown'}': " + (
                eq.validation_warnings[0]
                if eq.validation_warnings
                else "Mathematical syntax warning."
            )
            warnings.append(
                ReviewWarning(
                    code="GENERAL_REVIEW",
                    severity="warning" if eq.rendering_status == "warning" else "critical",
                    message=msg,
                    section_id=eq.section_id,
                )
            )

    return new_sections, all_equations, warnings


def process_manuscript_equations(
    paper: PaperDraft,
) -> tuple[PaperDraft, list[ReviewWarning]]:
    """Top-level pipeline step: numbers and synchronizes all equations in the paper draft."""
    try:
        new_sections, equations, warnings = renumber_and_synchronize_equations(paper.sections)
        updated_paper = paper.model_copy(update={"sections": new_sections})
        logger.info(
            "Successfully indexed and numbered %d mathematical equations across %d sections.",
            len(equations),
            len(new_sections),
        )
        return updated_paper, warnings
    except Exception as exc:
        logger.error("Failed to process manuscript equations: %s", exc, exc_info=True)
        return paper, [
            ReviewWarning(
                code="GENERAL_REVIEW",
                severity="warning",
                message=f"Equation engine encountered an error while indexing equations: {exc}",
                section_id=None,
            )
        ]
