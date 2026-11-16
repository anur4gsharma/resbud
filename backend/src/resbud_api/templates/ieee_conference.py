"""IEEE Conference Paper template configuration and formatting rules."""

from __future__ import annotations

import re
from typing import Any

from resbud_api.templates.base import (
    DocumentTemplateConfig,
    HeadingStyleConfig,
    MarginsConfig,
    TypographyConfig,
)

# Standard Roman numerals for IEEE Section Headings
_ROMAN_MAP = [
    (1000, "M"),
    (900, "CM"),
    (500, "D"),
    (400, "CD"),
    (100, "C"),
    (90, "XC"),
    (50, "L"),
    (40, "XL"),
    (10, "X"),
    (9, "IX"),
    (5, "V"),
    (4, "IV"),
    (1, "I"),
]


def int_to_roman(n: int) -> str:
    """Convert a positive integer to Roman numerals."""
    if n <= 0:
        return "I"
    result: list[str] = []
    num = n
    for val, roman in _ROMAN_MAP:
        while num >= val:
            result.append(roman)
            num -= val
    return "".join(result)


def int_to_letter(n: int) -> str:
    """Convert 1-based index to Latin capital letter sequence (1 -> 'A', 26 -> 'Z', 27 -> 'AA', etc.)."""
    if n <= 0:
        return "A"
    result: list[str] = []
    num = n
    while num > 0:
        num -= 1
        result.append(chr(ord("A") + (num % 26)))
        num //= 26
    return "".join(reversed(result))


# Sections that must remain unnumbered in IEEE Conference manuscripts
UNNUMBERED_IEEE_SECTIONS = {
    "reference",
    "references",
    "bibliography",
    "acknowledgment",
    "acknowledgments",
    "acknowledgements",
    "author contributions",
    "appendix",
    "appendices",
}

IEEE_TYPOGRAPHY = TypographyConfig(
    font_family="Times New Roman",
    title_size_pt=24.0,
    subtitle_size_pt=14.0,
    author_name_size_pt=11.0,
    author_detail_size_pt=9.0,
    abstract_heading_size_pt=9.0,
    abstract_body_size_pt=9.0,
    heading_1_size_pt=10.0,
    heading_2_size_pt=10.0,
    heading_3_size_pt=10.0,
    body_size_pt=10.0,
    caption_size_pt=8.0,
    table_cell_size_pt=8.0,
    reference_size_pt=9.0,
)

IEEE_CONFERENCE_CONFIG = DocumentTemplateConfig(
    template_id="ieee_conference",
    display_name="IEEE Conference Paper",
    category="Academic Research",
    default_page_layout="two_column_academic",
    default_typography=IEEE_TYPOGRAPHY,
    default_equation_format="omml",
    default_citation_format="ieee",
    default_reference_format="IEEE bibliography",
    page_width_inch=8.5,
    page_height_inch=11.0,
    margins=MarginsConfig(top=0.75, bottom=0.75, left=0.625, right=0.625),
    column_count=2,
    column_gap_inch=0.25,
    column_spacing_twips=360,
    heading_styles=HeadingStyleConfig(
        level_1_case="upper",
        level_1_alignment="center",
        level_1_small_caps=True,
        level_1_bold=True,
        level_1_numbering="roman",
        level_2_case="title",
        level_2_alignment="left",
        level_2_italic=True,
        level_2_bold=False,
        level_2_numbering="letter",
        level_3_case="title",
        level_3_alignment="left",
        level_3_italic=True,
        level_3_bold=False,
        level_3_numbering="arabic_paren",
    ),
    line_spacing=1.05,
    space_after_body_pt=4.0,
    abstract_prefix="Abstract—",
    index_terms_prefix="Index Terms—",
    references_heading="References",
    acknowledgment_heading="Acknowledgment",
)


