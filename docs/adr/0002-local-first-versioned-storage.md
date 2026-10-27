# ADR 0002: Keep project history in local SQLite snapshots

- **Status:** Accepted for MVP specification
- **Date:** 2026-10-27

## Context

Projects must survive app restarts, section regeneration must preserve edits, and the backend must not persist research content by default. The app has no account or sync scope in the MVP.

## Decision

Store project inputs and immutable, full `PaperDraft` snapshots in a local SQLite database. Use transactional per-project version increments and a current-version pointer. Accepted edits/regeneration create a new snapshot; failed or rejected actions do not change saved state. Apply numbered transactional database migrations and explicit paper-schema migrations. Preserve databases on migration/corruption failures and disclose there is no cloud recovery. Detailed behavior is in `05-data-model-and-storage.md`.

## Consequences

- Saved work is available offline and is not retained by the Resbud backend.
- Device loss/uninstall can lose work; there is no cross-device recovery.
- Migration, transaction, corruption, and version-history behavior are required client tests.
- Local SQLite storage is not represented as application-level encrypted storage.

## Alternatives considered

- **Backend project storage/cloud sync:** deferred because it materially expands privacy, authentication, hosting, and account scope.
- **Overwrite one current draft:** rejected because it cannot reliably restore prior content after a bad edit or regeneration.
