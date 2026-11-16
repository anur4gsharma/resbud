"""Canonical Mathematical Document Model and Native Office Math Markup Language (OMML) Engine.

Provides bidirectional conversion between LaTeX mathematical notation,
W3C MathML, and ISO/IEC 29500-1 native WordprocessingML Office Math (OMML).
Guarantees editable, native equation objects in exported Microsoft Word (.docx) documents.
"""

from __future__ import annotations

import html
import logging
import re
from dataclasses import dataclass, field
from typing import Any, Literal

import latex2mathml.converter
import mathml2omml
from docx.oxml import parse_xml

logger = logging.getLogger(__name__)

# Math XML Namespace
OMML_NS = 'xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"'


@dataclass
class MathNodeBase:
    """Base mathematical node preserving source and target representations."""

    original_latex: str
    normalized_latex: str
    mathml: str | None = None
    omml: str | None = None
    rendering_status: Literal["ok", "warning", "error"] = "ok"
    validation_warnings: list[str] = field(default_factory=list)
    source_location: str | None = None


@dataclass
class InlineMathNode(MathNodeBase):
    """Inline equation embedded within running paragraph prose."""

    pass


@dataclass
class DisplayMathNode(MathNodeBase):
    """Standalone display equation occupying its own centered block."""

    equation_number: str | None = None
    equation_label: str | None = None
    environment: str | None = None
    is_multiline: bool = False


@dataclass
class TextRunNode:
    """Prose text run within a paragraph."""

    text: str
    bold: bool = False
    italic: bool = False
    code: bool = False


@dataclass
class ParagraphNode:
    """Paragraph container supporting mixed text runs and inline math nodes."""

    children: list[TextRunNode | InlineMathNode] = field(default_factory=list)


def clean_math_delimiters(raw_latex: str) -> str:
    """Strip LaTeX math delimiters ($$, $, \\[, \\], \\(, \\))."""
    clean = raw_latex.strip()
    if clean.startswith("$$") and clean.endswith("$$") and len(clean) > 4:
        return clean[2:-2].strip()
    if clean.startswith(r"\[") and clean.endswith(r"\]") and len(clean) > 4:
        return clean[2:-2].strip()
    if clean.startswith(r"\(") and clean.endswith(r"\)") and len(clean) > 4:
        return clean[2:-2].strip()
    if clean.startswith("$") and clean.endswith("$") and len(clean) > 2:
        return clean[1:-1].strip()
    return clean


def sanitize_latex_for_mathml(raw_latex: str) -> str:
    """Sanitize and normalize LaTeX math expressions for robust MathML parsing.

    Handles alignment tokens, matrix environments, common operatornames, and macros.
    """
    clean = clean_math_delimiters(raw_latex)

    # 1. Normalize alignment environments (align, aligned, gather, split, multline)
    # MathML converters fail on raw alignment ampersands (&, &=); transform to matrix structure
    if re.search(r"\\begin\{(?:align|aligned|gather|split|multline)\*?\}", clean):
        clean = re.sub(
            r"\\begin\{(?:align|aligned|gather|split|multline)\*?\}",
            r"\\begin{matrix}",
            clean,
        )
        clean = re.sub(
            r"\\end\{(?:align|aligned|gather|split|multline)\*?\}",
            r"\\end{matrix}",
            clean,
        )
        clean = re.sub(r"&=", "=", clean)
        clean = clean.replace("&", " ")

    # 2. Normalize common function names and text wrappers
    clean = re.sub(r"\\operatorname\{([a-zA-Z0-9_]+)\}", r"\\mathrm{\1}", clean)
    clean = re.sub(r"\\text\{([^{}]+)\}", r"\\mathrm{\1}", clean)
    clean = re.sub(r"\\bm\{([^{}]+)\}", r"\\mathbf{\1}", clean)
    clean = re.sub(r"\\boldsymbol\{([^{}]+)\}", r"\\mathbf{\1}", clean)
    clean = re.sub(r"\\mathbf\{([^{}]+)\}", r"\\mathbf{\1}", clean)

    # 3. Clean spacing commands that cause syntax errors in MathML
    clean = clean.replace(r"\quad", " ").replace(r"\qquad", "  ").replace(r"\,", " ")

    # 4. Normalize norm symbols
    clean = clean.replace(r"\parallel", r"\Vert")

    # 5. Strip LaTeX \label and \tag commands from inner MathML/OMML
    clean = re.sub(r"\\label\{[^{}]+\}", "", clean)
    clean = re.sub(r"\\tag\{[^{}]+\}", "", clean)

    return clean


