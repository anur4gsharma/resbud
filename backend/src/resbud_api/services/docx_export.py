"""In-memory DOCX rendering for a validated current paper draft."""

from __future__ import annotations

import logging
import re
import unicodedata
from io import BytesIO
from pathlib import Path
from typing import Any

import math2docx
from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Mm, Pt, RGBColor

from resbud_api.core.errors import ResbudError
from resbud_api.domain.models import PaperDraft
from resbud_api.services.chart_generator import render_academic_chart_from_spec
from resbud_api.services.editorial_notes import prepare_paper_for_export
from resbud_api.services.image_processor import decode_image_source, process_image_for_document
from resbud_api.services.markdown_renderer import (
    clean_heading_text,
    parse_markdown_blocks,
    render_blocks_to_docx,
)

logger = logging.getLogger(__name__)

MAX_EXPORT_BYTES = 8 * 1024 * 1024
DOCX_MEDIA_TYPE = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
FORMAT_SPECIFIER_DIR_NAME = "format_specifier_papers"


def safe_docx_filename(title: str) -> str:
    """Create a short ASCII filename without using user text as a path."""
    ascii_title = unicodedata.normalize("NFKD", title).encode("ascii", "ignore").decode("ascii")
    slug = re.sub(r"[^a-z0-9]+", "-", ascii_title.lower()).strip("-")[:64].strip("-")
    return f"resbud-{slug or 'research-paper'}.docx"


def get_format_specifier_reference_path() -> Path | None:
    """Safely locate the format specifier folder if present, handling its absence gracefully."""
    candidates = [
        Path.cwd() / FORMAT_SPECIFIER_DIR_NAME,
        Path.cwd().parent / FORMAT_SPECIFIER_DIR_NAME,
        Path(__file__).resolve().parents[4] / FORMAT_SPECIFIER_DIR_NAME,
    ]
    for candidate in candidates:
        if candidate.is_dir():
            files = [f for f in candidate.iterdir() if f.is_file() and not f.name.startswith(".")]
            if files:
                return files[0]
    return None


def export_paper_docx(
    paper: PaperDraft,
    layout: str | None = None,
    include_review_notes_appendix: bool | None = None,
) -> bytes:
    """Render the submitted paper in its supplied order and return DOCX bytes."""
    try:
        effective_layout = layout or getattr(paper, "page_layout", "single_column")
        effective_notes = (
            include_review_notes_appendix
            if include_review_notes_appendix is not None
            else getattr(paper, "include_review_notes_appendix", False)
        )
        sanitized_paper, review_notes = prepare_paper_for_export(
            paper, include_review_notes_appendix=effective_notes
        )

        if effective_layout == "two_column_academic":
            document = _create_two_column_document(sanitized_paper, review_notes=review_notes)
        else:
            document = _create_document(sanitized_paper, review_notes=review_notes)
        output = BytesIO()
        document.save(output)
        result = output.getvalue()
    except Exception as exc:
        raise ResbudError(500) from exc
    if len(result) > MAX_EXPORT_BYTES:
        raise ResbudError(413)
    return result


def _add_page_number_to_footer(footer: Any) -> None:
    """Add a clean, centered dynamic Word PAGE field code to the section footer."""
    try:
        p = footer.paragraphs[0] if footer.paragraphs else footer.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        run = p.add_run()
        fldChar1 = OxmlElement("w:fldChar")
        fldChar1.set(qn("w:fldCharType"), "begin")
        instrText = OxmlElement("w:instrText")
        instrText.set(qn("xml:space"), "preserve")
        instrText.text = "PAGE"
        fldChar2 = OxmlElement("w:fldChar")
        fldChar2.set(qn("w:fldCharType"), "separate")
        fldChar3 = OxmlElement("w:fldChar")
        fldChar3.set(qn("w:fldCharType"), "end")

        r = run._r
        r.append(fldChar1)
        r.append(instrText)
        r.append(fldChar2)
        r.append(fldChar3)
        run.font.name = "Times New Roman"
        run.font.size = Pt(9.0)
        run.font.color.rgb = RGBColor(0x55, 0x55, 0x55)
    except Exception as exc:
        logger.warning("Failed to inject page number into footer: %s", exc)


