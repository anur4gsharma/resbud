"""Template registry for registering and retrieving document publication formats."""

from __future__ import annotations

from resbud_api.templates.base import (
    DocumentTemplateConfig,
    HeadingStyleConfig,
    MarginsConfig,
    TypographyConfig,
)
from resbud_api.templates.ieee_conference import IEEE_CONFERENCE_CONFIG

DEFAULT_TYPOGRAPHY = TypographyConfig(
    font_family="Times New Roman",
    title_size_pt=18.0,
    subtitle_size_pt=12.0,
    author_name_size_pt=11.0,
    author_detail_size_pt=9.5,
    abstract_heading_size_pt=10.0,
    abstract_body_size_pt=10.0,
    heading_1_size_pt=12.0,
    heading_2_size_pt=11.0,
    heading_3_size_pt=10.5,
    body_size_pt=10.5,
    caption_size_pt=9.0,
    table_cell_size_pt=9.0,
    reference_size_pt=9.5,
)

DEFAULT_TEMPLATE_CONFIG = DocumentTemplateConfig(
    template_id="default",
    display_name="Standard Academic Research Paper",
    category="Academic Research",
    default_page_layout="single_column",
    default_typography=DEFAULT_TYPOGRAPHY,
    default_equation_format="omml",
    default_citation_format="user_supplied",
    default_reference_format="Standard Bibliography",
    page_width_inch=8.5,
    page_height_inch=11.0,
    margins=MarginsConfig(top=1.0, bottom=1.0, left=1.0, right=1.0),
    column_count=1,
    column_gap_inch=0.0,
    column_spacing_twips=720,
    heading_styles=HeadingStyleConfig(
        level_1_case="title",
        level_1_alignment="left",
        level_1_small_caps=False,
        level_1_bold=True,
        level_1_numbering="arabic",
        level_2_case="title",
        level_2_alignment="left",
        level_2_italic=False,
        level_2_bold=True,
        level_2_numbering="arabic",
        level_3_case="title",
        level_3_alignment="left",
        level_3_italic=True,
        level_3_bold=True,
        level_3_numbering="arabic",
    ),
    line_spacing=1.15,
    space_after_body_pt=6.0,
    abstract_prefix="Abstract—",
    index_terms_prefix="Keywords: ",
    references_heading="References",
    acknowledgment_heading="Acknowledgment",
)

_REGISTRY: dict[str, DocumentTemplateConfig] = {
    "default": DEFAULT_TEMPLATE_CONFIG,
    "generic_academic": DEFAULT_TEMPLATE_CONFIG,
    "ieee_conference": IEEE_CONFERENCE_CONFIG,
}


def register_template(config: DocumentTemplateConfig) -> None:
    """Register a new document template configuration."""
    _REGISTRY[config.template_id] = config


def get_template(template_id: str | None) -> DocumentTemplateConfig:
    """Retrieve template configuration by internal ID, falling back to default."""
    if not template_id:
        return DEFAULT_TEMPLATE_CONFIG
    return _REGISTRY.get(template_id.lower().strip(), DEFAULT_TEMPLATE_CONFIG)


def list_templates() -> list[DocumentTemplateConfig]:
    """Return all registered unique document templates."""
    seen: set[str] = set()
    result: list[DocumentTemplateConfig] = []
    for t in _REGISTRY.values():
        if t.template_id not in seen:
            seen.add(t.template_id)
            result.append(t)
    return result
