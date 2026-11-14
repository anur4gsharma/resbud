"""Academic Markdown-to-Document translation engine for DOCX and PDF compilation.

Provides a robust, token-based conversion layer separating structural document models
from Markdown prose, enforcing hierarchical section numbering, authentic typographic styles,
Unicode font embedding, and zero Markdown token leakage.
"""

from __future__ import annotations

import base64
import html
import io
import logging
import os
import re
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Literal

import latex2mathml.converter
import math2docx

# fixmyslop-ignore[deps/phantom-import] Top-level import provided by mathml2omml-as package
import mathml2omml
import matplotlib
import matplotlib.pyplot as plt

matplotlib.use("Agg")
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import parse_xml
from docx.shared import Inches, Pt, RGBColor
from PIL import Image as PILImage
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.pdfmetrics import registerFontFamily
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Image as RLImage
from reportlab.platypus import Paragraph, Preformatted, Spacer, Table, TableStyle

from resbud_api.services.chart_generator import render_academic_chart_from_spec

logger = logging.getLogger(__name__)

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
class EquationBlockNode:
    latex: str
    display_type: Literal["display", "extracted_inline", "environment"] = "display"
    equation_id: str | None = None
    normalized_latex: str | None = None
    rendering_status: Literal["ok", "warning", "error"] = "ok"
    validation_error: str | None = None


# Backward-compatible alias for existing callers
MathBlock = EquationBlockNode

# Canonical AST aliases
ParagraphNode = ParagraphBlock
HeadingNode = HeadingBlock
ListNode = ListBlock
TableNode = TableBlock
FigureNode = FigureBlock
ChartNode = ChartBlock
CodeBlockNode = CodeBlock
BlockquoteNode = BlockquoteBlock


MarkdownBlock = (
    HeadingBlock
    | ParagraphBlock
    | ListBlock
    | BlockquoteBlock
    | CodeBlock
    | TableBlock
    | FigureBlock
    | ChartBlock
    | EquationBlockNode
)

# --- Inline Token Regex ---

INLINE_TOKEN_RE = re.compile(
    r"(?P<code>`[^`\n]+`)|"
    r"(?P<escaped_dollar>\\\$)|"
    r"(?P<math_display>\$\$[\s\S]*?\$\$|\\\[[\s\S]*?\\\])|"
    r"(?P<math_paren>\\\([\s\S]*?\\\))|"
    r"(?P<math_dollar>(?<!\\)\$(?!\s)(?!\d+(?:[.,]\d+)?(?:\s|[.,;:!?]|$))((?:[^$\n\\]|\\.)+?)(?<!\s)\$(?!\d))|"
    r"(?P<bold_italic>\*\*\*[^*]+\*\*\*|___[^_]+___)|"
    r"(?P<bold>\*\*[^*]+\*\*|__[^_]+__)|"
    r"(?P<italic>\*[^*\n]+\*|(?<=\s)_[^_\n]+_(?=\s|[.,;:!?]|$))|"
    r"(?P<link>\[[^\]]+\]\([^)]+\))"
)

BLOCK_MATH_PATTERN = re.compile(
    r"^(?:\$\$([\s\S]*?)\$\$|\\\[([\s\S]*?)\\\]|\\begin\{(?:equation|align|aligned|gather|matrix|pmatrix|bmatrix|vmatrix|cases)\*?}([\s\S]*?)\\end\{(?:equation|align|aligned|gather|matrix|pmatrix|bmatrix|vmatrix|cases)\*?})$"
)

MATH_EXTRACT_RE = re.compile(
    r"(?P<code>`[^`\n]+`)|"
    r"(?P<escaped_dollar>\\\$)|"
    r"(?P<math_env>\\begin\{(?:equation|align|aligned|gather|matrix|pmatrix|bmatrix|vmatrix|cases)\*?\}[\s\S]*?\\end\{(?:equation|align|aligned|gather|matrix|pmatrix|bmatrix|vmatrix|cases)\*?\})|"
    r"(?P<math_display>\$\$[\s\S]*?\$\$|\\\[[\s\S]*?\\\])|"
    r"(?P<math_paren>\\\([\s\S]*?\\\))|"
    r"(?P<math_dollar>(?<!\\)\$(?!\s)(?!\d+(?:[.,]\d+)?(?:\s|[.,;:!?]|$))((?:[^$\n\\]|\\.)+?)(?<!\s)\$(?!\d))"
)


