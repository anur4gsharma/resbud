"""Academic Markdown-to-Document translation engine for DOCX and PDF compilation.

Provides a robust, token-based conversion layer separating structural document models
from Markdown prose, enforcing hierarchical section numbering, authentic typographic styles,
Unicode font embedding, and zero Markdown token leakage.
"""

from __future__ import annotations

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

# fixmyslop-ignore[deps/phantom-import] Top-level import provided by mathml2omml-as package
import matplotlib
import matplotlib.pyplot as plt
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.shared import Inches, Pt, RGBColor
from PIL import Image as PILImage
from PIL import ImageFile
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.pdfmetrics import registerFontFamily
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Image as RLImage
from reportlab.platypus import KeepTogether, Paragraph, Preformatted, Spacer, Table, TableStyle

from resbud_api.services.chart_generator import render_academic_chart_from_spec
from resbud_api.services.image_processor import decode_image_source, process_image_for_document
from resbud_api.services.math_omml import (
    insert_omml_into_paragraph,
)
from resbud_api.templates.ieee_conference import (
    format_ieee_heading_2,
    format_ieee_heading_3,
)

matplotlib.use("Agg")
ImageFile.LOAD_TRUNCATED_IMAGES = True

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

FIGURE_TAG_PATTERN = re.compile(r"!\[([\s\S]*?)\]\(((?:data:[^)\s]+|https?://[^)\s]+|[^)\s]+))\)")

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
    return cleaned


def clean_post_equation_prose(text: str) -> str:
    """Format and clean prose following an extracted standalone equation."""
    cleaned = text.strip()
    if not cleaned or cleaned in (".", ",", ";", ":", "!", "?"):
        return ""
    cleaned = re.sub(r"^[,\s;]+", "", cleaned).strip()
    if not cleaned or cleaned in (".", ",", ";", ":", "!", "?"):
        return ""
    return cleaned


def is_big_equation(m: re.Match[str], full_text: str) -> bool:
    """Determine whether a regex math match represents a standalone/display equation
    or should remain inline within its paragraph prose.

    Adheres strictly to author delimiters and semantic structure:
    - $$...$$, \\[...\\], and \\begin{...} are display mathematics.
    - Multiline equations with explicit \\\\ line breaks are display mathematics.
    - Standalone equations occupying an entire paragraph are display mathematics.
    - Complete standalone equation definitions embedded in prose (with equality,
      structural math operators, and substantial length) are extracted as display blocks.
    - Inline variables ($x$, $\\alpha$, $k_1$, $f(t,d)$) strictly remain inline within prose.
    """
    if m.lastgroup in ("math_display", "math_env"):
        return True

    raw = m.group(0)
    if raw.startswith("$$") or raw.startswith(r"\["):
        return True

    # Multiline math with LaTeX newline breaks or environments embedded within parens/dollars
    if r"\\" in raw or re.search(r"\\begin\{[a-zA-Z0-9*]+\}", raw):
        return True

    # Standalone equation occupying the entire paragraph
    if full_text.strip() == raw.strip():
        return True

    inner = clean_math_source(raw)

    # Complete standalone equation definitions embedded in prose
    # (e.g. "... is defined as $O(S) = \prod_{i=1}^n f(P_i, C_i)$, where ...")
    if (
        any(rel in inner for rel in ("=", ":=", r"\equiv", r"\approx"))
        and len(inner) >= 15
        and any(op in inner for op in (r"\sum", r"\prod", r"\int", r"\frac", r"\sqrt"))
    ):
        return True

    # Author inline delimiters ($...$ and \(...\)) strictly remain inline
    return False


