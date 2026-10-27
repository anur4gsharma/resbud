# Prompt 12 — Flutter Foundation and Local Persistence

```text
Implement the Flutter app foundation and local-first persistence for Resbud. Inspect current `mobile/` conventions and the architecture/data-model specification before choosing dependencies.

Requirements:
- Establish app entry point, theme/design tokens, navigation for the smallest required workflow, and a clear feature/data/shared boundary where helpful.
- Implement persistence for projects, the source brief, the original draft, current paper draft, warning list, metadata, timestamps, and versions as specified by the reconciled data model.
- Use SQLite or the storage library approved by the spec. Do not keep critical content only in in-memory widget state.
- Define schema versioning/migrations and test fresh database creation plus upgrade path for at least the current schema.
- Use repository interfaces only where they provide a useful seam for testing; do not introduce a complicated generic data layer.
- Make writes atomic where appropriate. Failed writes must be surfaced; do not falsely report a save succeeded.
- Document local data retention, deletion, backup limitations, and what happens on app uninstall.
- Never store provider API keys or server secrets in the app.

Add tests for repository CRUD, empty project list, reopening after app restart where testable, migration behavior, version ordering, transaction/failure behavior, and serialization round trips. Add Flutter analysis and focused tests. UI polish is not the goal yet; data integrity is.
```