def _configure_two_column_academic_styles(document: Any) -> None:
    """Apply formal academic research paper styles for two-column academic layouts (IEEE style)."""
    academic_font = "Times New Roman"
    pure_black = RGBColor(0, 0, 0)

    for style_name in ["Normal", "Title", "Heading 1", "Heading 2", "Heading 3"]:
        if style_name in document.styles:
            style = document.styles[style_name]
            style.font.name = academic_font
            style.font.color.rgb = pure_black
            rPr = style.element.rPr
            if rPr is not None and rPr.rFonts is not None:
                rPr.rFonts.set(qn("w:ascii"), academic_font)
                rPr.rFonts.set(qn("w:hAnsi"), academic_font)
                rPr.rFonts.set(qn("w:cs"), academic_font)

    normal = document.styles["Normal"]
    normal.font.size = Pt(9.5)
    normal.paragraph_format.line_spacing = 1.12
    normal.paragraph_format.space_after = Pt(4)
    normal.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY

    title = document.styles["Title"]
    title.font.size = Pt(18)
    title.font.bold = True
    title.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
    title.paragraph_format.space_before = Pt(10)
    title.paragraph_format.space_after = Pt(8)

    h1 = document.styles["Heading 1"]
    h1.font.size = Pt(11)
    h1.font.bold = True
    h1.paragraph_format.space_before = Pt(10)
    h1.paragraph_format.space_after = Pt(3)
    h1.paragraph_format.keep_with_next = True

    if "Heading 2" in document.styles:
        h2 = document.styles["Heading 2"]
        h2.font.size = Pt(10)
        h2.font.bold = True
        h2.paragraph_format.space_before = Pt(7)
        h2.paragraph_format.space_after = Pt(2)
        h2.paragraph_format.keep_with_next = True


def _configure_academic_styles(document: Any) -> None:
    """Apply formal academic research paper styles modeled on reference formatting.

    Reference attributes (from format_specifier_papers):
    - Typography: Times New Roman / Roman serif, pure black (#000000)
    - Normal body text: 10.5pt, 1.15 line spacing, 6pt space after
    - Title: Centered, 18pt bold, 12pt before / 14pt after
    - Heading 1: 12pt bold, 12pt before / 4pt after, keep-with-next
    - Heading 2: 11pt bold, 8pt before / 3pt after, keep-with-next
    - Heading 3: 10.5pt bold/italic, 6pt before / 2pt after, keep-with-next
    """
    academic_font = "Times New Roman"
    pure_black = RGBColor(0, 0, 0)

    for style_name in ["Normal", "Title", "Heading 1", "Heading 2", "Heading 3"]:
        if style_name in document.styles:
            style = document.styles[style_name]
            style.font.name = academic_font
            style.font.color.rgb = pure_black
            rPr = style.element.rPr
            if rPr is not None and rPr.rFonts is not None:
                rPr.rFonts.set(qn("w:ascii"), academic_font)
                rPr.rFonts.set(qn("w:hAnsi"), academic_font)
                rPr.rFonts.set(qn("w:cs"), academic_font)

    normal = document.styles["Normal"]
    normal.font.size = Pt(10.5)
    normal.paragraph_format.line_spacing = 1.15
    normal.paragraph_format.space_after = Pt(6)

    title = document.styles["Title"]
    title.font.size = Pt(18)
    title.font.bold = True
    title.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
    title.paragraph_format.space_before = Pt(12)
    title.paragraph_format.space_after = Pt(14)

    h1 = document.styles["Heading 1"]
    h1.font.size = Pt(12)
    h1.font.bold = True
    h1.paragraph_format.space_before = Pt(12)
    h1.paragraph_format.space_after = Pt(4)
    h1.paragraph_format.keep_with_next = True

    if "Heading 2" in document.styles:
        h2 = document.styles["Heading 2"]
        h2.font.size = Pt(11)
        h2.font.bold = True
        h2.paragraph_format.space_before = Pt(8)
        h2.paragraph_format.space_after = Pt(3)
        h2.paragraph_format.keep_with_next = True