def clean_math_source(raw: str) -> str:
    """Strip outer delimiters while preserving inner LaTeX source."""
    c = raw.strip()
    if (c.startswith("$$") and c.endswith("$$") and len(c) >= 4) or (
        c.startswith(r"\[") and c.endswith(r"\]") and len(c) >= 4
    ):
        return c[2:-2].strip()
    if c.startswith(r"\(") and c.endswith(r"\)") and len(c) >= 4:
        return c[2:-2].strip()
    if c.startswith("$") and c.endswith("$") and len(c) >= 2:
        return c[1:-1].strip()
    return c


def normalize_math_latex(latex_str: str) -> str:
    """Normalize LaTeX expression for broad compatibility."""
    normalized = latex_str.strip()
    if "&" in normalized and ("aligned" in normalized or "align" in normalized):
        normalized = re.sub(r"\\begin\{(?:align|aligned)\*?\}", r"\\begin{matrix}", normalized)
        normalized = re.sub(r"\\end\{(?:align|aligned)\*?\}", r"\\end{matrix}", normalized)
        normalized = re.sub(r"&=", "=", normalized)
    return normalized


def validate_math_latex(latex_str: str) -> tuple[Literal["ok", "warning", "error"], str | None]:
    """Validate LaTeX mathematical syntax against standard math engines."""
    clean = latex_str.strip()
    if not clean:
        return "error", "Empty mathematical expression"

    brace_depth = 0
    for char in clean:
        if char == "{":
            brace_depth += 1
        elif char == "}":
            brace_depth -= 1
            if brace_depth < 0:
                return "error", "Unbalanced closing brace '}' in expression"
    if brace_depth != 0:
        return "error", f"Unclosed opening brace '{{' (unbalanced by {brace_depth})"

    if re.search(
        r"\\begin\{(?:matrix|pmatrix|bmatrix|vmatrix|cases|align|aligned|gather)\*?\}", clean
    ):
        sanitized = clean
        if "&" in sanitized and ("aligned" in sanitized or "align" in sanitized):
            sanitized = re.sub(r"\\begin\{(?:align|aligned)\*?\}", r"\\begin{matrix}", sanitized)
            sanitized = re.sub(r"\\end\{(?:align|aligned)\*?\}", r"\\end{matrix}", sanitized)
            sanitized = re.sub(r"&=", "=", sanitized)
        try:
            latex2mathml.converter.convert(sanitized)
            return "ok", None
        except Exception as e:
            return "warning", f"Unsupported environment syntax: {e}"

    try:
        from matplotlib.mathtext import MathTextParser

        mathtext_clean = clean.replace(r"\text", r"\rm").replace(r"\parallel", r"\Vert")
        parser = MathTextParser("path")
        parser.parse(f"${mathtext_clean}$")
        return "ok", None
    except Exception as e:
        return "warning", f"Unsupported mathematical syntax: {e}"


def create_equation_block_node(
    raw_latex: str,
    display_type: Literal["display", "extracted_inline", "environment"] = "display",
    equation_id: str | None = None,
) -> EquationBlockNode:
    """Factory creating an EquationBlockNode with validation and normalization."""
    clean = clean_math_source(raw_latex)
    norm = normalize_math_latex(clean)
    status, err = validate_math_latex(clean)
    return EquationBlockNode(
        latex=clean,
        display_type=display_type,
        equation_id=equation_id,
        normalized_latex=norm,
        rendering_status=status,
        validation_error=err,
    )


def clean_pre_equation_prose(text: str) -> str:
    """Format and clean prose preceding an extracted standalone equation."""
    cleaned = text.strip()
    if not cleaned or cleaned in (".", ",", ";", ":", "!", "?"):
        return ""
    cleaned = re.sub(r"[,;]+$", "", cleaned).strip()
    if re.search(
        r"\b(?:calculated|defined|written|expressed|represented|formulated|given)\s+as$",
        cleaned,
        re.IGNORECASE,
    ):
        cleaned = re.sub(r"\s+as$", " as follows:", cleaned, flags=re.IGNORECASE)
    elif re.search(r"\bas$", cleaned, re.IGNORECASE):
        cleaned = re.sub(r"\bas$", "as follows:", cleaned, flags=re.IGNORECASE)
    elif re.search(
        r"\b(?:is|given by|satisfies|satisfying|becomes|yields|minimizes the loss)$",
        cleaned,
        re.IGNORECASE,
    ):
        if not cleaned.endswith(":"):
            cleaned += ":"
    elif not cleaned.endswith((".", ":", "!", "?")):
        cleaned += ":"
    return cleaned


