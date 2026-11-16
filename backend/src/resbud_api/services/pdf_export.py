"""In-memory academic PDF rendering for a validated paper draft."""

from __future__ import annotations

import html
import io
import logging
import re
import unicodedata
from typing import Any

import matplotlib.pyplot as plt
from PIL import Image as PILImage
from PIL import ImageFile
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4, letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.pdfgen import canvas
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    FrameBreak,
    HRFlowable,
    KeepTogether,
    NextPageTemplate,
    PageTemplate,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)
from reportlab.platypus import (
    Image as RLImage,
)

from resbud_api.core.errors import ResbudError
from resbud_api.domain.models import PaperDraft
from resbud_api.services.chart_generator import render_academic_chart_from_spec
from resbud_api.services.editorial_notes import prepare_paper_for_export
from resbud_api.services.equation_engine import process_manuscript_equations
from resbud_api.services.image_processor import decode_image_source, process_image_for_document
from resbud_api.services.markdown_renderer import (
    clean_heading_text,
    parse_markdown_blocks,
    render_blocks_to_pdf,
    setup_reportlab_academic_fonts,
)
from resbud_api.services.reference_engine import format_ieee_reference
from resbud_api.templates.ieee_conference import (
    calculate_ieee_author_grid,
    format_ieee_heading_1,
)

ImageFile.LOAD_TRUNCATED_IMAGES = True

logger = logging.getLogger(__name__)

MAX_EXPORT_BYTES = 8 * 1024 * 1024
PDF_MEDIA_TYPE = "application/pdf"

INLINE_MATH_PATTERN = re.compile(
    r"(\$\$[\s\S]*?\$\$|\\\[[\s\S]*?\\\]|\$[^$\n]+\$|\\\([\s\S]*?\\\))"
)
BLOCK_MATH_PATTERN = re.compile(
    r"^(?:\$\$([\s\S]*?)\$\$|\\\[([\s\S]*?)\\\]|\\begin\{(?:equation|align|gather)\*?}([\s\S]*?)\\end\{(?:equation|align|gather)\*?})$"
)


def safe_pdf_filename(title: str) -> str:
    """Create a short ASCII filename without using user text as a path."""
    ascii_title = unicodedata.normalize("NFKD", title).encode("ascii", "ignore").decode("ascii")
    slug = re.sub(r"[^a-z0-9]+", "-", ascii_title.lower()).strip("-")[:64].strip("-")
    return f"resbud-{slug or 'research-paper'}.pdf"


class _NumberedCanvas(canvas.Canvas):
    """Two-pass canvas to dynamically compute and print accurate page numbers."""

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        self._saved_page_states: list[dict[str, Any]] = []

    def showPage(self) -> None:
        self._saved_page_states.append(dict(self.__dict__))
        self._startPage()

    def save(self) -> None:
        num_pages = len(self._saved_page_states)
        for state in self._saved_page_states:
            self.__dict__.update(state)
            self._draw_page_number(num_pages)
            super().showPage()
        super().save()

    def _draw_page_number(self, page_count: int) -> None:
        self.saveState()
        self.setFont("Times-Roman", 9)
        self.setFillColor(colors.HexColor("#555555"))
        page_text = f"{self._pageNumber}"
        center_x = getattr(self, "_pagesize", letter)[0] / 2.0
        self.drawCentredString(center_x, 32, page_text)
        self.restoreState()


def export_paper_pdf(
    paper: PaperDraft,
    layout: str | None = None,
    include_review_notes_appendix: bool | None = None,
    template_id: str | None = None,
) -> bytes:
    """Render the submitted paper into a formal academic PDF and return binary bytes."""
    effective_layout = layout or getattr(paper, "page_layout", "single_column")
    effective_template = (
        template_id
        or getattr(paper, "document_template", None)
        or ("ieee_conference" if effective_layout == "two_column_academic" else "default")
    )
    effective_notes = (
        include_review_notes_appendix
        if include_review_notes_appendix is not None
        else getattr(paper, "include_review_notes_appendix", False)
    )
    sanitized_paper, review_notes = prepare_paper_for_export(
        paper, include_review_notes_appendix=effective_notes
    )
    sanitized_paper, _ = process_manuscript_equations(sanitized_paper)

    if effective_template == "ieee_conference" or effective_layout == "two_column_academic":
        return _export_two_column_academic_pdf(
            sanitized_paper, review_notes=review_notes, template_id=effective_template
        )

    try:
        buffer = io.BytesIO()
        doc = SimpleDocTemplate(
            buffer,
            pagesize=letter,
            leftMargin=72,
            rightMargin=72,
            topMargin=72,
            bottomMargin=72,
        )

        styles = _create_academic_styles()
        story = _build_story(sanitized_paper, styles, review_notes=review_notes)

        doc.build(story, canvasmaker=_NumberedCanvas)
        result = buffer.getvalue()
    except Exception as exc:
        raise ResbudError(500) from exc

    if len(result) > MAX_EXPORT_BYTES:
        raise ResbudError(413)

    return result