def validate_latex_math(latex_str: str) -> tuple[Literal["ok", "warning", "error"], str | None]:
    """Validate LaTeX syntax bounds and check for unclosed braces or invalid tokens."""
    clean = clean_math_delimiters(latex_str)

    if len(clean) > 5000:
        return "error", "Mathematical expression exceeds maximum allowable length (5000 chars)"

    brace_depth = 0
    in_escape = False
    for ch in clean:
        if in_escape:
            in_escape = False
            continue
        if ch == "\\":
            in_escape = True
            continue
        if ch == "{":
            brace_depth += 1
        elif ch == "}":
            brace_depth -= 1
            if brace_depth < 0:
                return "error", "Unbalanced closing brace '}' in mathematical expression"

    if brace_depth != 0:
        return "error", f"Unclosed opening brace '{{' (unbalanced by {brace_depth})"

    return "ok", None


def latex_to_omml_xml(
    latex_str: str,
    is_display: bool = False,
    equation_number: str | None = None,
) -> tuple[str, Literal["ok", "warning", "error"], str | None]:
    """Convert a LaTeX mathematical string to genuine Microsoft Word OMML XML.

    Produces <m:oMathPara> for display mathematics and <m:oMath> for inline mathematics.
    Returns (omml_xml_string, status, warning_message).
    """
    status, val_err = validate_latex_math(latex_str)
    if status == "error":
        # Safe fallback OMML wrapping the original formula as formatted math text
        safe_text = html.escape(clean_math_delimiters(latex_str))
        fallback_inner = f'<m:r><m:rPr><m:sty m:val="i"/></m:rPr><m:t>{safe_text}</m:t></m:r>'
        if is_display:
            omml_str = (
                f"<m:oMathPara {OMML_NS}>"
                f'<m:oMathParaPr><m:jc m:val="center"/></m:oMathParaPr>'
                f"<m:oMath>{fallback_inner}</m:oMath>"
                f"</m:oMathPara>"
            )
        else:
            omml_str = f"<m:oMath {OMML_NS}>{fallback_inner}</m:oMath>"
        return omml_str, "error", val_err

    clean = sanitize_latex_for_mathml(latex_str)

    try:
        # Step 1: LaTeX -> MathML
        mathml = latex2mathml.converter.convert(clean)

        # Fix any raw unescaped & tokens in MathML
        mathml = mathml.replace("<mi>&</mi>", "").replace("<mi>&amp;</mi>", "")

        # Step 2: MathML -> OMML
        omml_chunk = mathml2omml.convert(mathml)

        # Strip outer m:oMath if returned by mathml2omml so we can control root and namespace
        if omml_chunk.startswith("<m:oMath") and omml_chunk.endswith("</m:oMath>"):
            inner = omml_chunk[omml_chunk.find(">") + 1 : omml_chunk.rfind("</m:oMath>")]
        else:
            inner = omml_chunk

        # Step 3: Wrap in appropriate OMML parent
        if is_display:
            omml_str = (
                f"<m:oMathPara {OMML_NS}>"
                f'<m:oMathParaPr><m:jc m:val="center"/></m:oMathParaPr>'
                f"<m:oMath>{inner}</m:oMath>"
                f"</m:oMathPara>"
            )
        else:
            omml_str = f"<m:oMath {OMML_NS}>{inner}</m:oMath>"

        return omml_str, "ok", None

    except Exception as exc:
        logger.warning(
            "Primary MathML-OMML conversion failed for '%s': %s. Using resilient fallback.",
            clean[:60],
            exc,
        )
        safe_text = html.escape(clean)
        fallback_inner = f'<m:r><m:rPr><m:sty m:val="i"/></m:rPr><m:t>{safe_text}</m:t></m:r>'
        if is_display:
            omml_str = (
                f"<m:oMathPara {OMML_NS}>"
                f'<m:oMathParaPr><m:jc m:val="center"/></m:oMathParaPr>'
                f"<m:oMath>{fallback_inner}</m:oMath>"
                f"</m:oMathPara>"
            )
        else:
            omml_str = f"<m:oMath {OMML_NS}>{fallback_inner}</m:oMath>"
        return omml_str, "warning", f"MathML conversion warning: {exc}"


def insert_omml_into_paragraph(
    paragraph: Any,
    latex_str: str,
    is_display: bool = False,
    equation_number: str | None = None,
) -> tuple[Literal["ok", "warning", "error"], str | None]:
    """Transpile LaTeX to native OMML and attach it directly to a python-docx paragraph element."""
    omml_xml, status, warning = latex_to_omml_xml(
        latex_str, is_display=is_display, equation_number=equation_number
    )
    omml_element = parse_xml(omml_xml)
    paragraph._p.append(omml_element)
    return status, warning
