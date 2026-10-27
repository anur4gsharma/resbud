# 01 — Requirements and Acceptance Criteria

Requirements use stable IDs so they can be mapped to code, tests, issues, and the academic demonstration.

## 1. Functional requirements

| ID | Requirement | Priority |
|---|---|---|
| FR-001 | A user can create, rename, edit, and delete a local paper project. | P0 |
| FR-002 | A project accepts a working title, research field, question, objectives, and contribution. | P0 |
| FR-003 | A user can provide a rough draft as pasted text or import `.txt`/`.docx` text. | P0 |
| FR-004 | Method, dataset/materials, results, limitations, and references may be supplied when available; explicit “not available/not conducted” values are distinguishable from unknown values. | P0 |
| FR-005 | The app validates required information and configured length limits before generation. | P0 |
| FR-006 | The user can generate a structured paper from the supplied material. | P0 |
| FR-007 | A generated paper conforms to the versioned `PaperDraft` schema. | P0 |
| FR-008 | The output displays missing-information and review warnings. | P0 |
| FR-009 | The user can edit the generated sections. | P0 |
| FR-010 | The user can request regeneration of one selected section; unrelated user edits must be preserved. | P0 |
| FR-011 | Projects and draft versions persist locally and survive a process/app restart. | P0 |
| FR-012 | The user can export the currently saved paper to a DOCX file. | P0 |
| FR-013 | Errors are mapped to understandable messages and stable machine-readable codes. | P0 |
| FR-014 | A user can cancel/leave a pending screen without corrupting saved data; cancellation semantics for a request are disclosed. | P0 |
| FR-015 | The app makes it clear that the output needs human review and source verification. | P0 |
| FR-016 | Import failure leaves the project and its previous content intact. | P0 |

## 2. Non-functional requirements

| ID | Requirement | Verification |
|---|---|---|
| NFR-001 | Provider API keys never appear in the mobile application bundle, repository, crash reports, or ordinary logs. | Secret scan and release review |
| NFR-002 | Research content is excluded from server logs by default. | Log inspection tests/review |
| NFR-003 | The backend does not persist generation inputs or outputs by default. | Code/config review and integration test |
| NFR-004 | API input and model output are validated at boundaries. | Unit and integration tests |
| NFR-005 | Generation and export failures preserve the last saved local version. | Fault-injection tests |
| NFR-006 | User-visible errors include a next action and do not expose secrets or provider internals. | UI/API tests |
| NFR-007 | Core domain logic can be tested without network access or a real model. | Fake-provider tests |
| NFR-008 | Critical paths have automated tests and repeatable manual QA steps. | CI/test report |
| NFR-009 | The API sets explicit request-size, input-length, timeout, and generation-budget limits. | Configuration and boundary tests |
| NFR-010 | The project can be built from a clean checkout using documented commands. | Clean-environment validation |

## 3. Acceptance criteria by workflow

### AC-01 — Create and save a project

- Given valid project details, when the user saves the project, it appears in the project list.
- When the app is closed and reopened, the project and last saved draft are still present.
- Deleting a project requires a clear user action and confirmation.

### AC-02 — Validate generation input

- Empty or whitespace-only source material is rejected before a provider call.
- Missing critical facts are shown to the user; a user may proceed only when the product's validation policy allows it.
- Inputs exceeding configured limits receive a clear validation error and are not sent to the provider.
- Unknown request fields are rejected rather than silently ignored.

### AC-03 — Generate a draft

- A valid request returns a schema-valid `PaperDraft` or a documented error response.
- The UI clearly indicates that generation is in progress and prevents accidental duplicate taps.
- A provider timeout or invalid response is presented as a recoverable error.
- The original source and last saved version remain unchanged if generation fails.

### AC-04 — Research integrity

- If results were not supplied, output does not claim that experiments succeeded or add numerical outcomes.
- If no references were supplied, the system does not create author names, paper titles, DOIs, or a fabricated reference list.
- A claim requiring unsupported evidence is marked for review or uses a citation-needed placeholder.
- A human evaluator can trace output claims to the input materials or identify them as needing verification.

### AC-05 — Edit and regenerate a section

- An edit is saved as a new version or a clearly defined update to the current version.
- Section regeneration receives the relevant original context and selected section, not only an isolated heading.
- The replacement is previewed before it replaces the current text.
- Unselected sections remain byte-for-byte unchanged unless the user explicitly accepts a whole-paper rewrite.

### AC-06 — Import and export documents

- Unsupported file types and oversized files are rejected before parsing.
- Malformed `.docx` input returns a friendly error; it does not crash the app.
- Export uses the latest saved content, not an older in-memory snapshot.
- The generated file opens in a standard DOCX reader and includes all applicable sections in order.
- Export failure does not modify the saved paper.

### AC-07 — Privacy/security release gate

- No provider secret is packaged with the mobile client.
- Production-like startup fails closed if required configuration is missing.
- Remote API access is authenticated and rate-limited before beta distribution.
- The privacy notice describes which content is sent to the backend/provider and for what purpose.
- Server logs contain operational metadata but not draft text, full prompts, references, or generated paper content.

## 4. Out of scope acceptance

No MVP acceptance test should require literature discovery, source authenticity verification, multi-user collaboration, cloud synchronization, LaTeX output, or plagiarism detection. Those items are explicitly deferred, not accidentally forgotten.

## 5. Traceability rule

For each requirement, record at least one of:

- automated test name;
- manual QA procedure;
- visible demo evidence;
- a documented reason the requirement is deferred.

No P0 requirement is marked complete based solely on “works on my machine.”