def _export_two_column_academic_pdf(
    paper: PaperDraft,
    review_notes: list[dict[str, str]] | None = None,
    template_id: str = "ieee_conference",
) -> bytes:
    """Render a formal Two-Column Academic research paper PDF (IEEE style) with full-width front matter."""
    try:
        buffer = io.BytesIO()
        page_w, page_h = A4
        margin = 54.0  # ~19mm
        gutter = 20.0  # ~7mm
        printable_w = page_w - 2 * margin
        printable_h = page_h - 2 * margin
        col_w = (printable_w - gutter) / 2.0

        styles = _create_two_column_academic_styles()

        # Build full-width front matter elements
        front_matter: list[Any] = []
        front_matter.append(Paragraph(html.escape(paper.title), styles["Title"]))

        authors = getattr(paper, "authors", None)
        if authors:
            sorted_authors = sorted(authors, key=lambda a: getattr(a, "order", 1))
            grid = calculate_ieee_author_grid(len(sorted_authors))
            aff_map = {aff.id: aff for aff in (getattr(paper, "affiliations", None) or [])}
            a_idx = 0
            for num_cols in grid:
                row_authors = sorted_authors[a_idx : a_idx + num_cols]
                a_idx += num_cols
                cell_data: list[Any] = []
                for author in row_authors:
                    lines = [f"<b>{html.escape(author.name)}</b>"]
                    if author.role_or_title:
                        lines.append(html.escape(author.role_or_title))
                    author_affs = [aff_map[aid] for aid in author.affiliation_ids if aid in aff_map]
                    paper_affs = getattr(paper, "affiliations", None) or []
                    aff_obj = (
                        author_affs[0]
                        if author_affs
                        else (paper_affs[0] if len(paper_affs) == 1 else None)
                    )
                    if aff_obj and aff_obj.department:
                        lines.append(f"<i>{html.escape(aff_obj.department)}</i>")
                    if aff_obj and aff_obj.institution:
                        lines.append(f"<i>{html.escape(aff_obj.institution)}</i>")
                    loc = ", ".join(
                        filter(
                            None,
                            [
                                aff_obj.city if aff_obj else None,
                                aff_obj.country if aff_obj else None,
                            ],
                        )
                    )
                    if loc:
                        lines.append(html.escape(loc))
                    if author.email:
                        lines.append(html.escape(author.email))
                    cell_html = "<br/>".join(lines)
                    cell_data.append(Paragraph(cell_html, styles["Author"]))
                t = Table([cell_data], colWidths=[printable_w / num_cols] * num_cols)
                t.setStyle(
                    TableStyle(
                        [
                            ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                            ("VALIGN", (0, 0), (-1, -1), "TOP"),
                            ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
                            ("TOPPADDING", (0, 0), (-1, -1), 2),
                        ]
                    )
                )
                front_matter.append(t)
        elif paper.author_info and paper.author_info.strip():
            front_matter.append(Paragraph(html.escape(paper.author_info.strip()), styles["Author"]))
            if paper.affiliation and paper.affiliation.strip():
                front_matter.append(
                    Paragraph(html.escape(paper.affiliation.strip()), styles["Affiliation"])
                )

        if paper.abstract.strip():
            front_matter.append(
                Paragraph(
                    f"<b>Abstract— </b>{html.escape(paper.abstract.strip())}",
                    styles["AbstractBody"],
                )
            )

        if paper.keywords:
            kw_html = "<b><i>Index Terms— </i></b>" + html.escape(", ".join(paper.keywords))
            front_matter.append(Paragraph(kw_html, styles["Keywords"]))

        front_matter.append(Spacer(1, 4))
        front_matter.append(
            HRFlowable(width="100%", thickness=0.5, color=colors.HexColor("#CCCCCC"), spaceAfter=8)
        )

        # Dynamically measure front matter height including inter-element spacing
        fm_h = 0.0
        for item in front_matter:
            _, h = item.wrap(printable_w, printable_h)
            sb = getattr(item, "getSpaceBefore", lambda: 0)()
            sa = getattr(item, "getSpaceAfter", lambda: 0)()
            fm_h += h + sb + sa
        fm_h += 14.0  # padding buffer for frame boundaries
        max_fm_h = printable_h - 150.0
        if fm_h > max_fm_h:
            fm_h = max_fm_h

        # Page 1 Frames: Top full-width + two bottom columns
        frame_top = Frame(
            margin,
            page_h - margin - fm_h,
            printable_w,
            fm_h,
            id="F_top",
            leftPadding=0,
            rightPadding=0,
            topPadding=0,
            bottomPadding=0,
        )
        frame_b1 = Frame(
            margin,
            margin,
            col_w,
            printable_h - fm_h - 8.0,
            id="F_b1",
            leftPadding=0,
            rightPadding=0,
            topPadding=0,
            bottomPadding=0,
        )
        frame_b2 = Frame(
            margin + col_w + gutter,
            margin,
            col_w,
            printable_h - fm_h - 8.0,
            id="F_b2",
            leftPadding=0,
            rightPadding=0,
            topPadding=0,
            bottomPadding=0,
        )

        # Later Pages: Two full-height columns
        frame_c1 = Frame(
            margin,
            margin,
            col_w,
            printable_h,
            id="F_c1",
            leftPadding=0,
            rightPadding=0,
            topPadding=0,
            bottomPadding=0,
        )
        frame_c2 = Frame(
            margin + col_w + gutter,
            margin,
            col_w,
            printable_h,
            id="F_c2",
            leftPadding=0,
            rightPadding=0,
            topPadding=0,
            bottomPadding=0,
        )

        doc = BaseDocTemplate(
            buffer,
            pagesize=A4,
            leftMargin=margin,
            rightMargin=margin,
            topMargin=margin,
            bottomMargin=margin,
        )
        first_page_tpl = PageTemplate(id="FirstPage", frames=[frame_top, frame_b1, frame_b2])
        later_pages_tpl = PageTemplate(id="LaterPages", frames=[frame_c1, frame_c2])
        doc.addPageTemplates([first_page_tpl, later_pages_tpl])

        story: list[Any] = []
        story.extend(front_matter)
        story.append(FrameBreak())
        story.append(NextPageTemplate("LaterPages"))

        body_sections = [
            sec
            for sec in paper.sections
            if sec.id.lower() not in ("references", "bibliography")
            and sec.heading.strip().lower() not in ("references", "bibliography", "6. references")
        ]

        is_ieee = template_id == "ieee_conference"
        figure_lookup: dict[str, Any] = {}
        if paper.figures:
            for fig in paper.figures:
                figure_lookup[fig.id] = fig
                figure_lookup[fig.filename] = fig

        for sec_idx, section in enumerate(body_sections, start=1):
            clean_title = clean_heading_text(section.heading)
            heading_text = (
                format_ieee_heading_1(sec_idx, clean_title)
                if is_ieee
                else f"{sec_idx}. {clean_title}"
            )
            story.append(Paragraph(html.escape(heading_text), styles["Heading1"]))
            blocks = parse_markdown_blocks(section.content)
            render_blocks_to_pdf(
                story,
                blocks,
                styles,
                section_index=sec_idx,
                numbered=True,
                max_width=col_w,
                two_column=True,
                figure_lookup=figure_lookup,
            )

        if paper.references:
            story.append(Paragraph("References", styles["Heading1"]))
            for ref_idx, ref in enumerate(paper.references, start=1):
                ref_num = ref.citation_number or ref_idx
                if ref.title and ref.publication_type:
                    ref_text = format_ieee_reference(ref, ref_num)
                else:
                    ref_text = ref.text.strip()
                    if not re.match(r"^\[\d+\]", ref_text) and not re.match(r"^\d+\.", ref_text):
                        ref_text = f"[{ref_num}] {ref_text}"
                story.append(Paragraph(html.escape(ref_text), styles["Reference"]))

        if review_notes:
            story.append(Spacer(1, 8))
            story.append(Paragraph("Author Review Notes", styles["Heading1"]))
            story.append(
                Paragraph(
                    "<i>The following unresolved research and editorial review notes pertain to this manuscript:</i>",
                    styles["Body"],
                )
            )
            for n_idx, note in enumerate(review_notes, start=1):
                sec_name = html.escape(note["section"])
                msg_text = html.escape(note["message"])
                note_html = f"<b>{n_idx}. [{sec_name}]</b> {msg_text}"
                story.append(Paragraph(note_html, styles["ListItem"]))

        doc.build(story, canvasmaker=_NumberedCanvas)
        result = buffer.getvalue()
    except Exception as exc:
        raise ResbudError(500) from exc

    if len(result) > MAX_EXPORT_BYTES:
        raise ResbudError(413)

    return result