def _ensure_run_style(paragraph: Any, bold: bool | None = None) -> None:
    """Ensure every text run in headings and paragraphs is explicitly pure black."""
    for run in paragraph.runs:
        run.font.name = "Times New Roman"
        run.font.color.rgb = RGBColor(0, 0, 0)
        if bold is not None:
            run.font.bold = bold


def _create_document(paper: PaperDraft, review_notes: list[dict[str, str]] | None = None) -> Any:
    # Handle absence of format_specifier_papers gracefully without crashing
    _ = get_format_specifier_reference_path()

    document = Document()
    page_section = document.sections[0]
    page_section.top_margin = Inches(1)
    page_section.bottom_margin = Inches(1)
    page_section.left_margin = Inches(1)
    page_section.right_margin = Inches(1)

    _configure_academic_styles(document)

    document.core_properties.title = paper.title
    title_p = document.add_heading(paper.title, level=0)
    _ensure_run_style(title_p, bold=True)

    if paper.author_info and paper.author_info.strip():
        auth_p = document.add_paragraph()
        auth_p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
        auth_p.paragraph_format.space_before = Pt(2)
        auth_p.paragraph_format.space_after = Pt(2)
        r = auth_p.add_run(paper.author_info.strip())
        r.font.name = "Times New Roman"
        r.font.size = Pt(11)
        r.font.bold = True
        r.font.color.rgb = RGBColor(0, 0, 0)

    if paper.affiliation and paper.affiliation.strip():
        aff_p = document.add_paragraph()
        aff_p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
        aff_p.paragraph_format.space_before = Pt(0)
        aff_p.paragraph_format.space_after = Pt(8)
        r = aff_p.add_run(paper.affiliation.strip())
        r.font.name = "Times New Roman"
        r.font.size = Pt(9.5)
        r.font.italic = True
        r.font.color.rgb = RGBColor(0, 0, 0)

    abs_p = document.add_heading("Abstract", level=1)
    _ensure_run_style(abs_p, bold=True)
    _add_text_paragraph(document, paper.abstract)

    kw_p = document.add_heading("Keywords", level=1)
    _ensure_run_style(kw_p, bold=True)
    _add_text_paragraph(document, ", ".join(paper.keywords))

    body_sections = [
        sec
        for sec in paper.sections
        if sec.id.lower() not in ("references", "bibliography")
        and sec.heading.strip().lower() not in ("references", "bibliography", "6. references")
    ]

    for sec_idx, section in enumerate(body_sections, start=1):
        clean_title = clean_heading_text(section.heading)
        heading_text = f"{sec_idx}. {clean_title}"
        sec_p = document.add_heading(heading_text, level=1)
        _ensure_run_style(sec_p, bold=True)
        blocks = parse_markdown_blocks(section.content)
        render_blocks_to_docx(
            document,
            blocks,
            section_index=sec_idx,
            numbered=True,
            academic_font="Times New Roman",
        )

    if paper.references:
        ref_heading = document.add_heading("References", level=1)
        _ensure_run_style(ref_heading, bold=True)
        for ref_idx, reference in enumerate(paper.references, start=1):
            ref_text = reference.text.strip()
            if not re.match(r"^\[\d+\]", ref_text) and not re.match(r"^\d+\.", ref_text):
                ref_text = f"[{ref_idx}] {ref_text}"
            paragraph = document.add_paragraph()
            paragraph.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
            paragraph.paragraph_format.left_indent = Inches(0.3)
            paragraph.paragraph_format.first_line_indent = Inches(-0.3)
            paragraph.paragraph_format.space_after = Pt(4)
            paragraph.paragraph_format.line_spacing = 1.15
            run = paragraph.add_run(ref_text)
            run.font.name = "Times New Roman"
            run.font.size = Pt(9.5)
            run.font.color.rgb = RGBColor(0, 0, 0)

    if review_notes:
        notes_h = document.add_heading("Author Review Notes", level=1)
        _ensure_run_style(notes_h, bold=True)
        lead_p = document.add_paragraph()
        lead_run = lead_p.add_run(
            "The following unresolved research and editorial review notes pertain to this manuscript:"
        )
        lead_run.font.name = "Times New Roman"
        lead_run.font.italic = True
        lead_p.paragraph_format.space_after = Pt(4)

        for n_idx, note in enumerate(review_notes, start=1):
            p = document.add_paragraph()
            p.paragraph_format.left_indent = Inches(0.25)
            p.paragraph_format.space_before = Pt(2)
            p.paragraph_format.space_after = Pt(2)
            num_run = p.add_run(f"{n_idx}. [{note['section']}] ")
            num_run.font.name = "Times New Roman"
            num_run.font.bold = True
            msg_run = p.add_run(note["message"])
            msg_run.font.name = "Times New Roman"
            msg_run.font.size = Pt(9.5)

    return document


