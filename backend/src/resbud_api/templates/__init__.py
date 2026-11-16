"""Document publication templates for Resbud academic publishing."""

from resbud_api.templates.base import (
    DocumentTemplateConfig,
    HeadingStyleConfig,
    MarginsConfig,
    TypographyConfig,
)
from resbud_api.templates.ieee_conference import (
    IEEE_CONFERENCE_CONFIG,
    calculate_ieee_author_grid,
    format_ieee_heading_1,
    format_ieee_heading_2,
    format_ieee_heading_3,
    int_to_letter,
    int_to_roman,
    validate_author_metadata,
)
from resbud_api.templates.registry import (
    DEFAULT_TEMPLATE_CONFIG,
    get_template,
    list_templates,
    register_template,
)

__all__ = [
    "DEFAULT_TEMPLATE_CONFIG",
    "DocumentTemplateConfig",
    "HeadingStyleConfig",
    "IEEE_CONFERENCE_CONFIG",
    "MarginsConfig",
    "TypographyConfig",
    "calculate_ieee_author_grid",
    "format_ieee_heading_1",
    "format_ieee_heading_2",
    "format_ieee_heading_3",
    "get_template",
    "int_to_letter",
    "int_to_roman",
    "list_templates",
    "register_template",
    "validate_author_metadata",
]
