# 05 — Local Data Model, Versioning, and Recovery

## 1. Scope and ownership

The Flutter client owns persistent projects and paper versions in a local SQLite database. API requests are transient; the backend does not keep project IDs, generation history, or paper content. Device storage is the source of truth for saved work. The MVP has no account, sync, or automatic cloud backup.

## 2. Records

Use SQLite with foreign keys enabled and a single database per app installation. The logical records are:

| Record | Required data | Rules |
|---|---|---|
| `projects` | stable UUID, working title, project-context JSON, source draft, created/updated UTC timestamps, current paper-version UUID (nullable) | A project owns its editable inputs; updating an input does not rewrite prior paper versions. |
| `paper_versions` | stable UUID, project UUID, monotonically increasing per-project version number, schema version, complete `PaperDraft` JSON, creation UTC timestamp, origin (`generation`, `section_acceptance`, `manual_edit`, or `import`) | Immutable after insert. A manual edit or accepted regeneration creates a new snapshot. Unique `(project_id, version_number)`. |
| `database_meta` | integer database schema version | Updated only after a successful migration transaction. |

Project input edits are saved transactionally. The current-version pointer is updated in the same transaction that inserts the corresponding paper version. Do not persist an in-flight generation proposal as the current paper.

## 3. Version semantics and save behavior

The version history model uses immutable, append-only snapshots. The version number increments monotonically per project (`max(version_number) + 1`).

### Actions that create a paper version:
1. **Full generation acceptance (`PaperVersionOrigin.generation`)**: When the user previews a full paper generated from project inputs and source material and explicitly chooses to accept it.
2. **Explicit manual save (`PaperVersionOrigin.manualEdit`)**: When the user taps the save button in the paper editor or selects "Save & leave" upon exiting with unsaved changes. Keystrokes in text fields update in-memory controller state and toggle the editor status to `Unsaved`, but do **not** write to SQLite on each keystroke to prevent database thrashing and history pollution.
3. **Section regeneration acceptance (`PaperVersionOrigin.sectionAcceptance`)**: When the user requests regeneration of a single section and accepts the proposed replacement. This atomically duplicates the active paper snapshot, replaces solely the target section content, updates section-scoped review warnings, and commits the new version.
4. **Version restoration (`PaperVersionOrigin.manualEdit`)**: When the user chooses to restore an older version from the Version History sheet. Restoring **never destroys or rewrites existing versions**. Instead, it creates a new snapshot with the next version number containing the restored version's content, records metadata `{"restored_from_version_number": N, "restored_from_version_id": "<uuid>"}`, and atomically advances `projects.current_paper_version_id`.
5. **Initial import / creation (`PaperVersionOrigin.import`)**: When a structured paper draft is initially imported into a project.

### Preservation of original source draft:
- When a project is created, its initial source draft is permanently recorded in `projects.original_draft`.
- Subsequent edits to the project inputs update `projects.source_draft`, leaving `projects.original_draft` unaltered.
- The paper editor provides a "Compare source draft" action allowing the author to inspect the original authoritative material alongside their working version.

### Unsaved changes and export safety:
- **Accurate dirty state**: Any difference between in-memory text controllers and the current version snapshot is reflected in the UI with an `Unsaved` badge.
- **Exporting with unsaved changes**: The user is explicitly prompted to either "Save & export" (committing a new version first) or "Export saved (vX)" (exporting the last committed snapshot). Stale widget memory is never exported silently.
- **Content validation**: Paper drafts are validated before sending to the export service (requiring non-empty title, valid sections within schema limits).
- **Failure leaves content intact**: If an export fails (network timeout, invalid response, server 5xx error, or filesystem write failure), saved versions and current editor contents remain strictly untouched.

### DOCX export and file saver platform considerations:
- File saving is isolated behind the `DocxFileSaver` interface.
- Filenames are sanitized to prevent directory traversal (`/`, `\`, `..`), control characters, null bytes, and reserved filesystem characters.
- Duplicate filenames are handled monotonically: `paper.docx` -> `paper (1).docx` -> `paper (2).docx`.
- **Platform limitations**: On desktop (Linux/macOS/Windows), files are saved directly to the designated directory. On mobile operating systems (Android/iOS), files written to internal app storage remain restricted to the app's sandbox. External viewing requires system file pickers, scoped storage permissions, or platform share sheets. Isolating file operations behind `DocxFileSaver` decouples these OS-specific boundaries from the editor core.

## 4. Migrations and schema evolution

SQLite structural changes use ordered, numbered migrations. On open, read `database_meta`, apply every missing migration in order inside a transaction, and advance the recorded version only when that migration commits. If a migration fails, roll back and leave the old database available; show a recoverable error and do not overwrite it with a fresh empty database.

Persisted paper JSON is validated against its recorded `schema_version`. When the paper schema changes incompatibly, ship an explicit deterministic migration for every supported prior version and test the migrated result. If no migration exists, retain the bytes and open the project in a read-only recovery/export path with a clear unsupported-version message; never silently drop fields or replace the project with defaults. A migration must preserve the original database until its successful commit.

## 5. Recovery and backup behavior

- Use SQLite transactions and a supported SQLite backup mechanism for migrations; do not copy a live database file while WAL writes may be active.
- Run `PRAGMA integrity_check` when database corruption is suspected, not on every ordinary read. If integrity fails, preserve the original database file, avoid automatic destructive repair, and show an actionable recovery error.
- The MVP provides no automatic remote backup. Users can export their current paper as DOCX; that export is not a restorable project backup. A future portable project backup format requires a separate contract and import/export tests.
- Device loss, uninstall, or platform cleanup can lose local projects. The UI and privacy information must disclose the absence of cloud recovery. OS-level device protections are relied on; the app does not claim application-level encryption at rest.

## 6. Privacy and deletion

All research content in this database remains on the device until the user explicitly sends selected text for generation or submits a paper for DOCX conversion. Deleting a project removes its rows through SQLite but does not promise forensic erasure from flash storage or OS/device backups. The app must not copy content to diagnostic logs, analytics, crash reports, or clipboard without an explicit user action.

## 7. Acceptance tests and traceability

Storage tests must cover create/update/reopen, version ordering, immutable prior snapshots, atomic section acceptance, rollback on injected write failure, migration success and failure, unsupported paper schema recovery, corrupt database preservation, project deletion, and the absence of content in logs. See `07-testing-and-evaluation.md` for end-to-end paths and `01-requirements-and-acceptance.md` for the P0 traceability matrix.

## 8. Current Flutter implementation

The Flutter client currently uses SQLite schema version 2. Its v1-to-v2 migration adds `original_draft` (initialized from the existing source draft) and per-version metadata JSON. A project's original draft is captured when the project is created; later source-draft edits do not replace it. Saved paper maps, including any warning list, are serialized as complete immutable version snapshots. Deleting a project removes its versions through SQLite foreign-key cascade after confirmation. The app displays that projects remain on the device, have no cloud backup, and may be lost when the app is uninstalled.