def _create_two_column_document(
    paper: PaperDraft, review_notes: list[dict[str, str]] | None = None
) -> Any:
    """Render a formal Two-Column Academic research paper with full-width front matter (IEEE style)."""
    # Handle absence of format_specifier_papers gracefully without crashing
    _ = get_format_specifier_reference_path()

    document = Document()

    # Section 1: Full-width Front Matter (Title, Authors, Affiliation, Abstract, Keywords)
    sec1 = document.sections[0]
    sec1.page_width = Mm(210)
    sec1.page_height = Mm(297)
    sec1.top_margin = Mm(19)
    sec1.bottom_margin = Mm(19)
    sec1.left_margin = Mm(19)
    sec1.right_margin = Mm(19)

    _add_page_number_to_footer(sec1.footer)
    _configure_two_column_academic_styles(document)

    document.core_properties.title = paper.title
    title_p = document.add_heading(paper.title, level=0)
    _ensure_run_style(title_p, bold=True)

    # Author and Affiliation (only when supplied)
    if paper.author_info and paper.author_info.strip():
        auth_p = document.add_paragraph()
        auth_p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
        auth_p.paragraph_format.space_before = Pt(2)
        auth_p.paragraph_format.space_after = Pt(2)
        r = auth_p.add_run(paper.author_info.strip())
        r.font.name = "Times New Roman"
        r.font.size = Pt(11)
        r.font.bold = True
        r.font.color.rgb = RGBColor(0, 0, 0)

    if paper.affiliation and paper.affiliation.strip():
        aff_p = document.add_paragraph()
        aff_p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
        aff_p.paragraph_format.space_before = Pt(0)
        aff_p.paragraph_format.space_after = Pt(10)
        r = aff_p.add_run(paper.affiliation.strip())
        r.font.name = "Times New Roman"
        r.font.size = Pt(9.5)
        r.font.italic = True
        r.font.color.rgb = RGBColor(0, 0, 0)

    # Full-width Abstract
    if paper.abstract and paper.abstract.strip():
        abs_p = document.add_paragraph()
        abs_p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
        abs_p.paragraph_format.line_spacing = 1.12
        abs_p.paragraph_format.space_before = Pt(6)
        abs_p.paragraph_format.space_after = Pt(6)
        abs_p.paragraph_format.left_indent = Inches(0.2)
        abs_p.paragraph_format.right_indent = Inches(0.2)
        r_head = abs_p.add_run("Abstract—")
        r_head.font.name = "Times New Roman"
        r_head.font.size = Pt(9.5)
        r_head.font.bold = True
        r_head.font.color.rgb = RGBColor(0, 0, 0)
        r_text = abs_p.add_run(" " + paper.abstract.strip())
        r_text.font.name = "Times New Roman"
        r_text.font.size = Pt(9.5)
        r_text.font.color.rgb = RGBColor(0, 0, 0)

    # Full-width Keywords
    if paper.keywords:
        kw_p = document.add_paragraph()
        kw_p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
        kw_p.paragraph_format.line_spacing = 1.12
        kw_p.paragraph_format.space_after = Pt(12)
        kw_p.paragraph_format.left_indent = Inches(0.2)
        kw_p.paragraph_format.right_indent = Inches(0.2)
        kw_head = kw_p.add_run("Index Terms—")
        kw_head.font.name = "Times New Roman"
        kw_head.font.size = Pt(9.5)
        kw_head.font.bold = True
        kw_head.font.italic = True
        kw_head.font.color.rgb = RGBColor(0, 0, 0)
        kw_text = kw_p.add_run(" " + ", ".join(paper.keywords))
        kw_text.font.name = "Times New Roman"
        kw_text.font.size = Pt(9.5)
        kw_text.font.color.rgb = RGBColor(0, 0, 0)

    # Section 2: Two vertical columns starting at the main body
    sec2 = document.add_section(WD_SECTION.CONTINUOUS)
    sec2.page_width = Mm(210)
    sec2.page_height = Mm(297)
    sec2.top_margin = Mm(19)
    sec2.bottom_margin = Mm(19)
    sec2.left_margin = Mm(19)
    sec2.right_margin = Mm(19)

    sectPr = sec2._sectPr
    cols = sectPr.xpath("./w:cols")
    if cols:
        col_elem = cols[0]
    else:
        col_elem = OxmlElement("w:cols")
        sectPr.append(col_elem)
    col_elem.set(qn("w:num"), "2")
    col_elem.set(qn("w:space"), "425")  # ~7.5mm inter-column space
    col_elem.set(qn("w:equalWidth"), "1")

    body_sections = [
        sec
        for sec in paper.sections
        if sec.id.lower() not in ("references", "bibliography")
        and sec.heading.strip().lower() not in ("references", "bibliography", "6. references")
    ]

    for sec_idx, section in enumerate(body_sections, start=1):
        clean_title = clean_heading_text(section.heading)
        heading_text = f"{sec_idx}. {clean_title}"
        sec_p = document.add_heading(heading_text, level=1)
        _ensure_run_style(sec_p, bold=True)
        sec_p.paragraph_format.keep_with_next = True
        blocks = parse_markdown_blocks(section.content)
        render_blocks_to_docx(
            document,
            blocks,
            section_index=sec_idx,
            numbered=True,
            academic_font="Times New Roman",
            two_column=True,
        )

    # References in Section 2 (flows across the two columns)
    if paper.references:
        ref_heading = document.add_heading("References", level=1)
        _ensure_run_style(ref_heading, bold=True)
        ref_heading.paragraph_format.keep_with_next = True
        for ref_idx, reference in enumerate(paper.references, start=1):
            ref_text = reference.text.strip()
            if not re.match(r"^\[\d+\]", ref_text) and not re.match(r"^\d+\.", ref_text):
                ref_text = f"[{ref_idx}] {ref_text}"
            paragraph = document.add_paragraph()
            paragraph.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
            paragraph.paragraph_format.left_indent = Inches(0.22)
            paragraph.paragraph_format.first_line_indent = Inches(-0.22)
            paragraph.paragraph_format.space_after = Pt(3)
            paragraph.paragraph_format.line_spacing = 1.05
            run = paragraph.add_run(ref_text)
            run.font.name = "Times New Roman"
            run.font.size = Pt(8.5)
            run.font.color.rgb = RGBColor(0, 0, 0)

    if review_notes:
        notes_h = document.add_heading("Author Review Notes", level=1)
        _ensure_run_style(notes_h, bold=True)
        notes_h.paragraph_format.keep_with_next = True
        lead_p = document.add_paragraph()
        lead_run = lead_p.add_run(
            "The following unresolved research and editorial review notes pertain to this manuscript:"
        )
        lead_run.font.name = "Times New Roman"
        lead_run.font.italic = True
        lead_run.font.size = Pt(8.5)
        lead_p.paragraph_format.space_after = Pt(3)

        for n_idx, note in enumerate(review_notes, start=1):
            p = document.add_paragraph()
            p.paragraph_format.left_indent = Inches(0.18)
            p.paragraph_format.space_before = Pt(2)
            p.paragraph_format.space_after = Pt(2)
            num_run = p.add_run(f"{n_idx}. [{note['section']}] ")
            num_run.font.name = "Times New Roman"
            num_run.font.bold = True
            num_run.font.size = Pt(8.5)
            msg_run = p.add_run(note["message"])
            msg_run.font.name = "Times New Roman"
            msg_run.font.size = Pt(8.5)

    return document


