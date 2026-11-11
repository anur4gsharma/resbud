"""Academic Markdown-to-Document translation engine for DOCX and PDF compilation.

Provides a robust, token-based conversion layer separating structural document models
from Markdown prose, enforcing hierarchical section numbering, authentic typographic styles,
Unicode font embedding, and zero Markdown token leakage.
"""

from __future__ import annotations

import base64
from dataclasses import dataclass, field
import html
import io
from pathlib import Path
import re
from typing import Any, Literal

from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor
import math2docx
from PIL import Image as PILImage
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.pdfmetrics import registerFontFamily
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Paragraph, Preformatted, Spacer, Table, TableStyle
from reportlab.platypus import Image as RLImage

from resbud_api.services.chart_generator import render_academic_chart_from_spec

# --- Data Structures for Parsed Markdown Elements ---


@dataclass
class InlineSpan:
    kind: Literal["text", "bold", "italic", "bold_italic", "code", "link", "math"]
    content: str
    target: str | None = None  # for links


@dataclass
class HeadingBlock:
    level: int  # 2, 3, 4
    title: str


@dataclass
class ParagraphBlock:
    spans: list[InlineSpan]


@dataclass
class ListBlock:
    ordered: bool
    items: list[list[InlineSpan]]
    start_num: int = 1


@dataclass
class BlockquoteBlock:
    spans: list[InlineSpan]


@dataclass
class CodeBlock:
    language: str
    code: str


@dataclass
class TableBlock:
    headers: list[str]
    rows: list[list[str]]


@dataclass
class FigureBlock:
    caption: str
    src: str


@dataclass
class ChartBlock:
    spec: str


@dataclass
class MathBlock:
    latex: str


MarkdownBlock = (
    HeadingBlock
    | ParagraphBlock
    | ListBlock
    | BlockquoteBlock
    | CodeBlock
    | TableBlock
    | FigureBlock
    | ChartBlock
    | MathBlock
)

# --- Inline Token Regex ---

INLINE_TOKEN_RE = re.compile(
    r"(?P<math>\$\$[\s\S]*?\$\$|\\\[[\s\S]*?\\\]|\$[^$\n]+\$|\\\([\s\S]*?\\\))|"
    r"(?P<code>`[^`\n]+`)|"
    r"(?P<bold_italic>\*\*\*[^*]+\*\*\*|___[^_]+___)|"
    r"(?P<bold>\*\*[^*]+\*\*|__[^_]+__)|"
    r"(?P<italic>\*[^*\n]+\*|(?<=\s)_[^_\n]+_(?=\s|[.,;:!?]|$))|"
    r"(?P<link>\[[^\]]+\]\([^)]+\))"
)

BLOCK_MATH_PATTERN = re.compile(
    r"^(?:\$\$([\s\S]*?)\$\$|\\\[([\s\S]*?)\\\]|\\begin\{(?:equation|align|gather)\*?}([\s\S]*?)\\end\{(?:equation|align|gather)\*?})$"
)


def parse_inline_spans(text: str) -> list[InlineSpan]:
    """Parse text into typed inline formatting spans without dropping content."""
    spans: list[InlineSpan] = []
    last_idx = 0
    for match in INLINE_TOKEN_RE.finditer(text):
        start, end = match.span()
        if start > last_idx:
            plain = text[last_idx:start]
            if plain:
                spans.append(InlineSpan(kind="text", content=plain))

        kind = match.lastgroup
        raw = match.group(0)
        if kind == "math":
            clean = raw
            if (raw.startswith("$$") and raw.endswith("$$")) or (
                raw.startswith(r"\[") and raw.endswith(r"\]")
            ):
                clean = raw[2:-2].strip()
            elif (raw.startswith("$") and raw.endswith("$")) or (
                raw.startswith(r"\(") and raw.endswith(r"\)")
            ):
                clean = raw[1:-1].strip() if raw.startswith("$") else raw[2:-2].strip()
            spans.append(InlineSpan(kind="math", content=clean))
        elif kind == "code":
            spans.append(InlineSpan(kind="code", content=raw[1:-1]))
        elif kind == "bold_italic":
            spans.append(InlineSpan(kind="bold_italic", content=raw[3:-3]))
        elif kind == "bold":
            spans.append(InlineSpan(kind="bold", content=raw[2:-2]))
        elif kind == "italic":
            spans.append(InlineSpan(kind="italic", content=raw[1:-1]))
        elif kind == "link":
            m = re.match(r"\[([^\]]+)\]\(([^)]+)\)", raw)
            if m:
                spans.append(InlineSpan(kind="link", content=m.group(1), target=m.group(2)))
            else:
                spans.append(InlineSpan(kind="text", content=raw))
        last_idx = end

    if last_idx < len(text):
        spans.append(InlineSpan(kind="text", content=text[last_idx:]))
    return spans


