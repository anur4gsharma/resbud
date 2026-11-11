# Architectural Specification: Single Authoritative PDF Viewer Architecture

## 1. Defect Audit & Root Cause Analysis

### Symptoms
In previous versions of Resbud, viewing a compiled academic PDF displayed two stacked, competing toolbars with conflicting state:
1. **Flutter Toolbar (Top Bar):** Displayed `Page 1 of 1`, zoom controls, and export buttons.
2. **Browser Embedded PDF Toolbar (Bottom Bar):** Displayed `1 / 8`, separate zoom controls, rotate, download, and print actions.

### Root Causes
1. **Unconstrained Web `<iframe>` Embedding:** On web platforms, `buildPdfWebEmbed()` created an `<iframe>` with a raw PDF blob URL (`blob:http://...`). Modern browsers (Chrome, Chromium, Brave, Edge, Firefox) inject their native internal PDF viewer inside iframes unless explicitly instructed otherwise. This resulted in two nested toolbars occupying the viewport.
2. **Hardcoded Initial Page Count:** `_PdfViewerState` initialized `_totalPages = 1`. Because the web viewer loaded the binary directly via iframe without passing metadata back to Dart, `_totalPages` never updated to reflect the actual page count of the compiled document.
3. **Canvas Fallback Override:** When the fallback canvas mounted during testing or layout calculation, its callback `onPageCountResolved` overwrote `_totalPages` with an estimated canvas page count based solely on section height rather than the authoritative compiled PDF binary.

---

## 2. The Single Authoritative PDF Viewer Design

Resbud establishes **exactly one authoritative PDF viewing interface** across all platforms.

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ Resbud Single Authoritative PDF Toolbar (Key: 'pdf-viewer-toolbar')                    │
│ [Version V1.0] [DOCX] | [< Prev] [Page 1 of 8] [Next >] | [-] [100%] [+] [Fit] | [Rotate] [Print] [PDF] [DOCX] [Edit] [⛶] │
└────────────────────────────────────────────────────────────────────────────────────────┘
│                                                                                        │
│                               Embedded PDF Document View                               │
│                         (Native browser toolbar suppressed via                         │
│                           #toolbar=0&navpanes=0&scrollbar=1)                           │
│                                                                                        │
│                                           8.5" x 11"                                   │
│                                    Academic Publication Canvas                         │
│                                                                                        │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

### Key Principles

1. **One Authoritative Control Bar:** All document controls reside exclusively in Flutter's `_buildViewerToolbar()`.
2. **Browser Toolbar Suppression:** The iframe blob URL appends `#toolbar=0&navpanes=0&scrollbar=1`, completely disabling Chromium and Firefox native toolbar chrome.
3. **Binary Metadata Extraction:** Page count is determined immediately from the PDF binary byte stream on load.
4. **Full Controller Integration:** Previous/Next, direct jumping, zoom scaling, 90° clockwise rotation, system print, and file downloads are coordinated through the single interface.

---

## 3. Authoritative Metadata Extraction

To ensure that the toolbar immediately displays the true page count (e.g., `Page 1 of 8`) before rendering or layout calculation:

```dart
int extractPdfPageCount(Uint8List bytes) {
  final text = latin1.decode(bytes, allowInvalid: true);
  // Scan for PDF Page dictionary objects
  final pageMatches = RegExp(r'/Type\s*/Page\b').allMatches(text);
  if (pageMatches.isNotEmpty) {
    return pageMatches.length;
  }
  // Fallback to /Pages /Count dictionary
  final countMatches = RegExp(r'/Count\s+(\d+)').allMatches(text);
  if (countMatches.isNotEmpty) {
    for (final m in countMatches) {
      final parsed = int.tryParse(m.group(1) ?? '1');
      if (parsed != null && parsed > 0) return parsed;
    }
  }
  return 1;
}
```

When `_pdfBytes` is loaded or updated, `_totalPages` is set directly from `extractPdfPageCount(_pdfBytes!)`. Fallback canvas callbacks are prohibited from overriding `_totalPages` when compiled PDF bytes are present.

---

## 4. Control Synchronization

| Toolbar Control | ValueKey | Action | Web Mechanism |
| :--- | :--- | :--- | :--- |
| **Previous Page** | `button-pdf-page-prev` | `_goToPage(_currentPage - 1)` | Updates `#page=N` via `window.setPdfViewerPage` |
| **Next Page** | `button-pdf-page-next` | `_goToPage(_currentPage + 1)` | Updates `#page=N` via `window.setPdfViewerPage` |
| **Page Indicator** | `pdf-page-indicator` | Displays `Page X of Y` | Synchronized with `_currentPage` and `_totalPages` |
| **Zoom In** | `button-pdf-zoom-in` | `_zoom = (_zoom + 0.1).clamp(0.5, 2.5)` | Scales viewport transform |
| **Zoom Out** | `button-pdf-zoom-out` | `_zoom = (_zoom - 0.1).clamp(0.5, 2.5)` | Scales viewport transform |
| **Fit to Width** | `button-pdf-fit-width` | `_zoom = 1.0` | Resets zoom scale |
| **Rotate** | `button-pdf-viewer-rotate` | `_rotationDegrees = (_rotationDegrees + 90) % 360` | Applies `RotatedBox` transform |
| **Print** | `button-pdf-viewer-print` | Invokes browser spooler | `window.printPdfViewer()` on iframe |
| **Download PDF** | `button-pdf-viewer-download` | Invokes `FileSaver.savePdf` | Native file save dialog |
| **Download DOCX** | `button-pdf-viewer-download-docx` | Invokes `FileSaver.saveDocx` | Native file save dialog |
| **Fullscreen** | `button-pdf-viewer-fullscreen` | Toggles `_isFullscreen` | Hides surrounding application navigation |

---

## 5. Verification & Test Coverage

Automated tests in `mobile/test/pdf_viewer_toolbar_test.dart` verify:
1. `extractPdfPageCount` accurately identifies 8 pages on an 8-page PDF fixture.
2. Exactly one toolbar widget (`pdf-viewer-toolbar`) is mounted in the widget tree.
3. Page indicator displays `Page 1 of 8` for multi-page documents and `Page 1 of 1` for single-page documents.
4. Next and Previous buttons increment and decrement `_currentPage` while clamping between 1 and `_totalPages`.
5. Zoom controls scale `_zoom` without duplicating UI controls.
6. Replacing the active PDF dynamically refreshes page count and resets viewer state.
