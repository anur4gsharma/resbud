"""Academic chart generation service for manuscript figures and visualizations."""

from __future__ import annotations

import io
import logging
from typing import Any

import matplotlib.pyplot as plt

logger = logging.getLogger(__name__)

# Colorblind-safe academic palette (Okabe-Ito / ColorBrewer)
ACADEMIC_COLORS = [
    "#0072B2",  # Blue
    "#D55E00",  # Vermilion
    "#009E73",  # Bluish green
    "#CC79A7",  # Reddish purple
    "#E69F00",  # Orange
    "#56B4E9",  # Sky blue
    "#F0E442",  # Yellow
]


def render_academic_chart_from_spec(spec_text: str) -> bytes | None:
    """Parse declarative chart block and synthesize a publication-quality 300 DPI chart."""
    try:
        spec = _parse_chart_spec(spec_text)
        if not spec or "values" not in spec:
            return None

        chart_type = spec.get("type", "bar").lower()
        title = spec.get("title", "Figure")
        xlabel = spec.get("xlabel", "")
        ylabel = spec.get("ylabel", "Value")
        labels = spec.get("labels", [f"Item {i + 1}" for i in range(len(spec["values"]))])
        values = spec["values"]

        fig, ax = plt.subplots(figsize=(5.5, 3.2), dpi=300)

        # Apply academic styling
        plt.rcParams.update(
            {
                "font.family": "serif",
                "font.serif": ["Times New Roman", "DejaVu Serif"],
            }
        )

        if chart_type == "line":
            ax.plot(
                labels,
                values,
                marker="o",
                color=ACADEMIC_COLORS[0],
                linewidth=1.8,
                markersize=5,
                label=spec.get("series_name", "Observation"),
            )
            ax.grid(True, linestyle="--", alpha=0.4)
        elif chart_type == "scatter":
            ax.scatter(
                labels, values, color=ACADEMIC_COLORS[1], s=40, edgecolors="#333333", alpha=0.85
            )
            ax.grid(True, linestyle="--", alpha=0.4)
        else:  # Default: bar chart
            num_bars = len(values)
            colors = [ACADEMIC_COLORS[i % len(ACADEMIC_COLORS)] for i in range(num_bars)]
            bars = ax.bar(
                labels, values, color=colors, width=0.55, edgecolor="#333333", linewidth=0.8
            )
            ax.grid(axis="y", linestyle="--", alpha=0.4)
            ax.set_axisbelow(True)
            for bar in bars:
                h = bar.get_height()
                ax.annotate(
                    f"{h:.1f}" if isinstance(h, float) else f"{h}",
                    xy=(bar.get_x() + bar.get_width() / 2, h),
                    xytext=(0, 3),
                    textcoords="offset points",
                    ha="center",
                    va="bottom",
                    fontsize=8.5,
                )

        ax.set_title(title, fontsize=11, fontweight="bold", pad=8)
        if xlabel:
            ax.set_xlabel(xlabel, fontsize=9.5)
        if ylabel:
            ax.set_ylabel(ylabel, fontsize=9.5)
        ax.tick_params(axis="both", which="major", labelsize=8.5)

        buf = io.BytesIO()
        fig.savefig(buf, format="png", dpi=300, bbox_inches="tight")
        plt.close(fig)
        return buf.getvalue()
    except Exception as exc:
        logger.warning("Failed to render academic chart from spec: %s", exc)
        return None


def _parse_chart_spec(text: str) -> dict[str, Any]:
    """Extract key-value pairs from yaml-like chart block."""
    spec: dict[str, Any] = {}
    for raw_line in text.strip().split("\n"):
        line = raw_line.strip()
        if not line or ":" not in line:
            continue
        key, val = line.split(":", 1)
        key = key.strip().lower()
        val = val.strip()

        if val.startswith("[") and val.endswith("]"):
            raw_items = [v.strip() for v in val[1:-1].split(",")]
            parsed_items: list[Any] = []
            for item in raw_items:
                try:
                    parsed_items.append(float(item) if "." in item else int(item))
                except ValueError:
                    parsed_items.append(item.strip("'\""))
            spec[key] = parsed_items
        else:
            spec[key] = val.strip("'\"")
    return spec
