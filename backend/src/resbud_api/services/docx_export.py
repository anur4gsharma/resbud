"""In-memory DOCX rendering for a validated current paper draft."""

from __future__ import annotations

import base64
import logging
import re
import unicodedata
from io import BytesIO
from pathlib import Path
from typing import Any

import math2docx
from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor
from PIL import Image as PILImage

from resbud_api.core.errors import ResbudError
from resbud_api.domain.models import PaperDraft
from resbud_api.services.chart_generator import render_academic_chart_from_spec
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
        target_w = 5.2
        target_h = 3.0
        try:
            with PILImage.open(BytesIO(img_bytes)) as pil_img:
                orig_w, orig_h = pil_img.size
                if orig_w > 0:
                    aspect = orig_h / orig_w
                    target_w = min(5.5, max(2.5, orig_w / 150.0))
                    target_h = target_w * aspect
                    if target_h > 4.5:
                        target_h = 4.5
                        target_w = target_h / aspect
        except Exception as exc:
            logger.warning(
                "Failed to determine chart image dimensions, using fallback dimensions: %s", exc
            )

        p = document.add_paragraph()
        p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.space_before = Pt(8)
        p.paragraph_format.space_after = Pt(4)
        run = p.add_run()
        run.add_picture(BytesIO(img_bytes), width=Inches(target_w), height=Inches(target_h))

        caption_p = document.add_paragraph()
        caption_p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
        caption_p.paragraph_format.space_before = Pt(2)
        caption_p.paragraph_format.space_after = Pt(12)
        c_run = caption_p.add_run(caption)
        c_run.font.name = "Times New Roman"
        c_run.font.size = Pt(9.5)
        c_run.font.italic = True
        c_run.font.color.rgb = RGBColor(0x33, 0x33, 0x33)
    except Exception:
        p = document.add_paragraph()
        p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
        run = p.add_run(f"[{caption}]")
        run.font.name = "Times New Roman"
        run.font.italic = True


def _insert_figure_from_src(document: Any, img_src: str, caption: str) -> None:
    try:
        raw_b64 = img_src.strip()
        if "base64," in raw_b64:
            raw_b64 = raw_b64.split("base64,", 1)[1]
        raw_b64 = re.sub(r"\s+", "", raw_b64)
        img_bytes = base64.b64decode(raw_b64)

        target_w = 5.2
        target_h = 3.2
        try:
            with PILImage.open(BytesIO(img_bytes)) as pil_img:
                orig_w, orig_h = pil_img.size
                if orig_w > 0:
                    aspect = orig_h / orig_w
                    target_w = min(5.5, max(2.0, orig_w / 96.0))
                    target_h = target_w * aspect
                    if target_h > 4.5:
                        target_h = 4.5
                        target_w = target_h / aspect
        except Exception as exc:
            logger.warning(
                "Failed to determine figure image dimensions, using fallback dimensions: %s", exc
            )

        p = document.add_paragraph()
        p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.space_before = Pt(8)
        p.paragraph_format.space_after = Pt(4)
        run = p.add_run()
        run.add_picture(BytesIO(img_bytes), width=Inches(target_w), height=Inches(target_h))

        caption_p = document.add_paragraph()
        caption_p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
        caption_p.paragraph_format.space_before = Pt(2)
        caption_p.paragraph_format.space_after = Pt(12)
        c_run = caption_p.add_run(caption)
        c_run.font.name = "Times New Roman"
        c_run.font.size = Pt(9.5)
        c_run.font.italic = True
        c_run.font.color.rgb = RGBColor(0x33, 0x33, 0x33)
    except Exception:
        p = document.add_paragraph()
        p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.space_before = Pt(6)
        p.paragraph_format.space_after = Pt(6)
        run = p.add_run(f"[{caption}]")
        run.font.name = "Times New Roman"
        run.font.italic = True
        run.font.color.rgb = RGBColor(0x55, 0x55, 0x55)


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
                    "Failed to render mathematical formula into docx, falling back to raw text: %s", exc
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
