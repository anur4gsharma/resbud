# Resbud Architecture: Durable Image Persistence and Recovery

**Document Reference**: `docs/29-image-storage-and-recovery.md`  
**Date**: November 16, 2026  
**Status**: Implemented & Verified  
**Schema Version**: 3  

---

## 1. Architectural Strategy: Decoupling Metadata from Binary Assets

To solve the Android SQLite `CursorWindow` limit (2,097,152 bytes) and ensure durable cross-restart persistence, Resbud separates lightweight manuscript figure metadata from heavy binary payloads.

```
+--------------------------------------------------------------------------------+
|                             USER INTERACTION (UI)                              |
|           ProjectInputPage / PaperEditorPage (Visual Figure Cards)            |
+--------------------------------------------------------------------------------+
                                       |
                   _buildContext() (Lightweight Metadata Only)
                                       v
+--------------------------------------------------------------------------------+
|                        LocalProjectRepository (v3)                             |
|                                                                                |
|  1. _prepareFiguresAndContext() extracts figure binaries outside transaction   |
|  2. Saves raw bytes to ProjectImageStorage (Disk/Blob)                         |
|  3. Strips 'bytes' & 'base64' -> Produces sanitized metadata (< 25 KB)         |
+--------------------------------------------------------------------------------+
             /                                                 \
            /                                                   \
           v                                                     v
+-------------------------------------+       +----------------------------------+
|           SQLite Database           |       |       ProjectImageStorage        |
|                                     |       |                                  |
| 1. projects                         |       | * Android/Linux/Desktop:         |
|    - project_context_json (< 50 KB) |       |   FileProjectImageStorage        |
|    (0 CursorWindow overflow)        |       |   ${appDocDir}/resbud_media/     |
|                                     |       |   figures/${projId}/${figId}_${f}|
| 2. project_figures (Metadata table) |       |   (Durable, zero RAM overhead)   |
|    - id, project_id, figure_number  |       |                                  |
|    - caption, alt_text, placement   |       | * Web / Fallback:                |
|    - storage_key, file_size, dim    |       |   DatabaseProjectImageStorage    |
|                                     |       |   project_image_blobs (1 key/row)|
+-------------------------------------+       +----------------------------------+
```

---

## 2. Storage Subsystem Specifications

### 2.1 Native Platforms (Android, Linux, macOS, Windows)
- **Engine**: `FileProjectImageStorage`
- **Location**: `${getApplicationDocumentsDirectory()}/resbud_media/figures/{projectId}/{figureId}_{filename}`
- **Security & Integrity**:
  - Filename and ID sanitization via regex `[^a-zA-Z0-9._-]` prevents path traversal vulnerabilities.
  - Flushed synchronously using `writeAsBytes(bytes, flush: true)`.
  - Independent of database memory windows, allowing multi-megabyte high-resolution imagery (EM, spectroscopy, photography) without memory pressure.

### 2.2 Web & Fallback Platform
- **Engine**: `DatabaseProjectImageStorage`
- **Location**: Dedicated single-item table `project_image_blobs`:
  ```sql
  CREATE TABLE IF NOT EXISTS project_image_blobs (
    storage_key TEXT PRIMARY KEY NOT NULL,
    image_bytes BLOB NOT NULL
  );
  ```
- Reads are performed individually by `storage_key`, isolating row sizes so that querying the `projects` table remains fast and lightweight.

---

## 3. SQLite Database Schema Version 3 Migration

In `mobile/lib/data/local_project_repository.dart`, the database schema version is advanced from `2` to `3`.

### 3.1 New Table Definitions
```sql
CREATE TABLE IF NOT EXISTS project_figures (
  id TEXT NOT NULL,
  project_id TEXT NOT NULL,
  figure_number INTEGER NOT NULL DEFAULT 1,
  filename TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  width INTEGER NOT NULL DEFAULT 0,
  height INTEGER NOT NULL DEFAULT 0,
  file_size INTEGER NOT NULL DEFAULT 0,
  caption TEXT NOT NULL,
  alt_text TEXT NOT NULL DEFAULT '',
  placement TEXT NOT NULL DEFAULT 'column_width',
  section_id TEXT,
  storage_key TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (project_id, id),
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS project_image_blobs (
  storage_key TEXT PRIMARY KEY NOT NULL,
  image_bytes BLOB NOT NULL
);
```

### 3.2 Upgrade Handler
```dart
if (version == 2) {
  await db.execute('''CREATE TABLE IF NOT EXISTS project_figures (...)''');
  await db.execute('''CREATE TABLE IF NOT EXISTS project_image_blobs (...)''');
  await db.update('database_meta', {'schema_version': 3}, where: 'id = 1');
  version = 3;
}
```

---

## 4. Atomic, Deadlock-Free Persistence Flow

To prevent SQLite lock contention when persisting images alongside project updates:
1. **Phase 1: Binary Persistence (Non-transactional)**
   - `_prepareFiguresAndContext(projectId, projectContext)` iterates over incoming figures.
   - For any figure with `cachedBytes`, `imageStorage.saveImage()` persists the payload to disk or dedicated blob row.
   - Generates lightweight sanitized figure metadata with the durable `storage_key`.
2. **Phase 2: Atomic Metadata Persistence (Transactional)**
   - Begins `_database.transaction(...)`.
   - Inserts or updates the `projects` table row with the sanitized `project_context_json` (row size < 25 KB).
   - Inserts or updates all figure records into `project_figures`.
   - Commits transaction atomically.

---

## 5. Deletion & Orphan Asset Cleanup

When a project is deleted via `repository.deleteProject(projectId)`:
1. SQLite cascades delete records from `projects` and `project_figures`.
2. `imageStorage.deleteProjectImages(projectId)` removes the associated directory `${appDocDir}/resbud_media/figures/${projectId}` or deletes rows from `project_image_blobs` where `storage_key LIKE '$cleanProj/%'`.
3. Zero orphaned storage or disk leaks remain.

---

## 6. Verification and Regression Test Coverage

The implementation is verified by `mobile/test/image_persistence_test.dart` covering 8 comprehensive scenarios:
- **Test 1**: Text-only project creation and save.
- **Test 2**: Single PNG image persistence and round-trip retrieval.
- **Test 3**: Multi-image, multi-format project (PNG, JPG, WebP).
- **Test 4**: Adding figures to existing text projects.
- **Test 5**: Editing captions and layout placement without modifying image binaries.
- **Test 6**: App restart simulation (closing and reopening repository from disk).
- **Test 7**: Project deletion and complete image asset cleanup.
- **Test 8**: Figure export resolution of `(fig_1)` markers into embedded data URIs.