def _create_academic_styles() -> dict[str, ParagraphStyle]:
    sample = getSampleStyleSheet()
    font_name = setup_reportlab_academic_fonts()
    bold_font = f"{font_name}-Bold" if font_name == "AcademicSerif" else "Times-Bold"
    italic_font = f"{font_name}-Italic" if font_name == "AcademicSerif" else "Times-Italic"
    bold_italic_font = (
        f"{font_name}-BoldItalic" if font_name == "AcademicSerif" else "Times-BoldItalic"
    )

    styles = {
        "Title": ParagraphStyle(
            "AcademicTitle",
            parent=sample["Normal"],
            fontName=bold_font,
            fontSize=18,
            leading=22,
            alignment=1,  # Center
            spaceAfter=14,
            textColor=colors.black,
        ),
        "Author": ParagraphStyle(
            "AcademicAuthor",
            parent=sample["Normal"],
            fontName=bold_font,
            fontSize=11,
            leading=14,
            alignment=1,  # Center
            spaceBefore=2,
            spaceAfter=2,
            textColor=colors.black,
        ),
        "Affiliation": ParagraphStyle(
            "AcademicAffiliation",
            parent=sample["Normal"],
            fontName=italic_font,
            fontSize=9.5,
            leading=13,
            alignment=1,  # Center
            spaceBefore=0,
            spaceAfter=10,
            textColor=colors.black,
        ),
        "AbstractHeading": ParagraphStyle(
            "AcademicAbstractHeading",
            parent=sample["Normal"],
            fontName=bold_font,
            fontSize=10,
            leading=13,
            alignment=1,  # Center
            spaceBefore=10,
            spaceAfter=6,
            textColor=colors.black,
        ),
        "AbstractBody": ParagraphStyle(
            "AcademicAbstractBody",
            parent=sample["Normal"],
            fontName=font_name,
            fontSize=10,
            leading=13.5,
            alignment=4,  # Justified
            leftIndent=18,
            rightIndent=18,
            spaceAfter=8,
            textColor=colors.black,
        ),
        "Keywords": ParagraphStyle(
            "AcademicKeywords",
            parent=sample["Normal"],
            fontName=font_name,
            fontSize=9.5,
            leading=13,
            alignment=4,  # Justified
            leftIndent=18,
            rightIndent=18,
            spaceAfter=16,
            textColor=colors.black,
        ),
        "Heading1": ParagraphStyle(
            "AcademicH1",
            parent=sample["Normal"],
            fontName=bold_font,
            fontSize=12,
            leading=15,
            spaceBefore=14,
            spaceAfter=4,
            keepWithNext=True,
            textColor=colors.black,
        ),
        "Heading2": ParagraphStyle(
            "AcademicH2",
            parent=sample["Normal"],
            fontName=bold_font,
            fontSize=11,
            leading=14,
            spaceBefore=10,
            spaceAfter=3,
            keepWithNext=True,
            textColor=colors.black,
        ),
        "Heading3": ParagraphStyle(
            "AcademicH3",
            parent=sample["Normal"],
            fontName=bold_italic_font,
            fontSize=10.5,
            leading=13.5,
            spaceBefore=8,
            spaceAfter=2,
            keepWithNext=True,
            textColor=colors.black,
        ),
        "Body": ParagraphStyle(
            "AcademicBody",
            parent=sample["Normal"],
            fontName=font_name,
            fontSize=10,
            leading=13.5,
            alignment=4,  # Justified
            spaceAfter=6,
            textColor=colors.black,
        ),
        "ListItem": ParagraphStyle(
            "AcademicListItem",
            parent=sample["Normal"],
            fontName=font_name,
            fontSize=10,
            leading=13.5,
            leftIndent=16,
            spaceAfter=2,
            spaceBefore=1,
            textColor=colors.black,
        ),
        "Blockquote": ParagraphStyle(
            "AcademicBlockquote",
            parent=sample["Normal"],
            fontName=italic_font,
            fontSize=10,
            leading=13.5,
            leftIndent=24,
            rightIndent=24,
            spaceBefore=4,
            spaceAfter=6,
            textColor=colors.black,
        ),
        "CodeBlock": ParagraphStyle(
            "AcademicCodeBlock",
            parent=sample["Normal"],
            fontName="Courier",
            fontSize=9,
            leading=12,
            leftIndent=16,
            spaceBefore=4,
            spaceAfter=6,
            textColor=colors.HexColor("#222222"),
        ),
        "TableCell": ParagraphStyle(
            "AcademicTableCell",
            parent=sample["Normal"],
            fontName=font_name,
            fontSize=9,
            leading=11.5,
            textColor=colors.black,
        ),
        "Caption": ParagraphStyle(
            "AcademicCaption",
            parent=sample["Normal"],
            fontName=italic_font,
            fontSize=9,
            leading=12,
            alignment=1,  # Center
            spaceBefore=4,
            spaceAfter=12,
            textColor=colors.HexColor("#333333"),
        ),
        "Reference": ParagraphStyle(
            "AcademicReference",
            parent=sample["Normal"],
            fontName=font_name,
            fontSize=9.5,
            leading=13,
            alignment=4,  # Justified
            leftIndent=24,
            firstLineIndent=-24,
            spaceAfter=4,
            textColor=colors.black,
        ),
        "MathBlock": ParagraphStyle(
            "AcademicMathBlock",
            parent=sample["Normal"],
            fontName=italic_font,
            fontSize=10,
            leading=14,
            alignment=1,  # Center
            spaceBefore=6,
            spaceAfter=6,
            textColor=colors.black,
        ),
    }
    return styles


