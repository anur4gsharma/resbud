"""In-memory DOCX rendering for a validated current paper draft."""

from __future__ import annotations

import re
import unicodedata
from io import BytesIO
from typing import Any

from docx import Document
from docx.enum.text import WD_BREAK
from docx.shared import Inches, Pt

from resbud_api.core.errors import ResbudError
from resbud_api.domain.models import PaperDraft

MAX_EXPORT_BYTES = 8 * 1024 * 1024
DOCX_MEDIA_TYPE = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"


def safe_docx_filename(title: str) -> str:
    """Create a short ASCII filename without using user text as a path."""
    ascii_title = unicodedata.normalize("NFKD", title).encode("ascii", "ignore").decode("ascii")
    slug = re.sub(r"[^a-z0-9]+", "-", ascii_title.lower()).strip("-")[:64].strip("-")
    return f"resbud-{slug or 'research-paper'}.docx"


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


def _create_document(paper: PaperDraft) -> Any:
    document = Document()
    page_section = document.sections[0]
    page_section.top_margin = Inches(1)
    page_section.bottom_margin = Inches(1)
    page_section.left_margin = Inches(1)
    page_section.right_margin = Inches(1)

    normal = document.styles["Normal"]
    normal.font.name = "Calibri"
    normal.font.size = Pt(11)

    document.core_properties.title = paper.title
    document.add_heading(paper.title, level=0)

    document.add_heading("Abstract", level=1)
    _add_text_paragraph(document, paper.abstract)

    document.add_heading("Keywords", level=1)
    _add_text_paragraph(document, ", ".join(paper.keywords))

    for section in paper.sections:
        document.add_heading(section.heading, level=1)
        _add_text_paragraph(document, section.content)

    if paper.references:
        document.add_heading("References", level=1)
        for reference in paper.references:
            paragraph = document.add_paragraph(reference.text)
            paragraph.paragraph_format.left_indent = Inches(0.25)
            paragraph.paragraph_format.first_line_indent = Inches(-0.25)

    return document


def _add_text_paragraph(document: Any, text: str) -> None:
    paragraph = document.add_paragraph()
    lines = text.split("\n")
    for index, line in enumerate(lines):
        if line:
            paragraph.add_run(line)
        if index < len(lines) - 1:
            paragraph.add_run().add_break(WD_BREAK.LINE)
