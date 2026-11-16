"""Robust in-memory image normalization and scaling for academic document rendering."""

from __future__ import annotations

import base64
import io
import logging
import re

from PIL import Image as PILImage
from PIL import ImageFile, ImageOps

ImageFile.LOAD_TRUNCATED_IMAGES = True

logger = logging.getLogger(__name__)

# Max resolution in pixels for embedded document figures to ensure visual clarity
# while preventing multi-megabyte PDF/DOCX bloating and memory pressure.
MAX_FIGURE_PIXEL_DIM = 1600

# Base64 data URI pattern
DATA_URI_PATTERN = re.compile(r"^data:[^;]+;base64,", re.IGNORECASE)


def decode_image_source(img_src: str) -> bytes | None:
    """Safely decode an image source string (data URI or raw base64) into bytes."""
    try:
        clean = img_src.strip()
        if "#" in clean:
            clean = clean.split("#", 1)[0]
        if "base64," in clean:
            clean = clean.split("base64,", 1)[1]
        # Remove any whitespace or newline characters inserted during transmission
        clean = re.sub(r"\s+", "", clean)
        # Pad base64 if needed
        padding = len(clean) % 4
        if padding:
            clean += "=" * (4 - padding)
        return base64.b64decode(clean)
    except Exception as exc:
        logger.warning("Failed to decode base64 image data: %s", exc)
        return None


def process_image_for_document(
    img_bytes: bytes,
    max_width_pt: float = 420.0,
    max_height_pt: float = 300.0,
) -> tuple[io.BytesIO, float, float] | None:
    """Safely normalize and scale an image for ReportLab PDF or Word DOCX rendering.

    Handles:
    - Supported formats: PNG, JPG, JPEG, WebP, GIF, BMP, TIFF.
    - Transparent backgrounds (RGBA, LA, palette-with-alpha flattened over solid white).
    - Animated GIF files using a documented first-frame policy.
    - EXIF orientation (rotated smartphone camera photos).
    - Portrait and landscape aspect ratios (preserves aspect ratio without stretching).
    - Large images (downscaled to sensible publication resolutions).
    - Corrupted or unrecognized image bytes (returns None gracefully).

    Returns:
        A tuple of (BytesIO containing JPEG bytes, target_width_pt, target_height_pt)
        or None if image cannot be processed.
    """
    if not img_bytes:
        return None

    try:
        with PILImage.open(io.BytesIO(img_bytes)) as raw_img:
            # 1. Documented first-frame policy for animated GIFs or multi-page formats
            try:
                raw_img.seek(0)
            except Exception:
                pass

            # 2. Correct EXIF orientation (e.g. mobile photo taken in portrait)
            try:
                oriented_img = ImageOps.exif_transpose(raw_img)
            except Exception:
                oriented_img = raw_img

            working_img = oriented_img if oriented_img is not None else raw_img

            # 3. Handle color modes and transparency:
            # ReportLab and Word DOCX can fail or produce black boxes around transparent pixels.
            # Convert alpha channels and transparent palettes cleanly onto an academic white canvas.
            if working_img.mode in ("RGBA", "LA") or (
                working_img.mode == "P" and "transparency" in working_img.info
            ):
                rgba_img = working_img.convert("RGBA")
                white_bg = PILImage.new("RGB", rgba_img.size, (255, 255, 255))
                # Paste using alpha channel as mask
                alpha_channel = rgba_img.split()[3]
                white_bg.paste(rgba_img, mask=alpha_channel)
                normalized_img = white_bg
            elif working_img.mode != "RGB":
                normalized_img = working_img.convert("RGB")
            else:
                normalized_img = working_img

            orig_w, orig_h = normalized_img.size
            if orig_w <= 0 or orig_h <= 0:
                return None

            # 4. Downscale oversized images exceeding sensible document budget (e.g., 4000x3000)
            if orig_w > MAX_FIGURE_PIXEL_DIM or orig_h > MAX_FIGURE_PIXEL_DIM:
                scale = min(MAX_FIGURE_PIXEL_DIM / orig_w, MAX_FIGURE_PIXEL_DIM / orig_h)
                new_w = max(1, int(orig_w * scale))
                new_h = max(1, int(orig_h * scale))
                normalized_img = normalized_img.resize((new_w, new_h), PILImage.Resampling.LANCZOS)
                orig_w, orig_h = normalized_img.size

            # 5. Export normalized image as high-quality JPEG (quality=92)
            # JPEG is universally supported by PDF DCTDecode and Word DOCX, avoiding format mismatches.
            out_buf = io.BytesIO()
            normalized_img.save(out_buf, format="JPEG", quality=92, optimize=True)
            out_buf.seek(0)

            # 6. Compute target document dimensions in points (72 pt/inch)
            # Default academic resolution assumes ~150-200 DPI for inline figures
            aspect = orig_h / max(orig_w, 1)
            # Minimum width 120 pt, max bounded by available printable column width
            target_w = float(min(max_width_pt, max(120.0, orig_w * 72.0 / 160.0)))
            target_h = float(target_w * aspect)

            # Restrict maximum height to avoid page or column frame overflow
            if target_h > max_height_pt:
                target_h = float(max_height_pt)
                target_w = float(target_h / aspect)

            # Final sanity bounds
            if target_w > max_width_pt:
                target_w = max_width_pt
                target_h = target_w * aspect

            return out_buf, target_w, target_h

    except Exception as exc:
        logger.warning("Failed to normalize image for document: %s", exc)
        return None