def extract_equation_blocks_from_paragraph(text: str) -> list[MarkdownBlock]:
    """Split paragraph text ONLY on display/big mathematical expressions,

    producing alternating ParagraphBlock (with preserved inline math spans)
    and EquationBlockNode (for display math blocks).
    Ensures inline math symbols remain within paragraph text without line breaks.
    """
    big_matches = [
        m
        for m in MATH_EXTRACT_RE.finditer(text)
        if m.lastgroup not in ("code", "escaped_dollar") and is_big_equation(m, text)
    ]

    if not big_matches:
        return [ParagraphBlock(spans=parse_inline_spans(text.strip()))]

    blocks: list[MarkdownBlock] = []
    cursor = 0
    for m in big_matches:
        pre_text = text[cursor : m.start()].strip()
        if pre_text:
            cleaned_pre = clean_pre_equation_prose(pre_text)
            if cleaned_pre:
                blocks.append(ParagraphBlock(spans=parse_inline_spans(cleaned_pre)))

        raw_math = m.group(0)
        display_type: Literal["display", "extracted_inline", "environment"] = (
            "environment"
            if (m.lastgroup == "math_env" or re.search(r"\\begin\{[a-zA-Z0-9*]+\}", raw_math))
            else "display"
        )
        eq_node = create_equation_block_node(raw_math, display_type=display_type)
        blocks.append(eq_node)
        cursor = m.end()

    trailing_text = text[cursor:].strip()
    if trailing_text:
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
        fig_match = FIGURE_TAG_PATTERN.match(trimmed)
        if fig_match and fig_match.end() == len(trimmed):
            blocks.append(
                FigureBlock(caption=fig_match.group(1).strip(), src=fig_match.group(2).strip())
            )
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
            and not lines[i].strip().startswith("![")
            and not (
                FIGURE_TAG_PATTERN.match(lines[i].strip())
                and (m := FIGURE_TAG_PATTERN.match(lines[i].strip())) is not None
                and m.end() == len(lines[i].strip())
            )
            and lines[i].strip() not in ("$$", r"\[")
        ):
            para_lines.append(lines[i].strip())
            i += 1

        if para_lines:
            para_text = " ".join(para_lines)
            if FIGURE_TAG_PATTERN.search(para_text):
                last_idx = 0
                for f_match in FIGURE_TAG_PATTERN.finditer(para_text):
                    start, end = f_match.span()
                    before = para_text[last_idx:start].strip()
                    if before:
                        blocks.extend(extract_equation_blocks_from_paragraph(before))
                    blocks.append(
                        FigureBlock(
                            caption=f_match.group(1).strip(),
                            src=f_match.group(2).strip(),
                        )
                    )
                    last_idx = end
                after = para_text[last_idx:].strip()
                if after:
                    blocks.extend(extract_equation_blocks_from_paragraph(after))
            else:
                blocks.extend(extract_equation_blocks_from_paragraph(para_text))

    return blocks


# --- DOCX Rendering Support ---


