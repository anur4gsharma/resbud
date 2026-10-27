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

## 3. Version semantics

- Every explicitly saved paper change creates a full snapshot with the next project-local version number. Generation results and section replacements are proposals until the user accepts/saves them.
- Section acceptance starts from the current snapshot, replaces only the chosen section, preserves all other section fields and all references/warnings unless the user separately edits them, then inserts a new snapshot and advances the pointer atomically.
- Cancelled, failed, or rejected generation/regeneration/export operations do not alter saved inputs, snapshots, version numbers, or current-version pointers.
- Deleting a project requires an explicit confirmation and deletes its versions in one transaction. There is no trash or server recovery in the MVP; the confirmation must say that local project history will be removed.

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
