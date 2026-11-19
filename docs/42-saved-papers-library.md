# Resbud — Saved Papers Library and Project Management Architecture

## 1. Executive Summary & Persistence Audit

### 1.1 Problem Statement
In previous iterations of Resbud, local-first storage was primarily project-centric. While research inputs, figures, and generated papers were saved in SQLite (`resbud_projects.sqlite`), users lacked:
1. **A dedicated Library View:** There was no top-level "My Papers" destination. Papers were nested inside project cards or research input pages.
2. **Title Desynchronization:** AI-generated manuscript titles and user-edited paper titles resided in `paper_versions.paper_json['title']`, while project list cards only displayed `projects.title`.
3. **Paper Metadata Visibility:** Important manuscript attributes—such as paper format (IEEE, Nature, ACM), citation style (IEEE, APA), author count, and draft completion status—were not visible on the dashboard.
4. **Independent Paper Operations:** Users could not rename, duplicate, or delete a paper independently from its project.
5. **False Empty States During Asynchronous Loads:** The Generated Paper card on `ProjectInputPage` evaluated `snapshot.data ?? []` during `ConnectionState.waiting`, briefly flashing "No paper generated yet" even when a valid paper was persisted. Additionally, it defaulted to `versions.first` (v1) instead of the latest or active version.

### 1.2 SQLite Schema Audit
The existing local-first schema (`currentDatabaseSchemaVersion = 3`) contains the necessary relational foundations:

```sql
-- Projects Table
CREATE TABLE projects (
  id TEXT PRIMARY KEY NOT NULL,
  title TEXT NOT NULL,
  project_context_json TEXT NOT NULL,
  source_draft TEXT NOT NULL,
  original_draft TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  current_paper_version_id TEXT,
  FOREIGN KEY (current_paper_version_id) REFERENCES paper_versions(id)
);

-- Paper Versions Table
CREATE TABLE paper_versions (
  id TEXT PRIMARY KEY NOT NULL,
  project_id TEXT NOT NULL,
  version_number INTEGER NOT NULL CHECK (version_number > 0),
  schema_version INTEGER NOT NULL CHECK (schema_version > 0),
  paper_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  origin TEXT NOT NULL CHECK (origin IN ('generation', 'section_acceptance', 'manual_edit', 'import')),
  metadata_json TEXT,
  UNIQUE (project_id, version_number),
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
);

-- Figures Table
CREATE TABLE project_figures (
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
```

### 1.3 Key Finding: No Schema Breaking Changes Required
The schema already encapsulates full paper data (`title`, `sections`, `abstract`, `references`, `figures`, `document_template`, `authors`) in `paper_versions.paper_json`. Rather than introducing redundant tables, we extend `LocalProjectRepository` with relational join queries, manuscript data mapping, and paper lifecycle operations (rename, duplicate, delete, list).

---

## 2. Information Architecture: Distinguishing Projects from Papers

### 2.1 Entity Relationship Model
```
ResearchProject (Container)
  ├── ResearchInputs (sourceDraft, researchField, topics, venue, context)
  ├── AttachedFigures (multimodal image files, captions, placements)
  └── Manuscripts (Saved Paper Versions)
       ├── Manuscript v1 (Initial AI generation)
       ├── Manuscript v2 (Section acceptance / user refinement)
       └── Current Active Manuscript (project.current_paper_version_id)
```

1. **ResearchProject:** A research initiative containing raw source materials, guidelines, and figures. A project can exist without a generated paper.
2. **SavedManuscript:** A generated, synthesized, or edited academic paper. A single project can have multiple saved versions over time.
3. **Unfinished Draft:** Either a project that has research inputs/material but has not yet completed paper synthesis, or a paper marked with `completion_status: 'partial'`.

---

## 3. Dedicated "My Papers" Library

### 3.1 Navigation
A primary bottom navigation destination labeled **My Papers** (`Icons.menu_book_outlined` / `Icons.menu_book`) provides instant access to all saved generated manuscripts across all projects.

### 3.2 Manuscript Card Features
Each entry displays:
* **Paper Title:** From `paper_json['title']` (falling back to project title if unedited).
* **Last Modified Date:** Human-readable formatted date.
* **Format Badge:** E.g., `IEEE Conference`, `Nature`, `ACM Standard`, `Academic Standard`.
* **Citation Style Badge:** E.g., `IEEE`, `APA 7th`, `Harvard`.
* **Author Count Badge:** E.g., `1 author`, `3 authors`.
* **Status Badge:** `Saved`, `Draft Ready`, or `Unfinished draft`.
* **Associated Project:** Clearly identifies the parent research project.
* **Document Preview / Abstract Snippet:** Expandable snippet of the abstract text.
* **Quick Primary Actions:**
  * `Read DOCX`: Opens the native paginated two-column DOCX canvas.
  * `View PDF`: Opens the high-fidelity PDF reading view.
  * `Edit Manuscript`: Opens the multi-pane manuscript editor.
* **Overflow Action Menu:**
  * `Version History`: In-app bottom sheet to view all versions, snapshot metadata, and restore previous versions.
  * `Export DOCX`: Direct formatted export.
  * `Export PDF`: Direct PDF export.
  * `Rename Paper`: Prompts user and updates paper title across SQLite records.
  * `Duplicate Manuscript`: Deep copies project context, figures, and paper as a new independent project.
  * `Delete Paper`: Deletes saved paper versions with confirmation dialog while retaining research inputs.

---

## 4. Enhanced Home Dashboard

The Home Dashboard integrates:
1. **Search & Filter Bar:** Instant real-time search across paper titles, project titles, and abstracts.
2. **Filter Chips:** Filter by paper format (`All`, `IEEE`, `ACM`, `Nature`, `Standard`).
3. **Sorting:** Sort by `Last Modified (Newest)`, `Last Modified (Oldest)`, `Title (A-Z)`, `Title (Z-A)`.
4. **Recent Papers:** Highlights recently edited manuscripts with direct reading/editing actions.
5. **Unfinished Drafts:** Surfaced separately with a "Continue Draft" CTA.
6. **Research Projects Repository:** Complete list of all research projects with creation mode and actions.
7. **Zero Fabricated Data:** True local-first data only; clean empty states for first-time users.

---

## 5. Generated Paper Screen Persistence Fixes

1. **Eliminate False Empty States:**
   * While `FutureBuilder` is loading (`ConnectionState.waiting`), display an accessible loading skeleton instead of the empty state when `current_paper_version_id != null`.
   * Only show "No paper generated yet" when `snapshot.connectionState == ConnectionState.done` and `versions.isEmpty`.
2. **Accurate Version Selection:**
   * Select the active current version (`project.currentPaperVersionId`) or the highest version number (`versions.last`), resolving the bug where `versions.first` (v1) was erroneously selected as "Latest".
3. **Comprehensive Metadata & Actions:**
   * Displays title, saved status badge, creation date, sections count, and direct DOCX / PDF / Editor buttons.

---

## 6. Test & Verification Plan

An end-to-end regression test suite in `mobile/test/saved_papers_library_test.dart` verifies:
* Empty library state.
* One saved manuscript display and actions.
* Multiple manuscripts across multiple projects.
* Unfinished drafts detection and continuation.
* Project reopening and manuscript persistence across app restarts.
* Manuscript restoration from prior versions.
* Rename and duplicate operations.
* Deletion with confirmation.
* Live title search and format filtering.
* Actual SQLite disk persistence via `sqflite_common_ffi`.