def clean_heading_text(raw_heading: str) -> str:
    """Strip Markdown hashes and existing manual hierarchical numbering from a heading string."""
    cleaned = raw_heading.strip()
    # Strip leading markdown hashes (#, ##, ###, ####)
    cleaned = re.sub(r"^#+\s*", "", cleaned).strip()
    # Strip leading manual hierarchical numbers like 1, 1., 1.1, 1.1., 1.1.1, etc.
    cleaned = re.sub(r"^\d+(?:\.\d+)*\.?\s*", "", cleaned).strip()
    return cleaned


def format_hierarchical_heading(title: str, indices: list[int]) -> str:
    """Format a heading with consistent hierarchical numbering (e.g. 1. Introduction, 1.1 Background)."""
    clean = clean_heading_text(title)
    if not indices:
        return clean
    if len(indices) == 1:
        return f"{indices[0]}. {clean}"
    prefix = ".".join(str(i) for i in indices)
    return f"{prefix} {clean}"


def parse_markdown_blocks(content: str) -> list[MarkdownBlock]:
    """Parse section Markdown content into structured academic document blocks."""
    blocks: list[MarkdownBlock] = []
    lines = content.split("\n")
    i = 0
    n = len(lines)

    while i < n:
        line = lines[i]
        trimmed = line.strip()

        if not trimmed:
            i += 1
            continue

        # 1. Fenced Code Block (```lang ... ```)
        if trimmed.startswith("```"):
            fence = trimmed[:3]
            lang = trimmed[3:].strip()
            code_lines: list[str] = []
            i += 1
            while i < n and not lines[i].strip().startswith("```"):
                code_lines.append(lines[i])
                i += 1
            if i < n:
                i += 1  # skip closing fence

            code_text = "\n".join(code_lines)
            if lang.lower() == "chart":
                blocks.append(ChartBlock(spec=code_text))
            else:
                blocks.append(CodeBlock(language=lang, code=code_text))
            continue

        # 2. Block Math ($$...$$ or \[...\])
        if BLOCK_MATH_PATTERN.match(trimmed) or (
            trimmed.startswith("$$") and trimmed.endswith("$$") and len(trimmed) > 4
        ):
            clean_math = trimmed
            if trimmed.startswith("$$") and trimmed.endswith("$$"):
                clean_math = trimmed[2:-2].strip()
            elif trimmed.startswith(r"\[") and trimmed.endswith(r"\]"):
                clean_math = trimmed[2:-2].strip()
            blocks.append(MathBlock(latex=clean_math))
            i += 1
            continue

        # Multiline block math starting with $$ or \[
        if trimmed in ("$$", r"\["):
            closing = "$$" if trimmed == "$$" else r"\]"
            math_lines: list[str] = []
            i += 1
            while i < n and lines[i].strip() != closing:
                math_lines.append(lines[i])
                i += 1
            if i < n:
                i += 1
            blocks.append(MathBlock(latex="\n".join(math_lines).strip()))
            continue

        # 3. Figure (![caption](src))
        fig_match = re.match(r"^!\[(.*?)\]\((.*?)\)$", trimmed)
        if fig_match:
            blocks.append(FigureBlock(caption=fig_match.group(1), src=fig_match.group(2)))
            i += 1
            continue

        # 4. Markdown Table (| header | header |)
        if trimmed.startswith("|") and trimmed.endswith("|"):
            table_lines: list[str] = []
            while i < n and lines[i].strip().startswith("|") and lines[i].strip().endswith("|"):
                table_lines.append(lines[i].strip())
                i += 1
            if len(table_lines) >= 2:
                # Parse headers and rows
                raw_rows: list[list[str]] = []
                for tline in table_lines:
                    if "---" in tline:
                        continue
                    cells = [c.strip() for c in tline.strip("|").split("|")]
                    raw_rows.append(cells)
                if raw_rows:
                    headers = raw_rows[0]
                    rows = raw_rows[1:]
                    blocks.append(TableBlock(headers=headers, rows=rows))
                continue

        # 5. Headings (### Subsection, #### Sub-subsection)
        heading_match = re.match(r"^(#{1,6})\s+(.*)$", trimmed)
        if heading_match:
            hash_count = len(heading_match.group(1))
            heading_title = clean_heading_text(heading_match.group(2))
            level = 2 if hash_count <= 3 else 3
            blocks.append(HeadingBlock(level=level, title=heading_title))
            i += 1
            continue

        # 6. Blockquote (> quote)
        if trimmed.startswith(">"):
            quote_lines: list[str] = []
            while i < n and lines[i].strip().startswith(">"):
                quote_lines.append(re.sub(r"^>\s*", "", lines[i].strip()))
                i += 1
            quote_text = " ".join(quote_lines)
            blocks.append(BlockquoteBlock(spans=parse_inline_spans(quote_text)))
            continue

        # 7. Unordered List (* item, - item, + item)
        if re.match(r"^[*+-]\s+", trimmed):
            list_items: list[list[InlineSpan]] = []
            while i < n and re.match(r"^[*+-]\s+", lines[i].strip()):
                item_text = re.sub(r"^[*+-]\s+", "", lines[i].strip())
                list_items.append(parse_inline_spans(item_text))
                i += 1
            blocks.append(ListBlock(ordered=False, items=list_items))
            continue

        # 8. Ordered List (1. item, 2. item)
        if re.match(r"^\d+\.\s+", trimmed):
            list_items = []
            start_num = int(re.match(r"^(\d+)\.", trimmed).group(1))
            while i < n and re.match(r"^\d+\.\s+", lines[i].strip()):
                item_text = re.sub(r"^\d+\.\s+", "", lines[i].strip())
                list_items.append(parse_inline_spans(item_text))
                i += 1
            blocks.append(ListBlock(ordered=True, items=list_items, start_num=start_num))
            continue

        # 9. Regular Paragraph (accumulate until blank line or next block element)
        para_lines: list[str] = []
        while (
            i < n
            and lines[i].strip()
            and not lines[i].strip().startswith("```")
            and not lines[i].strip().startswith("#")
            and not lines[i].strip().startswith(">")
            and not (lines[i].strip().startswith("|") and lines[i].strip().endswith("|"))
            and not re.match(r"^[*+-]\s+", lines[i].strip())
            and not re.match(r"^\d+\.\s+", lines[i].strip())
            and not BLOCK_MATH_PATTERN.match(lines[i].strip())
            and not lines[i].strip() in ("$$", r"\[")
        ):
            para_lines.append(lines[i].strip())
            i += 1

        if para_lines:
            para_text = " ".join(para_lines)
            blocks.append(ParagraphBlock(spans=parse_inline_spans(para_text)))

    return blocks