def render_blocks_to_docx(
    document: Any,
    blocks: list[MarkdownBlock],
    section_index: int,
    numbered: bool = True,
    academic_font: str = "Times New Roman",
    two_column: bool = False,
    template_id: str = "default",
    figure_lookup: dict[str, Any] | None = None,
) -> None:
    """Render structured Markdown blocks into a Word document with hierarchical numbering."""
    sub_index = 0
    subsub_index = 0
    is_ieee = template_id == "ieee_conference"
    body_size_pt = 10.0 if is_ieee else (9.5 if two_column else 10.5)
    h2_size_pt = 10.0 if two_column else 11.0
    h3_size_pt = 10.0 if is_ieee else (9.5 if two_column else 10.5)
    max_fig_width = 3.2 if two_column else 5.5
    caption_size = 8.5 if two_column else 9.5

    for block in blocks:
        if isinstance(block, HeadingBlock):
            if block.level == 2:
                sub_index += 1
                subsub_index = 0
                if is_ieee:
                    title_text = (
                        format_ieee_heading_2(sub_index, block.title) if numbered else block.title
                    )
                else:
                    title_text = (
                        f"{section_index}.{sub_index} {block.title}" if numbered else block.title
                    )
                h_para = document.add_heading(title_text, level=2)
                h_para.paragraph_format.space_before = Pt(8 if two_column else 10)
                h_para.paragraph_format.space_after = Pt(2 if two_column else 3)
                h_para.paragraph_format.keep_with_next = True
                _ensure_runs_font(
                    h_para,
                    academic_font,
                    bold=not is_ieee,
                    italic=is_ieee,
                    size_pt=h2_size_pt,
                )
            else:
                subsub_index += 1
                if is_ieee:
                    title_text = (
                        format_ieee_heading_3(subsub_index, block.title)
                        if numbered
                        else block.title
                    )
                else:
                    title_text = (
                        f"{section_index}.{sub_index}.{subsub_index} {block.title}"
                        if numbered
                        else block.title
                    )
                h_para = document.add_heading(title_text, level=3)
                h_para.paragraph_format.space_before = Pt(6 if two_column else 8)
                h_para.paragraph_format.space_after = Pt(2)
                h_para.paragraph_format.keep_with_next = True
                _ensure_runs_font(
                    h_para,
                    academic_font,
                    bold=not is_ieee,
                    italic=True,
                    size_pt=h3_size_pt,
                )

        elif isinstance(block, ParagraphBlock):
            p = document.add_paragraph()
            p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
            p.paragraph_format.line_spacing = 1.12 if two_column else 1.15
            p.paragraph_format.space_after = Pt(4 if two_column else 6)
            _render_spans_to_docx_paragraph(p, block.spans, academic_font, size_pt=body_size_pt)

        elif isinstance(block, ListBlock):
            style_name = "List Number" if block.ordered else "List Bullet"
            for _item_idx, item_spans in enumerate(block.items, start=block.start_num):
                p = document.add_paragraph(style=style_name)
                p.paragraph_format.space_after = Pt(2)
                p.paragraph_format.space_before = Pt(1)
                p.paragraph_format.line_spacing = 1.1
                _render_spans_to_docx_paragraph(p, item_spans, academic_font, size_pt=body_size_pt)

        elif isinstance(block, BlockquoteBlock):
            p = document.add_paragraph()
            p.paragraph_format.left_indent = Inches(0.25 if two_column else 0.4)
            p.paragraph_format.right_indent = Inches(0.25 if two_column else 0.4)
            p.paragraph_format.line_spacing = 1.12 if two_column else 1.15
            p.paragraph_format.space_before = Pt(3 if two_column else 4)
            p.paragraph_format.space_after = Pt(4 if two_column else 6)
            _render_spans_to_docx_paragraph(
                p, block.spans, academic_font, force_italic=True, size_pt=body_size_pt
            )

        elif isinstance(block, CodeBlock):
            p = document.add_paragraph()
            p.paragraph_format.left_indent = Inches(0.15 if two_column else 0.25)
            p.paragraph_format.space_before = Pt(3 if two_column else 4)
            p.paragraph_format.space_after = Pt(4 if two_column else 6)
            run = p.add_run(block.code)
            run.font.name = "Consolas"
            run.font.size = Pt(8.5 if two_column else 9.0)
            run.font.color.rgb = RGBColor(0x22, 0x22, 0x22)

        elif isinstance(block, (MathBlock, EquationBlockNode)):
            p = document.add_paragraph()
            p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
            p.paragraph_format.space_before = Pt(6 if two_column else 8)
            p.paragraph_format.space_after = Pt(6 if two_column else 8)
            _render_math_to_docx(
                p,
                block.latex,
                academic_font,
                is_display=True,
                status=block.rendering_status,
                error_msg=block.validation_error,
                equation_number=block.equation_id,
            )

        elif isinstance(block, TableBlock):
            _render_table_to_docx(
                document,
                block.headers,
                block.rows,
                academic_font,
                max_width_in=3.2 if two_column else 6.0,
                font_size_pt=8.5 if two_column else 9.5,
            )

        elif isinstance(block, FigureBlock):
            fig_obj = (figure_lookup or {}).get(block.src)
            if fig_obj is not None:
                is_full = getattr(fig_obj, "column_span", "column_width") == "full_width"
                img_src = getattr(fig_obj, "data_uri", None) or block.src
                caption_text = getattr(fig_obj, "caption", None) or block.caption
            else:
                is_full = "full_width" in block.src or "full_width" in block.caption.lower()
                img_src = block.src
                caption_text = block.caption

            fig_w = 6.2 if is_full else max_fig_width
            _render_figure_src_to_docx(
                document,
                img_src,
                caption_text,
                academic_font,
                max_width_in=fig_w,
                caption_size_pt=caption_size,
                figure_lookup=figure_lookup,
            )

        elif isinstance(block, ChartBlock):
            chart_bytes = render_academic_chart_from_spec(block.spec)
            if chart_bytes:
                caption = "Figure: Quantitative Benchmark Results"
                for c_line in block.spec.split("\n"):
                    if c_line.strip().lower().startswith("title:"):
                        caption = f"Figure: {c_line.split(':', 1)[1].strip()}"
                        break
                _render_figure_bytes_to_docx(
                    document,
                    chart_bytes,
                    caption,
                    academic_font,
                    max_width_in=max_fig_width,
                    caption_size_pt=caption_size,
                )


