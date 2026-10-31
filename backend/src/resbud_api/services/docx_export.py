"""In-memory DOCX rendering for a validated current paper draft."""

from __future__ import annotations

import re
import unicodedata
from io import BytesIO
from pathlib import Path
from typing import Any

from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor

from resbud_api.core.errors import ResbudError
from resbud_api.domain.models import PaperDraft

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


def export_paper_docx(paper: PaperDraft) -> bytes:
    """Render the submitted paper in its supplied order and return DOCX bytes."""
    try:
        document = _create_document(paper)
        output = BytesIO()
        document.save(output)
        result = output.getvalue()
    except Exception as exc:
        raise ResbudError(500) from exc
    if len(result) > MAX_EXPORT_BYTES:
        raise ResbudError(413)
    return result


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


def _create_document(paper: PaperDraft) -> Any:
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

    abs_p = document.add_heading("Abstract", level=1)
    _ensure_run_style(abs_p, bold=True)
    _add_text_paragraph(document, paper.abstract)

    kw_p = document.add_heading("Keywords", level=1)
    _ensure_run_style(kw_p, bold=True)
    _add_text_paragraph(document, ", ".join(paper.keywords))

    for section in paper.sections:
        sec_p = document.add_heading(section.heading, level=1)
        _ensure_run_style(sec_p, bold=True)
        _add_text_paragraph(document, section.content)

    if paper.references:
        ref_heading = document.add_heading("References", level=1)
        _ensure_run_style(ref_heading, bold=True)
        for reference in paper.references:
            paragraph = document.add_paragraph(reference.text)
            paragraph.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
            paragraph.paragraph_format.left_indent = Inches(0.25)
            paragraph.paragraph_format.first_line_indent = Inches(-0.25)
            paragraph.paragraph_format.space_after = Pt(4)
            paragraph.paragraph_format.line_spacing = 1.15
            _ensure_run_style(paragraph)

    return document


def _add_text_paragraph(document: Any, text: str) -> None:
    paragraph = document.add_paragraph()
    paragraph.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    paragraph.paragraph_format.line_spacing = 1.15
    paragraph.paragraph_format.space_after = Pt(6)
    lines = text.split("\n")
    for index, line in enumerate(lines):
        if line:
            run = paragraph.add_run(line)
            run.font.name = "Times New Roman"
            run.font.color.rgb = RGBColor(0, 0, 0)
        if index < len(lines) - 1:
            break_run = paragraph.add_run()
            break_run.font.name = "Times New Roman"
            break_run.font.color.rgb = RGBColor(0, 0, 0)
            break_run.add_break(WD_BREAK.LINE)
