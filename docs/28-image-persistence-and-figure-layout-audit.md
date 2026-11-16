# Resbud Audit: Image Persistence, Figure Rendering, and Export Lifecycle

**Document Reference**: `docs/28-image-persistence-and-figure-layout-audit.md`  
**Date**: November 16, 2026  
**Status**: Root Causes Confirmed & Architectural Plan Established  

---

## 1. Executive Summary & Problem Statement

Users reported that while images can be imported into Resbud research projects, saving a project containing images consistently fails on Android devices with:
- Project status: **Unsaved**
- Error banner: *"The project could not be saved. Your last saved copy remains available."*

Furthermore:
- Closing and reopening projects with attached images loses or corrupts visual research assets.
- Exporting generated manuscripts containing attached figures often renders only text placeholders `[Figure 1: ...]` instead of genuine embedded image graphics.
- Figure positioning in single-column and IEEE two-column academic formats requires strict geometric budgeting (column width vs. full-width spanning).

---

## 2. Reproduction & Root Cause Analysis

### 2.1 Failure 1: The 2 MiB Android SQLite `CursorWindow` Breach
In `mobile/lib/features/project_input/project_input_page.dart`:
```dart
_attachedFigures.add({
  'id': 'fig_$figNumber',
  'name': picked.name,
  'caption': 'Figure $figNumber: $titleName',
  'description': '...',
  'base64': b64,      // Multi-megabyte Base64 string
  'bytes': picked.bytes, // Raw Uint8List image buffer
});
```
When `_save()` invokes `repository.updateProjectInputs()`, the entire `_attachedFigures` list is serialized directly into `project_context_json` inside the SQLite `projects` table:
1. In Dart, `Uint8List` implements `List<int>`. When encoded via `jsonEncode()`, every single byte is formatted as an ASCII integer array: `[137, 80, 78, 71, ...]`.
2. A single 2.5 MiB image expands to **over 12 MiB of ASCII JSON text** for the integer array, plus another **3.4 MiB** for the `base64` string. A project with two images easily exceeds **30 MiB**.
3. Following the update, `updateProjectInputs` immediately executes `await getProject(projectId)`, which executes `SELECT * FROM projects WHERE id = ?`.
4. In Android, the native Android SQLite layer (`android.database.sqlite.SQLiteCursor`) utilizes an internal `CursorWindow` to read table rows across the JNI bridge. The Android OS enforces a hard ceiling of **2,097,152 bytes (2 MiB)** per `CursorWindow`.
5. When `CursorWindow.allocRow()` fails to fit the 30 MiB row, Android throws:
   `android.database.sqlite.SQLiteBlobTooBigException: Row too big to fit into CursorWindow requiredPos=0, totalRows=1`
6. In `project_input_page.dart`:
   ```dart
   } on Object {
     setState(() => _saving = false);
     _showMessage('The project could not be saved. Your last saved copy remains available.', isError: true);
     return false;
   }
   ```
   The exception was caught and converted into the exact user-reported error message, leaving the project in the **Unsaved** state.

### 2.2 Failure 2: Disconnection Between Figure Markers and Export Data
During paper generation, the LLM is prompted to insert figure references using short identifiers: `![Caption](fig_1)`.
When the resulting `PaperDraftPayload` is sent to `/api/v1/exports/pdf` or `/api/v1/exports/docx`:
1. The backend renderer looks at the `src` attribute of each `FigureBlock`.
2. If `src` is `"fig_1"`, `decode_image_source("fig_1")` fails because `"fig_1"` is not a base64 data URI.
3. The backend fell back to rendering a text placeholder `[Figure 1: ...]` instead of the image.
4. To embed actual figures, the export client must resolve figure IDs to their actual image data and provide them in the export payload (or resolve them into the document markdown blocks).

### 2.3 Failure 3: Ephemeral File Storage Across App Restarts
Previously, picked image bytes were held only in memory in the UI widget state. If the user navigated away, restarted the application, or restored a version snapshot, the raw image bytes were lost unless reconstituted from a durable local asset directory.

---

## 3. Architecture for Permanent Image Persistence & Layout

### 3.1 Separate Metadata from Binary Assets
1. **SQLite (`project_figures` table)**:
   Stores figure metadata (IDs, project ID, filenames, MIME types, dimensions, file sizes, captions, alt text, display order, placement mode, and relative storage keys).
2. **Durable File Storage (`ProjectImageStorage`)**:
   - **Native (Android / Linux)**: Persists image files to the application's durable support directory: `${appDocDir}/projects/${projectId}/figures/${figureId}.${ext}`.
   - **Web**: Uses dedicated IndexedDB / SQLite blob table isolated by single-item keys, completely avoiding `CursorWindow` overflows.
3. **Project Context Hygiene**:
   `project_context_json` only stores lightweight figure descriptors (IDs, captions, storage keys). Raw byte arrays and giant data URIs are never embedded into the main `projects` table row.

### 3.2 Professional Academic Figure Alignment
- **Single-Column**: Centered horizontally, aspect ratio preserved, max width calculated against printable page boundaries (default ~5.5 inches in DOCX, ~460 pt in PDF).
- **Two-Column**:
  - `column_width` (Default): Constrained to single-column width ((PageWidth - Margins - Gutter) / 2 = ~3.2 inches in DOCX, ~225 pt in PDF).
  - `full_width`: Explicit option for wide architectures, spanning both columns with clean section breaks and continuous reading flow.
- **Figure & Caption Grouping**: Kept together via ReportLab `KeepTogether` and Word paragraph `keep_with_next` attributes to prevent orphaned captions.