def clean_post_equation_prose(text: str) -> str:
    """Format and clean prose following an extracted standalone equation."""
    cleaned = text.strip()
    if not cleaned or cleaned in (".", ",", ";", ":", "!", "?"):
        return ""
    cleaned = re.sub(r"^[,\s;]+", "", cleaned).strip()
    if not cleaned or cleaned in (".", ",", ";", ":", "!", "?"):
        return ""
    if re.match(r"^where\b", cleaned, re.IGNORECASE):
        cleaned = re.sub(r"^where\b\s*", "Here, ", cleaned, flags=re.IGNORECASE)
    elif re.match(r"^in which\b", cleaned, re.IGNORECASE):
        cleaned = re.sub(r"^in which\b\s*", "In which ", cleaned, flags=re.IGNORECASE)
    elif re.match(r"^with\b", cleaned, re.IGNORECASE):
        cleaned = re.sub(r"^with\b\s*", "With ", cleaned, flags=re.IGNORECASE)
    elif cleaned and cleaned[0].islower():
        cleaned = cleaned[0].upper() + cleaned[1:]
    return cleaned


def extract_equation_blocks_from_paragraph(text: str) -> list[MarkdownBlock]:
    """Split paragraph text on all recognized mathematical expressions,

    producing alternating ParagraphBlock (pure prose) and EquationBlockNode (display math).
    Ensures zero inline math spans remain inside paragraphs.
    """
    matches = [
        m for m in MATH_EXTRACT_RE.finditer(text) if m.lastgroup not in ("code", "escaped_dollar")
    ]

    if not matches:
        return [ParagraphBlock(spans=parse_inline_spans(text.strip()))]

    blocks: list[MarkdownBlock] = []
    cursor = 0
    for i, m in enumerate(matches):
        pre_text = text[cursor : m.start()]
        if i > 0:
            cleaned_pre = clean_post_equation_prose(pre_text)
            if cleaned_pre and not cleaned_pre.endswith((".", ":", "!", "?")):
                cleaned_pre = clean_pre_equation_prose(cleaned_pre)
        else:
            cleaned_pre = clean_pre_equation_prose(pre_text)

        if cleaned_pre:
            blocks.append(ParagraphBlock(spans=parse_inline_spans(cleaned_pre)))

        raw_math = m.group(0)
        display_type: Literal["display", "extracted_inline", "environment"] = (
            "environment"
            if m.lastgroup == "math_env"
            else ("display" if m.lastgroup == "math_display" else "extracted_inline")
        )
        eq_node = create_equation_block_node(raw_math, display_type=display_type)
        blocks.append(eq_node)
        cursor = m.end()

    trailing_text = text[cursor:]
    cleaned_post = clean_post_equation_prose(trailing_text)
    if cleaned_post:
        blocks.append(ParagraphBlock(spans=parse_inline_spans(cleaned_post)))

    return blocks


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
        if kind == "escaped_dollar":
            spans.append(InlineSpan(kind="text", content="$"))
        elif kind in ("math", "math_display", "math_paren", "math_dollar"):
            clean = raw
            if (raw.startswith("$$") and raw.endswith("$$")) or (
                raw.startswith(r"\[") and raw.endswith(r"\]")
            ):
                clean = raw[2:-2].strip()
            elif raw.startswith(r"\(") and raw.endswith(r"\)"):
                clean = raw[2:-2].strip()
            elif raw.startswith("$") and raw.endswith("$"):
                clean = raw[1:-1].strip()
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
            clean_math = clean_math_source(trimmed)
            blocks.append(create_equation_block_node(clean_math, display_type="display"))
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
            raw_math = "\n".join(math_lines).strip()
            blocks.append(create_equation_block_node(raw_math, display_type="display"))
            continue

        # Multiline block environment \begin{env} ... \end{env}
        env_match = re.match(r"^\\begin\{([a-zA-Z0-9*]+)\}", trimmed)
        if env_match:
            env_name = env_match.group(1)
            math_lines = [lines[i]]
            if not trimmed.endswith(f"\\end{{{env_name}}}"):
                i += 1
                while i < n and f"\\end{{{env_name}}}" not in lines[i]:
                    math_lines.append(lines[i])
                    i += 1
                if i < n:
                    math_lines.append(lines[i])
                    i += 1
            else:
                i += 1
            raw_math = "\n".join(math_lines).strip()
            blocks.append(create_equation_block_node(raw_math, display_type="environment"))
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
        m_list = re.match(r"^(\d+)\.\s+", trimmed)
        if m_list:
            list_items = []
            start_num = int(m_list.group(1))
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
            and not re.match(r"^\\begin\{[a-zA-Z0-9*]+\}", lines[i].strip())
            and lines[i].strip() not in ("$$", r"\[")
        ):
            para_lines.append(lines[i].strip())
            i += 1

        if para_lines:
            para_text = " ".join(para_lines)
            blocks.extend(extract_equation_blocks_from_paragraph(para_text))

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
            for _item_idx, item_spans in enumerate(block.items, start=block.start_num):
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

        elif isinstance(block, (MathBlock, EquationBlockNode)):
            p = document.add_paragraph()
            p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
            p.paragraph_format.space_before = Pt(8)
            p.paragraph_format.space_after = Pt(8)
            _render_math_to_docx(
                p,
                block.latex,
                academic_font,
                status=block.rendering_status,
                error_msg=block.validation_error,
            )

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


