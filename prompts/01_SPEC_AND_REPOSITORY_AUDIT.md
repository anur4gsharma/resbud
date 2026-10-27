# Prompt 01 — Repository and Specification Audit

**Run first, before implementation.**

```text
Audit the existing Resbud repository and specifications. This task is an AUDIT AND RECONCILIATION task; do not implement product features yet.

Read the root README, all existing docs, JSON Schemas, and OpenAPI YAML. Inspect the actual directory tree and git status. Compare product requirements to contracts and contracts to each other.

Specifically verify:
- Every path linked from README exists.
- Every P0 requirement has a clear implementation location and acceptance test.
- Request/response schemas in OpenAPI align with the standalone JSON Schemas and docs.
- Section regeneration has complete request and response contracts, including the rule that non-target sections remain unchanged until a user accepts the replacement.
- `.txt` and `.docx` source import is specified end-to-end, including where extraction happens, file size/type limits, malformed-file behavior, privacy implications, and tests. The current API contract may not define an import endpoint; detect and resolve this gap instead of assuming.
- Local persistence/versioning has a real specification and migration/recovery rules.
- Authentication, rate limiting, local development mode, provider secrets, CORS, request limits, health/readiness checks, and content-free logs have release requirements.
- Generated paper warnings, section IDs, reference preservation, missing-information states, and error codes are consistent.
- No requirements conflict on whether the backend stores research content.

Produce `docs/11-spec-audit-and-decisions.md` with a table: issue, evidence/path, risk, proposed resolution, affected files, and test needed. Add ADRs for meaningful architecture choices in `docs/adr/`.

Resolve obvious documentation defects and unambiguous contract omissions in docs and machine-readable contracts together. Prefer minimal and backward-compatible changes. Do not quietly expand the product. For decisions that materially affect privacy, hosting cost, or user-facing scope, document the options and recommended choice without pretending it was approved.

At minimum, ensure README links are valid. If README references a missing local-storage document or ADR directory, create the missing document(s) or correct the references. Confirm that file import and section regeneration are implementable from a defined contract. Validate JSON and YAML syntax with available tooling.

Deliverables: audit report, ADRs for decisions actually made, synchronized docs/contracts, and a concise list of unresolved decisions. No application feature code in this task. Report the exact validation commands and results.
```