def _render_math_to_docx(
    paragraph: Any,
    latex_str: str,
    font_name: str,
    is_display: bool = True,
    status: Literal["ok", "warning", "error"] = "ok",
    error_msg: str | None = None,
    equation_number: str | None = None,
) -> None:
    """Render LaTeX equation into Word paragraph using native OMML."""
    insert_omml_into_paragraph(
        paragraph,
        latex_str,
        is_display=is_display,
        equation_number=equation_number,
    )


def _render_spans_to_docx_paragraph(
    paragraph: Any,
    spans: list[InlineSpan],
    font_name: str,
    force_italic: bool = False,
    size_pt: float = 10.5,
) -> None:
    pure_black = RGBColor(0, 0, 0)
    for span in spans:
        if span.kind == "math":
            _render_math_to_docx(paragraph, span.content, font_name, is_display=False)
            continue

        run = paragraph.add_run(span.content)
        run.font.name = "Consolas" if span.kind == "code" else font_name
        code_size = max(8.0, size_pt - 1.0)
        run.font.size = Pt(code_size) if span.kind == "code" else Pt(size_pt)
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
    max_width_in: float = 6.0,
    font_size_pt: float = 9.5,
) -> None:
    try:
        all_rows = [headers] + rows
        num_cols = max(len(r) for r in all_rows)
        table = document.add_table(rows=len(all_rows), cols=num_cols)
        table.style = "Table Grid"
        col_w = Inches(max_width_in / max(num_cols, 1))
        for r_idx, row in enumerate(all_rows):
            for c_idx, cell_text in enumerate(row):
                if c_idx < num_cols:
                    cell = table.cell(r_idx, c_idx)
                    cell.text = cell_text
                    cell.width = col_w
                    for p in cell.paragraphs:
                        p.paragraph_format.space_before = Pt(2)
                        p.paragraph_format.space_after = Pt(2)
                        p.paragraph_format.line_spacing = 1.05
                        for r in p.runs:
                            r.font.name = font_name
                            r.font.size = Pt(font_size_pt)
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
    max_width_in: float = 5.5,
    caption_size_pt: float = 9.5,
) -> None:
    try:
        max_w_pt = max_width_in * 72.0
        max_h_pt = 320.0 if max_width_in > 4.0 else 230.0
        processed = process_image_for_document(
            img_bytes, max_width_pt=max_w_pt, max_height_pt=max_h_pt
        )
        if processed is not None:
            buf, target_w_pt, target_h_pt = processed
            target_w_in = target_w_pt / 72.0
            target_h_in = target_h_pt / 72.0

            p = document.add_paragraph()
            p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
            p.paragraph_format.space_before = Pt(6)
            p.paragraph_format.space_after = Pt(2)
            p.paragraph_format.keep_with_next = True
            run = p.add_run()
            run.add_picture(buf, width=Inches(target_w_in), height=Inches(target_h_in))

            caption_p = document.add_paragraph()
            caption_p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
            caption_p.paragraph_format.space_before = Pt(2)
            caption_p.paragraph_format.space_after = Pt(8)
            c_run = caption_p.add_run(caption)
            c_run.font.name = font_name
            c_run.font.size = Pt(caption_size_pt)
            c_run.font.italic = True
            c_run.font.color.rgb = RGBColor(0x33, 0x33, 0x33)
            return
    except Exception as exc:
        logger.warning("Failed to render figure bytes to DOCX: %s", exc)

    p = document.add_paragraph()
    p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = p.add_run(f"[{caption}]")
    run.font.name = font_name
    run.font.italic = True