def _render_math_to_docx(
    paragraph: Any,
    latex_str: str,
    font_name: str,
    status: Literal["ok", "warning", "error"] = "ok",
    error_msg: str | None = None,
) -> None:
    """Render LaTeX equation into Word paragraph using native OMML, with resilient fallback."""
    clean = latex_str.strip()
    if clean.startswith("$$") and clean.endswith("$$") and len(clean) > 4:
        clean = clean[2:-2].strip()
    elif clean.startswith(r"\[") and clean.endswith(r"\]") and len(clean) > 4:
        clean = clean[2:-2].strip()
    elif clean.startswith(r"\(") and clean.endswith(r"\)") and len(clean) > 4:
        clean = clean[2:-2].strip()
    elif clean.startswith("$") and clean.endswith("$") and len(clean) > 2:
        clean = clean[1:-1].strip()

    # Pre-clean alignment tokens for latex2mathml compatibility
    sanitized = clean
    if "&" in sanitized and ("aligned" in sanitized or "align" in sanitized):
        sanitized = re.sub(r"\\begin\{(?:align|aligned)\*?\}", r"\\begin{matrix}", sanitized)
        sanitized = re.sub(r"\\end\{(?:align|aligned)\*?\}", r"\\end{matrix}", sanitized)
        sanitized = re.sub(r"&=", "=", sanitized)

    rendered_omml = False
    if status == "ok":
        try:
            mathml = latex2mathml.converter.convert(sanitized)
            mathml = mathml.replace("<mi>&</mi>", "").replace("<mi>&amp;</mi>", "")
            omml = mathml2omml.convert(mathml)
            xml = f'<p xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math">{omml}</p>'
            paragraph._p.append(parse_xml(xml)[0])
            rendered_omml = True
        except Exception as exc:
            logger.debug("Primary mathml conversion failed (%s), attempting math2docx fallback", exc)
            try:
                math2docx.add_math(paragraph, clean)
                rendered_omml = True
            except Exception as fallback_exc:
                logger.warning("math2docx fallback also failed: %s", fallback_exc)

    if not rendered_omml:
        # Fallback with visible warning if status was warning/error or rendering failed
        run = paragraph.add_run(clean)
        run.font.name = font_name
        run.font.italic = True
        run.font.color.rgb = RGBColor(0, 0, 0)

        warn_run = paragraph.add_run(" [Warning: Unsupported mathematical syntax]")
        warn_run.font.name = font_name
        warn_run.font.bold = True
        warn_run.font.color.rgb = RGBColor(0xCC, 0x00, 0x00)