# --- DOCX Rendering Support ---


def render_blocks_to_docx(
    document: Any,
    blocks: list[MarkdownBlock],
    section_index: int,
    numbered: bool = True,
    academic_font: str = "Times New Roman",
) -> None:
    """Render structured Markdown blocks into a Word document with hierarchical numbering."""
    sub_index = 0
    subsub_index = 0
    pure_black = RGBColor(0, 0, 0)

    for block in blocks:
        if isinstance(block, HeadingBlock):
            if block.level == 2:
                sub_index += 1
                subsub_index = 0
                title_text = (
                    f"{section_index}.{sub_index} {block.title}" if numbered else block.title
                )
                h_para = document.add_heading(title_text, level=2)
                h_para.paragraph_format.space_before = Pt(10)
                h_para.paragraph_format.space_after = Pt(3)
                h_para.paragraph_format.keep_with_next = True
                _ensure_runs_font(h_para, academic_font, bold=True, size_pt=11)
            else:
                subsub_index += 1
                title_text = (
                    f"{section_index}.{sub_index}.{subsub_index} {block.title}"
                    if numbered
                    else block.title
                )
                h_para = document.add_heading(title_text, level=3)
                h_para.paragraph_format.space_before = Pt(8)
                h_para.paragraph_format.space_after = Pt(2)
                h_para.paragraph_format.keep_with_next = True
                _ensure_runs_font(h_para, academic_font, bold=True, italic=True, size_pt=10.5)

        elif isinstance(block, ParagraphBlock):
            p = document.add_paragraph()
            p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
            p.paragraph_format.line_spacing = 1.15
            p.paragraph_format.space_after = Pt(6)
            _render_spans_to_docx_paragraph(p, block.spans, academic_font)

        elif isinstance(block, ListBlock):
            style_name = "List Number" if block.ordered else "List Bullet"
            for item_idx, item_spans in enumerate(block.items, start=block.start_num):
                p = document.add_paragraph(style=style_name)
                p.paragraph_format.space_after = Pt(2)
                p.paragraph_format.space_before = Pt(1)
                p.paragraph_format.line_spacing = 1.1
                _render_spans_to_docx_paragraph(p, item_spans, academic_font)

        elif isinstance(block, BlockquoteBlock):
            p = document.add_paragraph()
            p.paragraph_format.left_indent = Inches(0.4)
            p.paragraph_format.right_indent = Inches(0.4)
            p.paragraph_format.line_spacing = 1.15
            p.paragraph_format.space_before = Pt(4)
            p.paragraph_format.space_after = Pt(6)
            _render_spans_to_docx_paragraph(p, block.spans, academic_font, force_italic=True)

        elif isinstance(block, CodeBlock):
            p = document.add_paragraph()
            p.paragraph_format.left_indent = Inches(0.25)
            p.paragraph_format.space_before = Pt(4)
            p.paragraph_format.space_after = Pt(6)
            run = p.add_run(block.code)
            run.font.name = "Consolas"
            run.font.size = Pt(9.0)
            run.font.color.rgb = RGBColor(0x22, 0x22, 0x22)

        elif isinstance(block, MathBlock):
            p = document.add_paragraph()
            p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
            p.paragraph_format.space_before = Pt(8)
            p.paragraph_format.space_after = Pt(8)
            try:
                math2docx.add_math(p, block.latex)
            except Exception:
                run = p.add_run(block.latex)
                run.font.name = academic_font
                run.font.italic = True
                run.font.color.rgb = pure_black

        elif isinstance(block, TableBlock):
            _render_table_to_docx(document, block.headers, block.rows, academic_font)

        elif isinstance(block, FigureBlock):
            _render_figure_src_to_docx(document, block.src, block.caption, academic_font)

        elif isinstance(block, ChartBlock):
            chart_bytes = render_academic_chart_from_spec(block.spec)
            if chart_bytes:
                caption = "Figure: Quantitative Benchmark Results"
                for c_line in block.spec.split("\n"):
                    if c_line.strip().lower().startswith("title:"):
                        caption = f"Figure: {c_line.split(':', 1)[1].strip()}"
                        break
                _render_figure_bytes_to_docx(document, chart_bytes, caption, academic_font)