def _create_two_column_academic_styles() -> dict[str, ParagraphStyle]:
    sample = getSampleStyleSheet()
    font_name = setup_reportlab_academic_fonts()
    bold_font = f"{font_name}-Bold" if font_name == "AcademicSerif" else "Times-Bold"
    italic_font = f"{font_name}-Italic" if font_name == "AcademicSerif" else "Times-Italic"
    bold_italic_font = (
        f"{font_name}-BoldItalic" if font_name == "AcademicSerif" else "Times-BoldItalic"
    )

    styles = {
        "Title": ParagraphStyle(
            "AcademicTitle",
            parent=sample["Normal"],
            fontName=bold_font,
            fontSize=18,
            leading=22,
            alignment=1,  # Center
            spaceBefore=4,
            spaceAfter=8,
            textColor=colors.black,
        ),
        "Author": ParagraphStyle(
            "AcademicAuthor",
            parent=sample["Normal"],
            fontName=bold_font,
            fontSize=11,
            leading=14,
            alignment=1,  # Center
            spaceBefore=2,
            spaceAfter=2,
            textColor=colors.black,
        ),
        "Affiliation": ParagraphStyle(
            "AcademicAffiliation",
            parent=sample["Normal"],
            fontName=italic_font,
            fontSize=9.5,
            leading=13,
            alignment=1,  # Center
            spaceBefore=0,
            spaceAfter=10,
            textColor=colors.black,
        ),
        "AbstractHeading": ParagraphStyle(
            "AcademicAbstractHeading",
            parent=sample["Normal"],
            fontName=bold_font,
            fontSize=9.5,
            leading=12,
            alignment=1,  # Center
            spaceBefore=8,
            spaceAfter=4,
            textColor=colors.black,
        ),
        "AbstractBody": ParagraphStyle(
            "AcademicAbstractBody",
            parent=sample["Normal"],
            fontName=font_name,
            fontSize=9.5,
            leading=12.5,
            alignment=4,  # Justified
            leftIndent=14,
            rightIndent=14,
            spaceAfter=6,
            textColor=colors.black,
        ),
        "Keywords": ParagraphStyle(
            "AcademicKeywords",
            parent=sample["Normal"],
            fontName=font_name,
            fontSize=9.0,
            leading=12,
            alignment=4,  # Justified
            leftIndent=14,
            rightIndent=14,
            spaceAfter=12,
            textColor=colors.black,
        ),
        "Heading1": ParagraphStyle(
            "AcademicH1",
            parent=sample["Normal"],
            fontName=bold_font,
            fontSize=11,
            leading=14,
            spaceBefore=10,
            spaceAfter=3,
            keepWithNext=True,
            textColor=colors.black,
        ),
        "Heading2": ParagraphStyle(
            "AcademicH2",
            parent=sample["Normal"],
            fontName=bold_font,
            fontSize=10,
            leading=13,
            spaceBefore=7,
            spaceAfter=2,
            keepWithNext=True,
            textColor=colors.black,
        ),
        "Heading3": ParagraphStyle(
            "AcademicH3",
            parent=sample["Normal"],
            fontName=bold_italic_font,
            fontSize=9.5,
            leading=12.5,
            spaceBefore=5,
            spaceAfter=2,
            keepWithNext=True,
            textColor=colors.black,
        ),
        "Body": ParagraphStyle(
            "AcademicBody",
            parent=sample["Normal"],
            fontName=font_name,
            fontSize=9.5,
            leading=12.5,
            alignment=4,  # Justified
            spaceAfter=4,
            textColor=colors.black,
        ),
        "ListItem": ParagraphStyle(
            "AcademicListItem",
            parent=sample["Normal"],
            fontName=font_name,
            fontSize=9.5,
            leading=12.5,
            leftIndent=12,
            spaceAfter=2,
            spaceBefore=1,
            textColor=colors.black,
        ),
        "Blockquote": ParagraphStyle(
            "AcademicBlockquote",
            parent=sample["Normal"],
            fontName=italic_font,
            fontSize=9.5,
            leading=12.5,
            leftIndent=14,
            rightIndent=14,
            spaceBefore=3,
            spaceAfter=4,
            textColor=colors.black,
        ),
        "CodeBlock": ParagraphStyle(
            "AcademicCodeBlock",
            parent=sample["Normal"],
            fontName="Courier",
            fontSize=8.5,
            leading=11,
            leftIndent=10,
            spaceBefore=3,
            spaceAfter=4,
            textColor=colors.HexColor("#222222"),
        ),
        "TableCell": ParagraphStyle(
            "AcademicTableCell",
            parent=sample["Normal"],
            fontName=font_name,
            fontSize=8.5,
            leading=11,
            textColor=colors.black,
        ),
        "Caption": ParagraphStyle(
            "AcademicCaption",
            parent=sample["Normal"],
            fontName=italic_font,
            fontSize=8.5,
            leading=11,
            alignment=1,  # Center
            spaceBefore=3,
            spaceAfter=8,
            textColor=colors.HexColor("#333333"),
        ),
        "Reference": ParagraphStyle(
            "AcademicReference",
            parent=sample["Normal"],
            fontName=font_name,
            fontSize=8.5,
            leading=11,
            alignment=4,  # Justified
            leftIndent=16,
            firstLineIndent=-16,
            spaceAfter=3,
            textColor=colors.black,
        ),
        "MathBlock": ParagraphStyle(
            "AcademicMathBlock",
            parent=sample["Normal"],
            fontName=italic_font,
            fontSize=9.5,
            leading=13,
            alignment=1,  # Center
            spaceBefore=4,
            spaceAfter=4,
            textColor=colors.black,
        ),
    }
    return styles