def _render_spans_to_docx_paragraph(
    paragraph: Any,
    spans: list[InlineSpan],
    font_name: str,
    force_italic: bool = False,
) -> None:
    pure_black = RGBColor(0, 0, 0)
    for span in spans:
        if span.kind == "math":
            _render_math_to_docx(paragraph, span.content, font_name)
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
    except Exception as exc:
        logger.warning("Failed to render table to DOCX: %s", exc)


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
        except Exception as exc:
            logger.warning("Failed to determine figure image dimensions for DOCX, using defaults: %s", exc)

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
            except Exception as exc:
                logger.debug("Font registration failed for %s candidate, trying next: %s", reg, exc)
                continue

    _REGISTERED_PDF_FONT = "Times-Roman"
    return "Times-Roman"


_INLINE_MATH_CACHE: dict[str, str] = {}
_INLINE_MATH_DIR: tempfile.TemporaryDirectory[str] | None = None


def _get_inline_math_img_tag(latex: str) -> str:
    global _INLINE_MATH_DIR
    clean = latex.strip()
    if clean.startswith("$") and clean.endswith("$") and len(clean) > 2:
        clean = clean[1:-1].strip()
    elif clean.startswith(r"\(") and clean.endswith(r"\)") and len(clean) > 4:
        clean = clean[2:-2].strip()

    if clean in _INLINE_MATH_CACHE:
        return _INLINE_MATH_CACHE[clean]

    if _INLINE_MATH_DIR is None:
        _INLINE_MATH_DIR = tempfile.TemporaryDirectory(prefix="resbud_inline_math_")

    try:
        mathtext_str = (
            f"${clean}$" if not (clean.startswith("$") and clean.endswith("$")) else clean
        )
        fig = plt.figure()
        fig.patch.set_alpha(0.0)
        fig.text(0.5, 0.5, mathtext_str, fontsize=10, ha="center", va="center")
        buf = io.BytesIO()
        fig.savefig(
            buf, format="png", dpi=300, transparent=True, bbox_inches="tight", pad_inches=0.01
        )
        plt.close(fig)
        buf.seek(0)
        with PILImage.open(buf) as pil_img:
            w_px, h_px = pil_img.size
            w_pt = (w_px / 300.0) * 72.0
            h_pt = (h_px / 300.0) * 72.0

        file_path = os.path.join(_INLINE_MATH_DIR.name, f"math_{abs(hash(clean))}.png")
        with open(file_path, "wb") as f:
            f.write(buf.getvalue())

        valign = -2 if h_pt <= 16 else -4
        tag = f'<img src="{file_path}" width="{w_pt:.1f}" height="{h_pt:.1f}" valign="{valign}"/>'
        _INLINE_MATH_CACHE[clean] = tag
        return tag
    except Exception:
        fallback = f"<i>{html.escape(clean)}</i>"
        _INLINE_MATH_CACHE[clean] = fallback
        return fallback