INLINE_MATH_PATTERN = re.compile(
    r"(\$\$[\s\S]*?\$\$|\\\[[\s\S]*?\\\]|\$[^$\n]+\$|\\\([\s\S]*?\\\))"
)
BLOCK_MATH_PATTERN = re.compile(
    r"^(?:\$\$([\s\S]*?)\$\$|\\\[([\s\S]*?)\\\]|\\begin\{(?:equation|align|gather)\*?}([\s\S]*?)\\end\{(?:equation|align|gather)\*?})$"
)


def _render_section_content(document: Any, content: str) -> None:
    has_image = bool(re.search(r"!\[(.*?)\]\((.*?)\)", content))
    has_table = bool(re.search(r"\|.*\|", content) and "---" in content)
    has_block_math = bool(
        re.search(r"\$\$[\s\S]*?\$\$|\\\[[\s\S]*?\\\]|\\begin\{equation", content)
    )

    if not has_image and not has_table and not has_block_math:
        _add_text_paragraph(document, content)
        return

    blocks = content.split("\n\n")
    for block in blocks:
        trimmed = block.strip()
        if not trimmed:
            continue
        chart_match = re.match(r"^```chart\s*([\s\S]*?)\s*```$", trimmed)
        if chart_match:
            spec_content = chart_match.group(1)
            chart_bytes = render_academic_chart_from_spec(spec_content)
            if chart_bytes:
                caption = "Figure: Quantitative Results"
                for c_line in spec_content.split("\n"):
                    if c_line.strip().lower().startswith("title:"):
                        caption = f"Figure: {c_line.split(':', 1)[1].strip()}"
                        break
                _insert_figure_from_bytes(document, chart_bytes, caption)
                continue
        fig_match = re.match(r"^!\[(.*?)\]\((.*?)\)$", trimmed)
        if fig_match:
            caption_text = fig_match.group(1)
            img_src = fig_match.group(2)
            _insert_figure_from_src(document, img_src, caption_text)
            continue
        lines = [line.strip() for line in trimmed.split("\n") if line.strip()]
        if len(lines) >= 2 and all(line.startswith("|") and line.endswith("|") for line in lines):
            _insert_table(document, lines)
            continue
        if BLOCK_MATH_PATTERN.match(trimmed) or (
            trimmed.startswith("$$") and trimmed.endswith("$$")
        ):
            _insert_equation_block(document, trimmed)
            continue
        _add_text_paragraph(document, trimmed)