def _build_story(
    paper: PaperDraft,
    styles: dict[str, ParagraphStyle],
    review_notes: list[dict[str, str]] | None = None,
) -> list[Any]:
    story: list[Any] = []

    # Title
    story.append(Paragraph(html.escape(paper.title), styles["Title"]))

    # Author and Affiliation (if supplied)
    if paper.author_info and paper.author_info.strip():
        story.append(
            Paragraph(html.escape(paper.author_info.strip()), styles.get("Author", styles["Body"]))
        )
    if paper.affiliation and paper.affiliation.strip():
        story.append(
            Paragraph(
                html.escape(paper.affiliation.strip()), styles.get("Affiliation", styles["Body"])
            )
        )

    # Abstract
    if paper.abstract.strip():
        story.append(Paragraph("ABSTRACT", styles["AbstractHeading"]))
        story.append(Paragraph(html.escape(paper.abstract), styles["AbstractBody"]))

    # Keywords
    if paper.keywords:
        kw_html = "<b><i>Index Terms— </i></b>" + html.escape(", ".join(paper.keywords))
        story.append(Paragraph(kw_html, styles["Keywords"]))

    story.append(Spacer(1, 4))
    story.append(
        HRFlowable(width="100%", thickness=0.5, color=colors.HexColor("#CCCCCC"), spaceAfter=12)
    )

    body_sections = [
        sec
        for sec in paper.sections
        if sec.id.lower() not in ("references", "bibliography")
        and sec.heading.strip().lower() not in ("references", "bibliography", "6. references")
    ]

    figure_lookup: dict[str, Any] = {}
    if paper.figures:
        for fig in paper.figures:
            figure_lookup[fig.id] = fig
            figure_lookup[fig.filename] = fig

    # Sections with Markdown interpretation and hierarchical numbering
    for section_idx, section in enumerate(body_sections, start=1):
        clean_title = clean_heading_text(section.heading)
        heading_text = f"{section_idx}. {clean_title}"
        story.append(Paragraph(html.escape(heading_text), styles["Heading1"]))
        blocks = parse_markdown_blocks(section.content)
        render_blocks_to_pdf(
            story,
            blocks,
            styles,
            section_index=section_idx,
            numbered=True,
            figure_lookup=figure_lookup,
        )

    # References (only bibliographic entries)
    if paper.references:
        story.append(Paragraph("References", styles["Heading1"]))
        for ref_idx, ref in enumerate(paper.references, start=1):
            ref_num = ref.citation_number or ref_idx
            if ref.title and ref.publication_type:
                ref_text = format_ieee_reference(ref, ref_num)
            else:
                ref_text = ref.text.strip()
                if not re.match(r"^\[\d+\]", ref_text) and not re.match(r"^\d+\.", ref_text):
                    ref_text = f"[{ref_num}] {ref_text}"
            story.append(Paragraph(html.escape(ref_text), styles["Reference"]))

    if review_notes:
        story.append(Spacer(1, 12))
        story.append(Paragraph("Author Review Notes", styles["Heading1"]))
        story.append(
            Paragraph(
                "<i>The following unresolved research and editorial review notes pertain to this manuscript:</i>",
                styles["Body"],
            )
        )
        for n_idx, note in enumerate(review_notes, start=1):
            sec_name = html.escape(note["section"])
            msg_text = html.escape(note["message"])
            note_html = f"<b>{n_idx}. [{sec_name}]</b> {msg_text}"
            story.append(Paragraph(note_html, styles["ListItem"]))

    return story