def _render_figure_src_to_docx(
    document: Any,
    img_src: str,
    caption: str,
    font_name: str,
    max_width_in: float = 5.5,
    caption_size_pt: float = 9.5,
    figure_lookup: dict[str, Any] | None = None,
) -> None:
    img_bytes = decode_image_source(img_src)
    if img_bytes is None and figure_lookup and img_src in figure_lookup:
        fig_obj = figure_lookup[img_src]
        img_bytes = decode_image_source(getattr(fig_obj, "data_uri", "") or "")

    if img_bytes is not None:
        _render_figure_bytes_to_docx(
            document,
            img_bytes,
            caption,
            font_name,
            max_width_in=max_width_in,
            caption_size_pt=caption_size_pt,
        )
    else:
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


def _sanitize_mathtext_str(clean: str) -> str:
    """Preprocess LaTeX math string for Matplotlib mathtext compatibility."""
    s = clean.strip()
    s = re.sub(r"\\ge\b", r"\\geq", s)
    s = re.sub(r"\\le\b", r"\\leq", s)
    s = re.sub(r"\\ne\b", r"\\neq", s)
    s = re.sub(r"\\text\{([^}]+)\}", r"\\rm{\1}", s)
    s = s.replace(r"\text", r"\rm").replace(r"\parallel", r"\Vert")
    if s.startswith(r"\begin{aligned}") and s.endswith(r"\end{aligned}"):
        s = s.replace(r"\begin{aligned}", "").replace(r"\end{aligned}", "")
    s = re.sub(r"&=", "=", s)
    s = re.sub(r"&", " ", s)
    return s


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
        mathtext_str = _sanitize_mathtext_str(clean)
        if not (mathtext_str.startswith("$") and mathtext_str.endswith("$")):
            mathtext_str = f"${mathtext_str}$"

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
            max_w = 460.0
            if w_pt > max_w:
                scale = max_w / w_pt
                w_pt = max_w
                h_pt = h_pt * scale

            max_h = 13.5
            if h_pt > max_h:
                scale = max_h / h_pt
                h_pt = max_h
                w_pt = w_pt * scale

        file_path = os.path.join(_INLINE_MATH_DIR.name, f"math_{abs(hash(clean))}.png")
        with open(file_path, "wb") as f:
            f.write(buf.getvalue())

        valign = -2
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
    max_width: float = 460.0,
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
    mathtext_str = _sanitize_mathtext_str(clean)
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
            if w_pt > max_width:
                scale = max_width / w_pt
                w_pt = max_width
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
    max_width: float = 460.0,
    two_column: bool = False,
    figure_lookup: dict[str, Any] | None = None,
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
                max_width=max_width,
            )
            story.append(Spacer(1, 4 if two_column else 6))
            story.append(flowable)
            story.append(Spacer(1, 4 if two_column else 6))

        elif isinstance(block, TableBlock):
            _render_table_to_pdf(story, block.headers, block.rows, styles, max_width=max_width)

        elif isinstance(block, FigureBlock):
            fig_obj = (figure_lookup or {}).get(block.src)
            if fig_obj is not None:
                is_full = getattr(fig_obj, "column_span", "column_width") == "full_width"
                img_src = getattr(fig_obj, "data_uri", None) or block.src
                caption_text = getattr(fig_obj, "caption", None) or block.caption
            else:
                is_full = "full_width" in block.src or "full_width" in block.caption.lower()
                img_src = block.src
                caption_text = block.caption

            effective_w = 460.0 if (is_full and not two_column) else max_width
            _render_figure_src_to_pdf(
                story,
                img_src,
                caption_text,
                styles,
                max_width=effective_w,
                figure_lookup=figure_lookup,
            )

        elif isinstance(block, ChartBlock):
            chart_bytes = render_academic_chart_from_spec(block.spec)
            if chart_bytes:
                caption = "Figure: Quantitative Results"
                for c_line in block.spec.split("\n"):
                    if c_line.strip().lower().startswith("title:"):
                        caption = f"Figure: {c_line.split(':', 1)[1].strip()}"
                        break
                _render_figure_bytes_to_pdf(
                    story, chart_bytes, caption, styles, max_width=max_width
                )