def _insert_equation_block(document: Any, latex_formula: str) -> None:
    formula = latex_formula.strip()
    match = BLOCK_MATH_PATTERN.match(formula)
    if match:
        clean_latex = (match.group(1) or match.group(2) or match.group(3) or formula).strip()
    elif formula.startswith("$$") and formula.endswith("$$"):
        clean_latex = formula[2:-2].strip()
    elif formula.startswith(r"\[") and formula.endswith(r"\]"):
        clean_latex = formula[2:-2].strip()
    else:
        clean_latex = formula

    p = document.add_paragraph()
    p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(8)
    p.paragraph_format.space_after = Pt(8)
    try:
        math2docx.add_math(p, clean_latex)
    except Exception:
        run = p.add_run(formula)
        run.font.name = "Times New Roman"
        run.font.italic = True
        run.font.color.rgb = RGBColor(0, 0, 0)


def _insert_figure_from_bytes(document: Any, img_bytes: bytes, caption: str) -> None:
    try:
        processed = process_image_for_document(img_bytes, max_width_pt=396.0, max_height_pt=300.0)
        if processed is not None:
            buf, target_w_pt, target_h_pt = processed
            target_w_in = target_w_pt / 72.0
            target_h_in = target_h_pt / 72.0

            p = document.add_paragraph()
            p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
            p.paragraph_format.space_before = Pt(8)
            p.paragraph_format.space_after = Pt(4)
            p.paragraph_format.keep_with_next = True
            run = p.add_run()
            run.add_picture(buf, width=Inches(target_w_in), height=Inches(target_h_in))

            caption_p = document.add_paragraph()
            caption_p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
            caption_p.paragraph_format.space_before = Pt(2)
            caption_p.paragraph_format.space_after = Pt(12)
            c_run = caption_p.add_run(caption)
            c_run.font.name = "Times New Roman"
            c_run.font.size = Pt(9.5)
            c_run.font.italic = True
            c_run.font.color.rgb = RGBColor(0x33, 0x33, 0x33)
            return
    except Exception as exc:
        logger.warning("Failed to render figure bytes to DOCX: %s", exc)

    p = document.add_paragraph()
    p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = p.add_run(f"[{caption}]")
    run.font.name = "Times New Roman"
    run.font.italic = True