def _render_section_content_pdf(
    story: list[Any],
    content: str,
    styles: dict[str, ParagraphStyle],
) -> None:
    blocks = content.split("\n\n")
    for block in blocks:
        trimmed = block.strip()
        if not trimmed:
            continue

        # Chart block
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
                _insert_figure_from_bytes_pdf(story, chart_bytes, caption, styles)
                continue

        # Figure
        fig_match = re.match(r"^!\[(.*?)\]\((.*?)\)$", trimmed)
        if fig_match:
            caption_text = fig_match.group(1)
            img_src = fig_match.group(2)
            _insert_figure_pdf(story, img_src, caption_text, styles)
            continue

        # Markdown Table
        lines = [line.strip() for line in trimmed.split("\n") if line.strip()]
        if len(lines) >= 2 and all(line.startswith("|") and line.endswith("|") for line in lines):
            _insert_table_pdf(story, lines, styles)
            continue

        # Block math
        if BLOCK_MATH_PATTERN.match(trimmed) or (
            trimmed.startswith("$$") and trimmed.endswith("$$")
        ):
            _insert_block_math_pdf(story, trimmed, styles)
            continue

        # Body paragraph with potential inline math
        _add_paragraph_pdf(story, trimmed, styles["Body"])


def _add_paragraph_pdf(story: list[Any], text: str, style: ParagraphStyle) -> None:
    lines = text.split("\n")
    formatted_lines: list[str] = []
    for line in lines:
        if not line.strip():
            continue
        tokens = INLINE_MATH_PATTERN.split(line)
        line_parts: list[str] = []
        for token in tokens:
            if not token:
                continue
            is_math = False
            clean = token
            if token.startswith("$$") and token.endswith("$$") and len(token) > 4:
                is_math = True
                clean = token[2:-2].strip()
            elif token.startswith(r"\[") and token.endswith(r"\]") and len(token) > 4:
                is_math = True
                clean = token[2:-2].strip()
            elif token.startswith("$") and token.endswith("$") and len(token) > 2:
                is_math = True
                clean = token[1:-1].strip()
            elif token.startswith(r"\(") and token.endswith(r"\)") and len(token) > 4:
                is_math = True
                clean = token[2:-2].strip()

            if is_math:
                line_parts.append(f"<i>{html.escape(clean)}</i>")
            else:
                line_parts.append(html.escape(token))
        formatted_lines.append("".join(line_parts))

    if formatted_lines:
        story.append(Paragraph("<br/>".join(formatted_lines), style))


