"""Base abstractions and configuration dataclasses for document templates."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Literal

PageLayoutType = Literal["single_column", "two_column_academic"]
CitationFormatType = Literal["user_supplied", "apa_7", "ieee", "other"]
EquationFormatType = Literal["omml", "latex_fallback"]


@dataclass(frozen=True)
class MarginsConfig:
    """Document margin settings in inches."""

    top: float
    bottom: float
    left: float
    right: float


@dataclass(frozen=True)
class TypographyConfig:
    """Font family and sizing configuration in points."""

    font_family: str
    title_size_pt: float
    subtitle_size_pt: float
    author_name_size_pt: float
    author_detail_size_pt: float
    abstract_heading_size_pt: float
    abstract_body_size_pt: float
    heading_1_size_pt: float
    heading_2_size_pt: float
    heading_3_size_pt: float
    body_size_pt: float
    caption_size_pt: float
    table_cell_size_pt: float
    reference_size_pt: float


@dataclass(frozen=True)
class HeadingStyleConfig:
    """Rules for formatting headings at levels 1, 2, and 3."""

    level_1_case: Literal["upper", "title", "preserve"] = "upper"
    level_1_alignment: Literal["center", "left", "justify"] = "center"
    level_1_small_caps: bool = True
    level_1_bold: bool = True
    level_1_numbering: Literal["roman", "arabic", "none"] = "roman"

    level_2_case: Literal["upper", "title", "preserve"] = "title"
    level_2_alignment: Literal["center", "left", "justify"] = "left"
    level_2_italic: bool = True
    level_2_bold: bool = False
    level_2_numbering: Literal["letter", "arabic", "none"] = "letter"

    level_3_case: Literal["upper", "title", "preserve"] = "title"
    level_3_alignment: Literal["center", "left", "justify"] = "left"
    level_3_italic: bool = True
    level_3_bold: bool = False
    level_3_numbering: Literal["arabic_paren", "arabic", "none"] = "arabic_paren"


@dataclass(frozen=True)
class DocumentTemplateConfig:
    """Centralized configuration for a predefined document publication format."""

    template_id: str
    display_name: str
    category: str
    default_page_layout: PageLayoutType
    default_typography: TypographyConfig
    default_equation_format: EquationFormatType
    default_citation_format: CitationFormatType
    default_reference_format: str
    page_width_inch: float = 8.5
    page_height_inch: float = 11.0
    margins: MarginsConfig = field(
        default_factory=lambda: MarginsConfig(top=0.75, bottom=0.75, left=0.625, right=0.625)
    )
    column_count: int = 2
    column_gap_inch: float = 0.25
    column_spacing_twips: int = 360
    heading_styles: HeadingStyleConfig = field(default_factory=HeadingStyleConfig)
    line_spacing: float = 1.05
    space_after_body_pt: float = 4.0
    abstract_prefix: str = "Abstract—"
    index_terms_prefix: str = "Index Terms—"
    references_heading: str = "References"
    acknowledgment_heading: str = "Acknowledgment"

    def to_metadata(self) -> dict[str, Any]:
        """Serialize public metadata dictionary for API and UI consumers."""
        return {
            "template_id": self.template_id,
            "display_name": self.display_name,
            "category": self.category,
            "default_page_layout": self.default_page_layout,
            "default_typography": self.default_typography.font_family,
            "default_equation_format": self.default_equation_format,
            "default_citation_format": self.default_citation_format,
            "default_reference_format": self.default_reference_format,
            "page_dimensions": f"{self.page_width_inch}x{self.page_height_inch} in",
            "column_count": self.column_count,
        }