def _render_spans_to_docx_paragraph(
    paragraph: Any,
    spans: list[InlineSpan],
    font_name: str,
    force_italic: bool = False,
) -> None:
    pure_black = RGBColor(0, 0, 0)
    for span in spans:
        if span.kind == "math":
            try:
                math2docx.add_math(paragraph, span.content)
                continue
            except Exception:
                run = paragraph.add_run(span.content)
                run.font.name = font_name
                run.font.italic = True
                run.font.color.rgb = pure_black
                continue

        run = paragraph.add_run(span.content)
        run.font.name = "Consolas" if span.kind == "code" else font_name
        run.font.size = Pt(9.5) if span.kind == "code" else Pt(10.5)
        run.font.color.rgb = pure_black

        if span.kind in ("bold", "bold_italic"):
            run.font.bold = True
        if span.kind in ("italic", "bold_italic") or force_italic:
            run.font.italic = True


def _ensure_runs_font(
    paragraph: Any,
    font_name: str,
    bold: bool = False,
    italic: bool = False,
    size_pt: float = 11,
) -> None:
    pure_black = RGBColor(0, 0, 0)
    for run in paragraph.runs:
        run.font.name = font_name
        run.font.color.rgb = pure_black
        run.font.bold = bold
        run.font.italic = italic
        run.font.size = Pt(size_pt)


