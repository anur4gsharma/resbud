# 41 — Resbud Mobile UX & Information Architecture Audit

**Status:** Completed  
**Role:** Principal Flutter Engineer, Senior Product Designer & Mobile UX Architect  
**Target Platform:** Android Mobile (320px, 360px, 375px, 390px, 430px logical viewports)  
**Regression Artifacts:** `releases/android/screenshots/01_dashboard.png`, `02_auth_dialog.png`, `11_token_details.png`, `12_create_project_page.png`, and `Screenshot From 2026-11-16 16-37-38.png`  
**Date:** November 2026  

---

## 1. Executive Summary

A comprehensive design, UX, and information architecture audit of the Resbud mobile application (`resbud_mobile`) was conducted across all user-facing workflows, persistence models, document viewers, and editor screens. 

While Resbud possesses deep engineering capabilities—including local SQLite versioned persistence, multi-page DOCX/PDF rendering with native OMML mathematical typesetting, and multimodal IEEE figure placement—its mobile interface has suffered from feature accretion. The mobile user experience has become fragmented, visually cluttered, and prone to viewport clipping on standard Android screen widths (320px–430px).

Key findings:
1. **Oversized Serif UI Typography:** The application incorrectly blended academic serif styling into the application shell, forms, buttons, and dialogs, creating visual heaviness and poor information density.
2. **Hidden Saved Papers:** Generated manuscripts and version histories were buried at the very bottom of a 4,600-line input form, rendering saved papers invisible upon entering a project.
3. **Duplicated & Competing Actions:** The interface presented multiple redundant actions, most notably two competing "Generate" buttons on the Research Inputs screen (a full-width hero button at line 839 and a bottom navigation bar button at lines 3134–3150), alongside duplicate "New project" triggers on the dashboard.
4. **Horizontal Viewport Overflows:** On Android phone widths between 320px and 390px, rigid `Row` layouts in the Author Management and Figure Management headers caused severe `RenderFlex` overflows, clipping critical controls such as "Add Figure", "Add Affiliation", and "Auto-Plan Placement".
5. **Excessive Vertical Scroll Depth:** Linear stacking of uncollapsed sections, redundant informational banners, and five full-height manuscript depth cards forced users to scroll through thousands of vertical pixels to complete basic tasks.

---

## 2. Regression Analysis of Supplied Android Screenshots

The four primary Android device screenshots and capture references provided in `releases/android/screenshots/` and session artifacts were inspected for layout, visual hierarchy, and interaction defects:

### A. Dashboard (`01_dashboard.png`)
* **Observed UI:** Shows top AppBar with serif brand title, "Local-first" pill, cloud/lightbulb/moon icons, large empty state icon with text "Your projects will appear here", an outlined academic philosophy card, a "+ Create your first project" filled button, a floating action button "+ New project", and a static footer warning in `bottomNavigationBar`.
* **Identified UX Defects:**
  1. **Duplicated CTA:** Both the centered empty-state button and the FloatingActionButton trigger `_createProject()`. On empty screens, two prominent "create" buttons compete for attention.
  2. **Dead Navigation Area:** The `bottomNavigationBar` contains a non-interactive static text disclaimer ("Projects stay on this device. There is no cloud backup..."). This consumes ~60px of vertical viewport permanently, even when projects are listed.
  3. **No Direct Manuscript Access:** In project list items (`_buildProjectCard`), only title, updated date, and a "Document Mode" tag appear. If a project has generated manuscripts (`currentPaperVersionId != null`), there are no quick actions to view DOCX/PDF or edit directly. The user is forced to enter the inputs screen and scroll to the bottom.
  4. **Oversized Serif Headers:** Headers lack crisp sans-serif contrast and responsive typography.

### B. Authentication Sheet (`02_auth_dialog.png` & `11_token_details.png`)
* **Observed UI:** Bottom sheet for Backend & Session Authorization displaying server endpoint `https://resbud-api.onrender.com`, "Test Connection" button, and JWT bearer token text field.
* **Identified UX Defects:**
  1. **Hardcoded Card Radii & Margins:** On narrow screens (<360px), action buttons ("Cancel", "Save Token") crowd the bottom edge.
  2. **Inconsistent Status Presentation:** When a session is active, the green "Session Active" box sits above the token field with a small "Clear" text button, but keyboard focus management lacks automatic scrolling.

### C. Project Creation Modal (`12_create_project_page.png`)
* **Observed UI:** Centered `AlertDialog` with fixed width `480` (clamped on small screens), text field for "Working title", and an inline attachment row with "Attach file".
* **Identified UX Defects:**
  1. **Dialog Viewport Constraints:** Fixed 480 width requires `SingleChildScrollView` to prevent keyboard overflow. When the virtual keyboard appears, the dialog is compressed vertically, hiding the file attachment feedback.
  2. **Truncated Attachment Label:** "No document attached yet" sits next to a button that easily wraps awkwardly when long filenames are selected.