def _render_table_to_pdf(
    story: list[Any],
    headers: list[str],
    rows: list[list[str]],
    styles: dict[str, ParagraphStyle],
    max_width: float = 460.0,
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
        num_cols = max(len(r) for r in all_rows)
        col_w = max_width / max(num_cols, 1)
        t = Table(data, colWidths=[col_w] * num_cols, hAlign="CENTER")
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
    max_width: float = 420.0,
) -> None:
    max_h = 280.0 if max_width > 300.0 else 220.0
    processed = process_image_for_document(img_bytes, max_width_pt=max_width, max_height_pt=max_h)
    if processed is not None:
        buf, target_w, target_h = processed
        rl_img = RLImage(buf, width=target_w, height=target_h)
        rl_img.hAlign = "CENTER"
        caption_p = Paragraph(html.escape(caption), styles["Caption"])
        story.append(KeepTogether([Spacer(1, 4), rl_img, caption_p, Spacer(1, 6)]))
    else:
        logger.warning("Rendering placeholder for unprocessable figure bytes: %s", caption)
        placeholder_text = caption if caption.lower().startswith("figure") else f"Figure: {caption}"
        placeholder = Paragraph(f"<i>[{html.escape(placeholder_text)}]</i>", styles["Caption"])
        story.append(KeepTogether([Spacer(1, 4), placeholder, Spacer(1, 6)]))


def _render_figure_src_to_pdf(
    story: list[Any],
    img_src: str,
    caption: str,
    styles: dict[str, ParagraphStyle],
    max_width: float = 420.0,
    figure_lookup: dict[str, Any] | None = None,
) -> None:
    img_bytes = decode_image_source(img_src)
    if img_bytes is None and figure_lookup and img_src in figure_lookup:
        fig_obj = figure_lookup[img_src]
        img_bytes = decode_image_source(getattr(fig_obj, "data_uri", "") or "")

    if img_bytes is not None:
        _render_figure_bytes_to_pdf(story, img_bytes, caption, styles, max_width=max_width)
    else:
        logger.warning("Rendering placeholder for unprocessable figure source: %s", caption)
        placeholder_text = caption if caption.lower().startswith("figure") else f"Figure: {caption}"
        placeholder = Paragraph(f"<i>[{html.escape(placeholder_text)}]</i>", styles["Caption"])
        story.append(KeepTogether([Spacer(1, 4), placeholder, Spacer(1, 6)]))