def _render_table_to_docx(
    document: Any,
    headers: list[str],
    rows: list[list[str]],
    font_name: str,
) -> None:
    try:
        all_rows = [headers] + rows
        num_cols = max(len(r) for r in all_rows)
        table = document.add_table(rows=len(all_rows), cols=num_cols)
        table.style = "Table Grid"
        for r_idx, row in enumerate(all_rows):
            for c_idx, cell_text in enumerate(row):
                if c_idx < num_cols:
                    cell = table.cell(r_idx, c_idx)
                    cell.text = cell_text
                    for p in cell.paragraphs:
                        p.paragraph_format.space_before = Pt(2)
                        p.paragraph_format.space_after = Pt(2)
                        p.paragraph_format.line_spacing = 1.05
                        for r in p.runs:
                            r.font.name = font_name
                            r.font.size = Pt(9.5)
                            r.font.color.rgb = RGBColor(0, 0, 0)
                            if r_idx == 0:
                                r.font.bold = True
        space_p = document.add_paragraph()
        space_p.paragraph_format.space_after = Pt(4)
    except Exception:
        pass


def _render_figure_bytes_to_docx(
    document: Any,
    img_bytes: bytes,
    caption: str,
    font_name: str,
) -> None:
    try:
        target_w, target_h = 5.2, 3.0
        try:
            with PILImage.open(io.BytesIO(img_bytes)) as pil_img:
                orig_w, orig_h = pil_img.size
                if orig_w > 0:
                    aspect = orig_h / orig_w
                    target_w = min(5.5, max(2.5, orig_w / 150.0))
                    target_h = target_w * aspect
                    if target_h > 4.5:
                        target_h = 4.5
                        target_w = target_h / aspect
        except Exception:
            pass

        p = document.add_paragraph()
        p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.space_before = Pt(8)
        p.paragraph_format.space_after = Pt(4)
        run = p.add_run()
        run.add_picture(io.BytesIO(img_bytes), width=Inches(target_w), height=Inches(target_h))

        caption_p = document.add_paragraph()
        caption_p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
        caption_p.paragraph_format.space_before = Pt(2)
        caption_p.paragraph_format.space_after = Pt(12)
        c_run = caption_p.add_run(caption)
        c_run.font.name = font_name
        c_run.font.size = Pt(9.5)
        c_run.font.italic = True
        c_run.font.color.rgb = RGBColor(0x33, 0x33, 0x33)
    except Exception:
        p = document.add_paragraph()
        p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
        run = p.add_run(f"[{caption}]")
        run.font.name = font_name
        run.font.italic = True


def _render_figure_src_to_docx(document: Any, img_src: str, caption: str, font_name: str) -> None:
    try:
        raw_b64 = img_src.strip()
        if "base64," in raw_b64:
            raw_b64 = raw_b64.split("base64,", 1)[1]
        raw_b64 = re.sub(r"\s+", "", raw_b64)
        img_bytes = base64.b64decode(raw_b64)
        _render_figure_bytes_to_docx(document, img_bytes, caption, font_name)
    except Exception:
        p = document.add_paragraph()
        p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
        run = p.add_run(f"[{caption}]")
        run.font.name = font_name
        run.font.italic = True


# --- PDF Rendering Support & TrueType Font Discovery ---