def _insert_figure_from_src(document: Any, img_src: str, caption: str) -> None:
    img_bytes = decode_image_source(img_src)
    if img_bytes is not None:
        _insert_figure_from_bytes(document, img_bytes, caption)
    else:
        p = document.add_paragraph()
        p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
        run = p.add_run(f"[{caption}]")
        run.font.name = "Times New Roman"
        run.font.italic = True


def _insert_table(document: Any, lines: list[str]) -> None:
    try:
        parsed_rows = []
        for line in lines:
            if "---" in line:
                continue
            cells = [c.strip() for c in line.strip("|").split("|")]
            parsed_rows.append(cells)
        if not parsed_rows:
            return
        num_cols = max(len(row) for row in parsed_rows)
        table = document.add_table(rows=len(parsed_rows), cols=num_cols)
        table.style = "Table Grid"
        for r_idx, row in enumerate(parsed_rows):
            for c_idx, cell_text in enumerate(row):
                if c_idx < num_cols:
                    cell = table.cell(r_idx, c_idx)
                    cell.text = cell_text
                    for p in cell.paragraphs:
                        p.paragraph_format.space_after = Pt(2)
                        p.paragraph_format.space_before = Pt(2)
                        p.paragraph_format.line_spacing = 1.05
                        for r in p.runs:
                            r.font.name = "Times New Roman"
                            r.font.size = Pt(9.5)
                            r.font.color.rgb = RGBColor(0, 0, 0)
                            if r_idx == 0:
                                r.font.bold = True
        space_p = document.add_paragraph()
        space_p.paragraph_format.space_after = Pt(6)
    except Exception:
        _add_text_paragraph(document, "\n".join(lines))


def _append_line_with_math(paragraph: Any, line: str) -> None:
    tokens = INLINE_MATH_PATTERN.split(line)
    for token in tokens:
        if not token:
            continue
        is_math = False
        clean_math = token
        if token.startswith("$$") and token.endswith("$$") and len(token) > 4:
            is_math = True
            clean_math = token[2:-2].strip()
        elif token.startswith(r"\[") and token.endswith(r"\]") and len(token) > 4:
            is_math = True
            clean_math = token[2:-2].strip()
        elif token.startswith("$") and token.endswith("$") and len(token) > 2:
            is_math = True
            clean_math = token[1:-1].strip()
        elif token.startswith(r"\(") and token.endswith(r"\)") and len(token) > 4:
            is_math = True
            clean_math = token[2:-2].strip()

        if is_math and clean_math:
            try:
                math2docx.add_math(paragraph, clean_math)
                continue
            except Exception as exc:
                logger.warning(
                    "Failed to render mathematical formula into docx, falling back to raw text: %s",
                    exc,
                )
        run = paragraph.add_run(token)
        run.font.name = "Times New Roman"
        run.font.color.rgb = RGBColor(0, 0, 0)


def _add_text_paragraph(document: Any, text: str) -> None:
    paragraph = document.add_paragraph()
    paragraph.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    paragraph.paragraph_format.line_spacing = 1.15
    paragraph.paragraph_format.space_after = Pt(6)
    lines = text.split("\n")
    for index, line in enumerate(lines):
        if line:
            _append_line_with_math(paragraph, line)
        if index < len(lines) - 1:
            break_run = paragraph.add_run()
            break_run.font.name = "Times New Roman"
            break_run.font.color.rgb = RGBColor(0, 0, 0)
            break_run.add_break(WD_BREAK.LINE)