def _insert_block_math_pdf(
    story: list[Any], formula_text: str, styles: dict[str, ParagraphStyle]
) -> None:
    formula = formula_text.strip()
    match = BLOCK_MATH_PATTERN.match(formula)
    if match:
        clean_latex = (match.group(1) or match.group(2) or match.group(3) or formula).strip()
    elif formula.startswith("$$") and formula.endswith("$$"):
        clean_latex = formula[2:-2].strip()
    elif formula.startswith(r"\[") and formula.endswith(r"\]"):
        clean_latex = formula[2:-2].strip()
    else:
        clean_latex = formula

    # Attempt high-DPI matplotlib rasterization in-memory
    rendered_image = _render_latex_math_to_image(clean_latex)
    if rendered_image:
        story.append(Spacer(1, 4))
        story.append(rendered_image)
        story.append(Spacer(1, 4))
    else:
        story.append(Paragraph(f"<i>{html.escape(clean_latex)}</i>", styles["MathBlock"]))


def _render_latex_math_to_image(latex_code: str) -> RLImage | None:
    try:
        fig = plt.figure(figsize=(5.5, 0.7))
        fig.text(0.5, 0.5, f"${latex_code}$", fontsize=11, ha="center", va="center")
        buf = io.BytesIO()
        fig.savefig(buf, format="png", dpi=250, bbox_inches="tight", transparent=True)
        plt.close(fig)
        buf.seek(0)

        with PILImage.open(buf) as pil_img:
            w_px, h_px = pil_img.size
            pt_w = min(420.0, max(50.0, w_px * 72.0 / 250.0))
            pt_h = pt_w * (h_px / max(w_px, 1))

        buf.seek(0)
        img = RLImage(buf, width=pt_w, height=pt_h)
        img.hAlign = "CENTER"
        return img
    except Exception as exc:
        logger.warning("Failed to render chart image for PDF: %s", exc)
        return None