_REGISTERED_PDF_FONT: str | None = None


def setup_reportlab_academic_fonts() -> str:
    """Locate and register TrueType Unicode serif fonts with ReportLab.

    Returns the registered font family name ('AcademicSerif' or 'Times-Roman').
    """
    global _REGISTERED_PDF_FONT
    if _REGISTERED_PDF_FONT is not None:
        return _REGISTERED_PDF_FONT

    font_candidates = [
        # Liberation Serif (Standard drop-in metric replacement for Times New Roman on Linux)
        (
            "/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSerif-Bold.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSerif-Italic.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSerif-BoldItalic.ttf",
        ),
        # DejaVu Serif
        (
            "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Italic.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSerif-BoldItalic.ttf",
        ),
        # FreeSerif
        (
            "/usr/share/fonts/truetype/freefont/FreeSerif.ttf",
            "/usr/share/fonts/truetype/freefont/FreeSerifBold.ttf",
            "/usr/share/fonts/truetype/freefont/FreeSerifItalic.ttf",
            "/usr/share/fonts/truetype/freefont/FreeSerifBoldItalic.ttf",
        ),
    ]

    for reg, bold, italic, bold_italic in font_candidates:
        if (
            Path(reg).is_file()
            and Path(bold).is_file()
            and Path(italic).is_file()
            and Path(bold_italic).is_file()
        ):
            try:
                pdfmetrics.registerFont(TTFont("AcademicSerif", reg))
                pdfmetrics.registerFont(TTFont("AcademicSerif-Bold", bold))
                pdfmetrics.registerFont(TTFont("AcademicSerif-Italic", italic))
                pdfmetrics.registerFont(TTFont("AcademicSerif-BoldItalic", bold_italic))
                registerFontFamily(
                    "AcademicSerif",
                    normal="AcademicSerif",
                    bold="AcademicSerif-Bold",
                    italic="AcademicSerif-Italic",
                    boldItalic="AcademicSerif-BoldItalic",
                )
                _REGISTERED_PDF_FONT = "AcademicSerif"
                return "AcademicSerif"
            except Exception:
                continue

    _REGISTERED_PDF_FONT = "Times-Roman"
    return "Times-Roman"


def spans_to_reportlab_html(spans: list[InlineSpan]) -> str:
    """Convert typed inline spans to safe ReportLab XML/HTML markup."""
    parts: list[str] = []
    for span in spans:
        escaped = html.escape(span.content)
        if span.kind == "math":
            parts.append(f"<i>{escaped}</i>")
        elif span.kind == "code":
            parts.append(f"<code>{escaped}</code>")
        elif span.kind == "bold":
            parts.append(f"<b>{escaped}</b>")
        elif span.kind == "italic":
            parts.append(f"<i>{escaped}</i>")
        elif span.kind == "bold_italic":
            parts.append(f"<b><i>{escaped}</i></b>")
        elif span.kind == "link":
            parts.append(f"<u>{escaped}</u>")
        else:
            parts.append(escaped)
    return "".join(parts)