def format_ieee_heading_1(num: int, heading_text: str) -> str:
    """Format a primary section heading according to IEEE conventions.

    Examples:
    - 1, "Introduction" -> "I. INTRODUCTION"
    - 2, "Related Work" -> "II. RELATED WORK"
    - 7, "References"   -> "REFERENCES" (unnumbered)
    - 8, "Acknowledgment" -> "ACKNOWLEDGMENT" (unnumbered)
    """
    clean_text = heading_text.strip()
    # Strip any existing leading roman or arabic numbers followed by a dot or space e.g. "I. Introduction", "1. Introduction"
    match = re.match(r"^(?:[IVXLCDM]+|\d+)(?:\.|\s)\s*(.+)$", clean_text, re.IGNORECASE)
    if match:
        clean_text = match.group(1).strip()

    if clean_text.lower() in ("reference", "references"):
        return "REFERENCES"
    if clean_text.lower() in ("acknowledgment", "acknowledgments", "acknowledgements"):
        return clean_text.upper()
    if clean_text.lower() in UNNUMBERED_IEEE_SECTIONS:
        return clean_text.upper()

    roman = int_to_roman(num)
    return f"{roman}. {clean_text.upper()}"


def format_ieee_heading_2(letter_idx: int, subheading_text: str) -> str:
    """Format a level-2 subheading according to IEEE conventions.

    Examples:
    - 1, "Image Acquisition" -> "A. Image Acquisition"
    - 2, "Human Pose Estimation" -> "B. Human Pose Estimation"
    """
    clean_text = subheading_text.strip()
    match = re.match(r"^[A-Z](?:\.|\s)\s*(.+)$", clean_text)
    if match:
        clean_text = match.group(1).strip()

    letter = int_to_letter(letter_idx)
    return f"{letter}. {clean_text}"


def format_ieee_heading_3(num: int, subsubheading_text: str) -> str:
    """Format a level-3 sub-subheading according to IEEE conventions.

    Examples:
    - 1, "Camera Setup" -> "1) Camera Setup:"
    """
    clean_text = subsubheading_text.strip()
    match = re.match(r"^\d+(?:\)|\.|\s)\s*(.+)$", clean_text)
    if match:
        clean_text = match.group(1).strip().rstrip(":")

    return f"{num}) {clean_text}:"


def calculate_ieee_author_grid(author_count: int) -> list[int]:
    """Calculate the row/column distribution of author blocks across 1–10 authors.

    Matches standard IEEE conference author tables:
    - 1 author  -> [1] (single centered block)
    - 2 authors -> [2] (1 row, 2 columns)
    - 3 authors -> [3] (1 row, 3 columns)
    - 4 authors -> [2, 2] (2 rows, 2 columns each)
    - 5 authors -> [3, 2] (replicates ASEP 2 RP.docx: 3 on top, 2 on bottom)
    - 6 authors -> [3, 3] (2 rows, 3 columns each)
    - 7 authors -> [4, 3] (2 rows: 4 on top, 3 on bottom)
    - 8 authors -> [4, 4] (2 rows, 4 columns each)
    - 9 authors -> [3, 3, 3] (3 rows, 3 columns each)
    - 10 authors -> [4, 3, 3] (3 rows)
    """
    if author_count <= 0:
        return []
    if author_count == 1:
        return [1]
    if author_count == 2:
        return [2]
    if author_count == 3:
        return [3]
    if author_count == 4:
        return [2, 2]
    if author_count == 5:
        return [3, 2]
    if author_count == 6:
        return [3, 3]
    if author_count == 7:
        return [4, 3]
    if author_count == 8:
        return [4, 4]
    if author_count == 9:
        return [3, 3, 3]
    if author_count == 10:
        return [4, 3, 3]
    # For author counts > 10, partition into rows of at most 3 or 4
    rows: list[int] = []
    remaining = author_count
    while remaining > 0:
        chunk = min(remaining, 3)
        rows.append(chunk)
        remaining -= chunk
    return rows


def validate_author_metadata(authors: list[dict[str, Any]]) -> list[str]:
    """Inspect authors and report warnings for missing or unresolved metadata fields.

    Never fabricates names, institutions, emails or credentials.
    """
    warnings: list[str] = []
    if not authors:
        warnings.append(
            "No authors supplied. The paper will be published without author attribution."
        )
        return warnings

    for idx, author in enumerate(authors, start=1):
        name = author.get("name", "").strip()
        author_label = name or f"#{idx}"
        if not name:
            warnings.append(f"Author #{idx} is missing a required name.")
        inst = author.get("institution", "").strip()
        dept = author.get("department", "").strip()
        email = author.get("email", "").strip()
        if not inst and not dept:
            warnings.append(
                f"Author '{author_label}' is missing institutional affiliation details."
            )
        if not email:
            warnings.append(f"Author '{author_label}' is missing an email address.")

    return warnings