def _render_math_to_pdf_flowable(
    latex: str,
    styles: dict[str, ParagraphStyle],
    status: Literal["ok", "warning", "error"] = "ok",
    error_msg: str | None = None,
) -> Any:
    """Render a LaTeX display equation into a centered high-DPI image flowable or table."""
    clean = latex.strip()
    if clean.startswith("$$") and clean.endswith("$$") and len(clean) > 4:
        clean = clean[2:-2].strip()
    elif clean.startswith(r"\[") and clean.endswith(r"\]") and len(clean) > 4:
        clean = clean[2:-2].strip()
    elif clean.startswith(r"\(") and clean.endswith(r"\)") and len(clean) > 4:
        clean = clean[2:-2].strip()
    elif clean.startswith("$") and clean.endswith("$") and len(clean) > 2:
        clean = clean[1:-1].strip()

    if status in ("warning", "error"):
        warn_text = (
            f'<font color="#CC0000"><b>[Warning: Unsupported mathematical syntax]</b></font> '
            f"<i>{html.escape(clean)}</i>"
        )
        return Paragraph(warn_text, styles["MathBlock"])

    # If it's a matrix environment like \begin{pmatrix} ... \end{pmatrix}
    m = re.search(r"\\begin\{(pmatrix|matrix|bmatrix)\}([\s\S]*?)\\end\{\1\}", clean)
    if m:
        body = m.group(2).strip()
        raw_rows = [r.strip() for r in body.split(r"\\") if r.strip()]
        if raw_rows:
            table_data = []
            matrix_cell_style = styles.get("TableCell", styles.get("Body"))
            for row in raw_rows:
                row_cells = []
                for cell in row.split("&"):
                    cell_text = cell.strip()
                    row_cells.append(
                        Paragraph(f"<i>{html.escape(cell_text)}</i>", matrix_cell_style)
                    )
                table_data.append(row_cells)
            t = Table(table_data, hAlign="CENTER")
            t.setStyle(
                TableStyle(
                    [
                        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                        ("LEFTPADDING", (0, 0), (-1, -1), 8),
                        ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                        ("TOPPADDING", (0, 0), (-1, -1), 4),
                        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
                    ]
                )
            )
            return t

    # Mathtext preprocessing
    mathtext_str = clean.replace(r"\text", r"\rm").replace(r"\parallel", r"\Vert")
    if mathtext_str.startswith(r"\begin{aligned}") and mathtext_str.endswith(r"\end{aligned}"):
        mathtext_str = mathtext_str.replace(r"\begin{aligned}", "").replace(r"\end{aligned}", "")
    mathtext_str = re.sub(r"&=", "=", mathtext_str)
    mathtext_str = re.sub(r"&", " ", mathtext_str)

    if not (mathtext_str.startswith("$") and mathtext_str.endswith("$")):
        mathtext_str = f"${mathtext_str}$"

    try:
        fig = plt.figure()
        fig.patch.set_alpha(0.0)
        fig.text(0.5, 0.5, mathtext_str, fontsize=12, ha="center", va="center")
        buf = io.BytesIO()
        fig.savefig(
            buf, format="png", dpi=300, transparent=True, bbox_inches="tight", pad_inches=0.03
        )
        plt.close(fig)
        buf.seek(0)
        with PILImage.open(buf) as pil_img:
            w_px, h_px = pil_img.size
            w_pt = (w_px / 300.0) * 72.0
            h_pt = (h_px / 300.0) * 72.0
            max_w = 460.0
            if w_pt > max_w:
                scale = max_w / w_pt
                w_pt = max_w
                h_pt = h_pt * scale
        buf.seek(0)
        img = RLImage(buf, width=w_pt, height=h_pt)
        img.hAlign = "CENTER"
        return img
    except Exception:
        warn_text = (
            f'<font color="#CC0000"><b>[Warning: Unsupported mathematical syntax]</b></font> '
            f"<i>{html.escape(clean)}</i>"
        )
        return Paragraph(warn_text, styles["MathBlock"])


def spans_to_reportlab_html(spans: list[InlineSpan]) -> str:
    """Convert typed inline spans to safe ReportLab XML/HTML markup."""
    parts: list[str] = []
    for span in spans:
        escaped = html.escape(span.content)
        if span.kind == "math":
            parts.append(_get_inline_math_img_tag(span.content))
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

        elif isinstance(block, (MathBlock, EquationBlockNode)):
            flowable = _render_math_to_pdf_flowable(
                block.latex,
                styles,
                status=block.rendering_status,
                error_msg=block.validation_error,
            )
            story.append(Spacer(1, 6))
            story.append(flowable)
            story.append(Spacer(1, 6))

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
    except Exception as exc:
        logger.warning("Failed to render table to PDF: %s", exc)


def _render_figure_bytes_to_pdf(
    story: list[Any],
    img_bytes: bytes,
    caption: str,
    styles: dict[str, ParagraphStyle],
) -> None:
    try:
        target_w: float = 360.0
        target_h: float = 200.0
        try:
            with PILImage.open(io.BytesIO(img_bytes)) as pil_img:
                w, h = pil_img.size
                if w > 0:
                    aspect = h / w
                    target_w = float(min(420.0, max(200.0, w * 0.5)))
                    target_h = float(target_w * aspect)
                    if target_h > 280.0:
                        target_h = 280.0
                        target_w = float(target_h / aspect)
        except Exception as exc:
            logger.warning("Failed to determine figure dimensions for PDF, using defaults: %s", exc)

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