def render_blocks_to_pdf(
    story: list[Any],
    blocks: list[MarkdownBlock],
    styles: dict[str, ParagraphStyle],
    section_index: int,
    numbered: bool = True,
) -> None:
    """Render structured Markdown blocks into a ReportLab PDF story with hierarchical numbering."""
    sub_index = 0
    subsub_index = 0

    for block in blocks:
        if isinstance(block, HeadingBlock):
            if block.level == 2:
                sub_index += 1
                subsub_index = 0
                title_text = (
                    f"{section_index}.{sub_index} {block.title}" if numbered else block.title
                )
                story.append(Paragraph(html.escape(title_text), styles["Heading2"]))
            else:
                subsub_index += 1
                title_text = (
                    f"{section_index}.{sub_index}.{subsub_index} {block.title}"
                    if numbered
                    else block.title
                )
                story.append(Paragraph(html.escape(title_text), styles["Heading3"]))

        elif isinstance(block, ParagraphBlock):
            html_text = spans_to_reportlab_html(block.spans)
            story.append(Paragraph(html_text, styles["Body"]))

        elif isinstance(block, ListBlock):
            for item_idx, item_spans in enumerate(block.items, start=block.start_num):
                item_html = spans_to_reportlab_html(item_spans)
                prefix = f"{item_idx}. " if block.ordered else "• "
                story.append(Paragraph(f"{prefix}{item_html}", styles["ListItem"]))

        elif isinstance(block, BlockquoteBlock):
            html_text = spans_to_reportlab_html(block.spans)
            story.append(Paragraph(f"<i>{html_text}</i>", styles["Blockquote"]))

        elif isinstance(block, CodeBlock):
            story.append(Preformatted(block.code, styles["CodeBlock"]))

        elif isinstance(block, MathBlock):
            story.append(Paragraph(f"<i>{html.escape(block.latex)}</i>", styles["MathBlock"]))

        elif isinstance(block, TableBlock):
            _render_table_to_pdf(story, block.headers, block.rows, styles)

        elif isinstance(block, FigureBlock):
            _render_figure_src_to_pdf(story, block.src, block.caption, styles)

        elif isinstance(block, ChartBlock):
            chart_bytes = render_academic_chart_from_spec(block.spec)
            if chart_bytes:
                caption = "Figure: Quantitative Results"
                for c_line in block.spec.split("\n"):
                    if c_line.strip().lower().startswith("title:"):
                        caption = f"Figure: {c_line.split(':', 1)[1].strip()}"
                        break
                _render_figure_bytes_to_pdf(story, chart_bytes, caption, styles)


def _render_table_to_pdf(
    story: list[Any],
    headers: list[str],
    rows: list[list[str]],
    styles: dict[str, ParagraphStyle],
) -> None:
    try:
        all_rows = [headers] + rows
        data = [
            [
                Paragraph(
                    f"<b>{html.escape(cell)}</b>" if r_idx == 0 else html.escape(cell),
                    styles["TableCell"],
                )
                for cell in row
            ]
            for r_idx, row in enumerate(all_rows)
        ]
        t = Table(data, hAlign="CENTER")
        t.setStyle(
            TableStyle(
                [
                    ("GRID", (0, 0), (-1, -1), 0.5, colors.black),
                    ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#F0F0F0")),
                    ("TOPPADDING", (0, 0), (-1, -1), 3),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
                ]
            )
        )
        story.append(Spacer(1, 4))
        story.append(t)
        story.append(Spacer(1, 6))
    except Exception:
        pass


def _render_figure_bytes_to_pdf(
    story: list[Any],
    img_bytes: bytes,
    caption: str,
    styles: dict[str, ParagraphStyle],
) -> None:
    try:
        target_w, target_h = 360, 200
        try:
            with PILImage.open(io.BytesIO(img_bytes)) as pil_img:
                w, h = pil_img.size
                if w > 0:
                    aspect = h / w
                    target_w = min(420, max(200, w * 0.5))
                    target_h = target_w * aspect
                    if target_h > 280:
                        target_h = 280
                        target_w = target_h / aspect
        except Exception:
            pass

        img_flowable = RLImage(io.BytesIO(img_bytes), width=target_w, height=target_h)
        story.append(Spacer(1, 6))
        story.append(img_flowable)
        story.append(Paragraph(html.escape(caption), styles["Caption"]))
        story.append(Spacer(1, 6))
    except Exception:
        story.append(Paragraph(f"<i>[{html.escape(caption)}]</i>", styles["Caption"]))


def _render_figure_src_to_pdf(
    story: list[Any],
    img_src: str,
    caption: str,
    styles: dict[str, ParagraphStyle],
) -> None:
    try:
        raw_b64 = img_src.strip()
        if "base64," in raw_b64:
            raw_b64 = raw_b64.split("base64,", 1)[1]
        raw_b64 = re.sub(r"\s+", "", raw_b64)
        img_bytes = base64.b64decode(raw_b64)
        _render_figure_bytes_to_pdf(story, img_bytes, caption, styles)
    except Exception:
        story.append(Paragraph(f"<i>[{html.escape(caption)}]</i>", styles["Caption"]))