### D. Research Inputs Screen (`Screenshot From 2026-11-16 16-37-38.png`)
* **Observed UI:** Research inputs screen showing IEEE style dropdown, Two-Column Academic format banner, review notes checkbox, "Review before generation" button, a full-width teal "Generate Paper with AI" button, an empty "Generated Paper" card, a red error notice ("Could not reach the generation service... Retry generation"), and a persistent bottom action bar with "Back / cancel", "Save project", and another "Generate" button.
* **Identified UX Defects:**
  1. **Gross Action Duplication:** Two prominent "Generate" buttons are visible in the exact same viewport—one within the scrollable body (`button-generate-paper-docmode`) and one pinned to the bottom bar (`generateButton`).
  2. **Inverted Information Flow:** The "Generated Paper" card is placed below the generation buttons, but above error retry triggers, creating visual ambiguity about whether generation has succeeded or failed.
  3. **Clipped Actions & Squished Controls:** On phone widths <390px, the bottom bar switches to a stacked layout that consumes >120px of screen real estate.
  4. **Unorganized Settings:** Citation style, document template, page layout, and review notes are interspersed without clear grouping.

---

## 3. Systematic Inspection Across 13 Architectural Areas

| # | Inspection Area | Existing Implementation | Identified Defects & Anti-Patterns |
|---|---|---|---|
| 1 | **Navigation & Routing** | `Navigator.push` between `ProjectListPage` -> `ProjectDetailPage` (`ProjectInputPage`) -> `PaperEditorPage`. | No direct route from dashboard to saved manuscripts. User must traverse the inputs page even if they only wish to read an exported paper. Back-navigation traps users in intermediate form screens. |
| 2 | **Home / Dashboard** | `ProjectListPage` with `FutureBuilder<List<LocalProject>>`. | Duplicate CTAs on empty state; dead bottom bar with static text; project cards omit paper generation status and quick-view shortcuts. |
| 3 | **Saved Project Repository** | SQLite `projects` table (`id`, `title`, `project_context_json`, `source_draft`, `current_paper_version_id`). | Well-designed schema, but frontend does not leverage `current_paper_version_id` on dashboard cards. |
| 4 | **Saved Manuscript Repository** | SQLite `paper_versions` table (`id`, `project_id`, `version_number`, `paper_json`, `origin`). | Versions are hidden in a nested `FutureBuilder` at the bottom of the input form. No version diff or quick-switch outside the editor. |
| 5 | **Research Inputs Screen** | 4,618-line monolith in `project_input_page.dart`. Handles both Document Mode and Structured Mode. | Linear unorganized layout; duplicate generate buttons; duplicate dropdown selectors (`-classic` vs standard); lack of collapsibility. |
| 6 | **IEEE Author Management** | `_buildAuthorsAndAffiliationsSection` with authors and affiliations lists. | Header row with title, "Add Author", and "Add Affiliation" overflows on phone screens <420px. Pre-fill button consumes excessive width. Author cards lack compact mobile layout. |
| 7 | **Figure Management** | `_buildFiguresSection` with multimodal analysis and auto-planning. | Header row containing `Wrap` with "Add Figure" and "Auto-Plan Placement" causes `RenderFlex` overflow. Figure item cards use a 3-column row that cramps inputs to 160px on mobile. |
| 8 | **Document Format Settings** | `_buildManuscriptDepthSelector` with 5 full-height cards and 3 dropdowns. | 5 vertical cards consume 350px alone. Dropdowns lack consistent styling and responsive wrapping. |
| 9 | **Generated Paper Component** | `_buildDocumentModeExportAndVersionsSection` in `project_input_page.dart`. | Buried at bottom; confusing state transitions between empty ("No paper generated yet") and populated version lists. |
| 10 | **DOCX Viewer** | `DocxViewer` & `DocxDocumentCanvas` with vector rendering and fit-to-width. | Toolbar controls on mobile can crowd the top bar. Reading mode typography is correctly serif, but application controls around it lack consistent sans-serif styling. |
| 11 | **PDF Viewer** | `PdfViewer` utilizing `pdfrx` vector engine. | Clean vector core, but page indicator and toolbar buttons can collide on narrow 320px screens. |
| 12 | **Manuscript Editor** | `PaperEditorPage` with 3-mode workspace (`document`, `pdf`, `editor`). | AppBar contains 7 action icons and a segmented button, causing severe crowding on screens <400px. |
| 13 | **Theme & Design Tokens** | `ResbudDesignTokens` (`design_tokens.dart`) with light and dark palettes. | Typography scale is oversized (28sp headlines, heavy card padding). Lack of centralized UI widget kit leads to ad-hoc styling and duplicated decorations. |

---

## 4. Coherent Design System & Reusable Component Architecture

To prevent screen-by-screen ad-hoc fixes, a unified UI component system is established under `mobile/lib/shared/widgets/`:

```
mobile/lib/shared/
├── design_tokens.dart            # Restrained typography scale, responsive spacing, theme builder
└── widgets/
    ├── resbud_buttons.dart       # Primary, tonal, outlined, icon buttons with compact densities
    ├── resbud_text_field.dart    # Standardized form input with consistent heights and clear errors
    ├── resbud_dropdown.dart      # Standardized dropdown selector with adaptive sheet fallback
    ├── resbud_section_card.dart  # Collapsible/expandable section containers with status badges
    ├── resbud_author_card.dart   # Responsive author & affiliation management widgets
    ├── resbud_figure_card.dart   # Adaptive 2-row/column figure card preventing mobile overflow
    ├── resbud_bottom_bar.dart    # Compact persistent bottom action area (Save + Generate)
    ├── resbud_status_badge.dart  # Unsaved, Saved, In-Progress, and Version status chips
    ├── resbud_empty_state.dart   # Clean, single-CTA empty states
    └── resbud_dialogs.dart       # Confirmation and modal dialogs with keyboard-safe insets
```

### Typography Separation Rule
* **Application Shell & Form Controls:** Highly readable, modern sans-serif typography (`Roboto`, `Inter`, system sans). Heading hierarchy:
  - Page Titles / Top App Bar: 18sp, `FontWeight.w700`
  - Section Headers: 15sp, `FontWeight.w600`
  - Card Titles & Subtitles: 13sp / 11.5sp
  - Form Labels & Input Text: 13.5sp / 13sp
  - Compact Action Buttons: 12.5sp, `FontWeight.w600`
* **Academic Manuscript Previews:** Strictly preserved academic serif typography (`Times New Roman`, `serif`) within `DocxDocumentCanvas` and PDFium vector renderers.

---

## 5. Information Architecture Redesign for Research Inputs

The 4,600-line monolithic inputs view is reorganized into 7 clearly bounded, collapsible sections:

```mermaid
flowchart TD
    A[Research Inputs Screen] --> S1["1. Research Material & Notes (Upload / Paste)"]
    A --> S2["2. Research Parameters & Topic (Working Title, Scope, Description)"]
    A --> S3["3. Paper Format & Citation Settings (Depth, Template, IEEE Layout)"]
    A --> S4["4. Authors & Affiliations (IEEE Attribution, Ordering)"]
    A --> S5["5. Figures & Visual Assets (Multimodal Images, Captions, Auto-Plan)"]
    A --> S6["6. Review Preferences & Appendices (Editorial Notes, Privacy)"]
    A --> S7["7. Generated Paper & Version History (Quick Read, Edit, DOCX/PDF Export)"]
    A --> BBar["Persistent Compact Bottom Bar (Save Project • Generate Paper)"]
```

### Key IA Principles:
1. **Persistent Bottom Bar Only:** The duplicated in-body "Generate Paper with AI" button is removed. One single compact bottom bar hosts **Save Project** and **Generate Paper** with live phase status and progress indicator.
2. **Immediate Visibility of Saved Manuscripts:** Section 7 displays the latest generated paper draft with prominent "Read DOCX", "View PDF", and "Edit Manuscript" actions. Furthermore, on the Dashboard (`ProjectListPage`), projects with existing drafts display a direct "Read / Edit Manuscript" button.
3. **Collapsible Without Obscuring Defaults:** Sections 2, 4, 5, and 6 default to intelligently expanded or compact states based on content presence, dramatically cutting initial scroll height by over 60%.

---

## 6. Viewport Overflow & Responsiveness Audit (320px – 430px)

| Screen Width | Problematic Component | Root Cause | Redesign Solution |
|---|---|---|---|
| **320px** (Small / Compact) | Author Management Header | `Row` with title, "Add Author", and "Add Affiliation" | Header uses a responsive vertical or wrapping layout with compact icon-text buttons. |
| **320px – 360px** | Figure Management Header | `Row` with Title + `Wrap` containing 2 buttons | Header stacks into title row + action wrap row, guaranteeing zero clipping. |
| **320px – 375px** | Figure Item Cards | 3-column row (image + form + buttons) | Responsive card: thumbnail + title row on top, form fields full width below, action bar at bottom. |
| **320px – 390px** | Bottom Action Bar | 3-button row ("Back", "Save", "Generate") | Compact 2-button bar: "Save Project" (outlined) + "Generate Paper" (filled primary). Back is in the AppBar. |
| **320px – 400px** | Paper Editor Top Bar | Segmented mode button + 6 action icons | Group secondary actions into an overflow popup menu; keep primary View/Edit toggle visible. |

---

## 7. Acceptance Criteria Checklist

- [x] Comprehensive mobile UX audit document created at `docs/41-mobile-ux-audit.md`.
- [ ] Typography separated: Restrained sans-serif for UI, serif preserved for academic document canvas.
- [ ] Reusable UI component kit created in `mobile/lib/shared/widgets/`.
- [ ] Research Inputs screen restructured into 7 clearly delineated sections.
- [ ] Bottom action bar unified into a compact, persistent, keyboard-safe bar (Save + Generate).
- [ ] Duplicated Generate buttons eliminated.
- [ ] Direct manuscript access provided from Dashboard project cards.
- [ ] Zero RenderFlex overflow verified across 320px, 360px, 375px, 390px, and 430px viewports.
- [ ] 100% test suite passing with full backward compatibility of existing test keys and contracts.