def _insert_figure_from_bytes_pdf(
    story: list[Any],
    img_bytes: bytes,
    caption: str,
    styles: dict[str, ParagraphStyle],
) -> None:
    processed = process_image_for_document(img_bytes, max_width_pt=420.0, max_height_pt=280.0)
    if processed is not None:
        buf, target_pt_w, target_pt_h = processed
        rl_img = RLImage(buf, width=target_pt_w, height=target_pt_h)
        rl_img.hAlign = "CENTER"
        caption_p = Paragraph(html.escape(caption), styles["Caption"])
        story.append(KeepTogether([Spacer(1, 4), rl_img, caption_p, Spacer(1, 6)]))
    else:
        logger.warning("Rendering fallback caption for figure in PDF: %s", caption)
        placeholder_text = caption if caption.lower().startswith("figure") else f"Figure: {caption}"
        placeholder = Paragraph(f"<i>[{html.escape(placeholder_text)}]</i>", styles["Caption"])
        story.append(KeepTogether([Spacer(1, 4), placeholder, Spacer(1, 6)]))


def _insert_figure_pdf(
    story: list[Any],
    img_src: str,
    caption: str,
    styles: dict[str, ParagraphStyle],
) -> None:
    img_bytes = decode_image_source(img_src)
    if img_bytes is not None:
        _insert_figure_from_bytes_pdf(story, img_bytes, caption, styles)
    else:
        placeholder_text = caption if caption.lower().startswith("figure") else f"Figure: {caption}"
        placeholder = Paragraph(f"<i>[{html.escape(placeholder_text)}]</i>", styles["Caption"])
        story.append(KeepTogether([Spacer(1, 4), placeholder, Spacer(1, 6)]))


def _insert_table_pdf(
    story: list[Any],
    lines: list[str],
    styles: dict[str, ParagraphStyle],
) -> None:
    try:
        parsed_rows: list[list[str]] = []
        for line in lines:
            if "---" in line:
                continue
            cells = [c.strip() for c in line.strip("|").split("|")]
            parsed_rows.append(cells)
        if not parsed_rows:
            return

        num_cols = max(len(row) for row in parsed_rows)
        col_width = min(120.0, 440.0 / max(num_cols, 1))

        table_data: list[list[Paragraph]] = []
        cell_style = ParagraphStyle(
            "TableCell",
            parent=styles["Body"],
            fontSize=8.5,
            leading=11,
            alignment=0,
            spaceAfter=0,
        )
        header_style = ParagraphStyle(
            "TableHeaderCell",
            parent=cell_style,
            fontName="Times-Bold",
        )

        for r_idx, row in enumerate(parsed_rows):
            cur_style = header_style if r_idx == 0 else cell_style
            formatted_row: list[Paragraph] = []
            for c_idx in range(num_cols):
                text = row[c_idx] if c_idx < len(row) else ""
                formatted_row.append(Paragraph(html.escape(text), cur_style))
            table_data.append(formatted_row)

        table = Table(table_data, colWidths=[col_width] * num_cols)
        table.setStyle(
            TableStyle(
                [
                    ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#AAAAAA")),
                    ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#F2F2F2")),
                    ("TOPPADDING", (0, 0), (-1, -1), 4),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
                    ("LEFTPADDING", (0, 0), (-1, -1), 6),
                    ("RIGHTPADDING", (0, 0), (-1, -1), 6),
                    ("ALIGN", (0, 0), (-1, -1), "LEFT"),
                    ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ]
            )
        )
        table.hAlign = "CENTER"
        story.append(Spacer(1, 4))
        story.append(table)
        story.append(Spacer(1, 8))
    except Exception:
        story.append(Paragraph(html.escape("\n".join(lines)), styles["Body"]))
