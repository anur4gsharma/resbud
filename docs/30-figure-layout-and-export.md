# Resbud Architecture: Academic Figure Layout, Rendering, and Export Pipeline

**Document Reference**: `docs/30-figure-layout-and-export.md`  
**Date**: November 16, 2026  
**Status**: Implemented & Verified  

---

## 1. Academic Document Geometry & Figure Placement

Academic publishing standards (IEEE Transactions, ACM, Springer, Elsevier) require strict document geometry for visual figures:

| Layout Style | Figure Placement Mode | Target Width Budget | Max Height Budget | Alignment & Rules |
| :--- | :--- | :--- | :--- | :--- |
| **Standard Academic (Single-Column)** | Default (`column_width`) | 460 pt (~6.0 in) | 280 pt | Centered, aspect-ratio preserved, KeepTogether with caption |
| **Standard Academic (Single-Column)** | Spanning (`full_width`) | 460 pt (~6.2 in) | 280 pt | Centered, aspect-ratio preserved, KeepTogether with caption |
| **Two-Column Academic (IEEE)** | Default (`column_width`) | 233 pt (~3.2 in) | 220 pt | Strictly fits within 1 column; zero gutter crossing |
| **Two-Column Academic (IEEE)** | Spanning (`full_width`) | 460 pt (~6.2 in) | 280 pt | Spans across both columns / full printable page width |

---

## 2. In-Memory Export Resolution Pipeline

To prevent SQLite bloat while ensuring high-fidelity rendering, drafts store lightweight figure markers, which are resolved on-demand during export:

```
[Local SQLite Storage]
Section text: "As observed in ![Convergence Analysis](fig_1), speedup is achieved."
Figure assets: Stored safely in FileProjectImageStorage under storageKey.
                                 |
                                 v
[User clicks "Download PDF" or "Download DOCX"]
                                 |
                                 v
[resolveFiguresForExport() in figure_export_resolver.dart]
1. Queries repository.listProjectFigures(projectId)
2. Loads binary bytes via repository.getFigureBytes(storageKey)
3. Replaces '(fig_1)' with '(data:image/png;base64,iVBORw0K...#placement=column_width)'
                                 |
                                 v
[FastAPI Backend /api/v1/exports/pdf & /api/v1/exports/docx]
1. decode_image_source() safely strips '#placement=...' and base64-decodes bytes
2. process_image_for_document() normalizes with Pillow:
   - EXIF camera rotation corrected via ImageOps.exif_transpose()
   - Alpha transparency flattened over solid clean white background
   - Animated GIFs converted via documented first-frame policy
   - Max resolution capped at 1600px to prevent multi-megabyte document bloat
3. ReportLab / python-docx embeds image and caption inside KeepTogether block
                                 |
                                 v
[Client downloads fully rendered, professional PDF / DOCX with actual graphics embedded]
```

---

## 3. Image Normalization & Pillow Processing

The backend image processing engine (`resbud_api/services/image_processor.py`) guarantees robust in-memory handling without retaining files on disk (zero server retention):

- **Supported Formats**: PNG, JPG, JPEG, WebP, GIF, BMP, TIFF.
- **Transparency Handling**: RGBA, LA, and palette-based images with transparency masks are composited onto a pure white background (`#FFFFFF`) to prevent black box artifacts in PDF/Word viewers.
- **Aspect Ratio Preservation**:
  ```python
  scale = min(max_width_pt / orig_w, max_height_pt / orig_h, 1.0)
  target_w = orig_w * scale
  target_h = orig_h * scale
  ```
  Images are never stretched or distorted.
- **Orphan Caption Prevention**:
  ```python
  story.append(KeepTogether([Spacer(1, 4), rl_img, caption_p, Spacer(1, 6)]))
  ```
  The figure graphic and caption are guaranteed to remain on the same page.

---

## 4. Editorial Review Notes Appendix Control

The preference `"Include review notes appendix in exported document"` (`include_review_notes_appendix: bool`) provides granular user control:

1. **Disabled (`false`, default for publication submissions)**:
   - All bracketed review notes (`[Note: ...]`, `[Methodological Scope Note: ...]`) are stripped from section prose.
   - Legitimate academic citations (`[1]`, `[1-3]`, `[12, 15]`) and mathematical intervals (`[0, 1]`) are preserved.
   - No review notes appendix is attached.
2. **Enabled (`true`, for editorial review and co-author feedback)**:
   - Retains author review notes in an official appendix section titled `"Author Review Notes"`.
   - Lists all unresolved warnings, missing dataset flags, and methodological limitations for collaborative revision.

---

## 5. Automated Verification Summary

- **Backend Pytest Suite**: 206 tests passing, including tests for multi-format image embedding, `full_width` vs `column_width` placement, and review notes appendix control in both PDF and DOCX formats.
- **Mobile Flutter Suite**: 197 tests passing, verifying figure resolution, image persistence lifecycle, single/two-column selection, and UI responsiveness.
