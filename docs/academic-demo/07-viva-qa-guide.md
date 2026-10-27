# 07 — Viva Voce Preparation and Examination Q&A Guide

This guide provides comprehensive, technically precise answers to the 15 most probable examination questions during an academic viva voce or senior engineering defense.

---

### Q1: Why separate Flutter and FastAPI instead of building a monolithic mobile app with direct LLM calls?
**Answer**:  
Directly calling LLM providers from a mobile app presents critical security and architectural vulnerabilities. Client-side binaries can be decompiled or memory-inspected, which would expose provider API keys and allow arbitrary unauthorized token usage.  
By introducing a FastAPI backend:
1. **Secret Isolation**: Provider credentials and JWT validation keys remain strictly server-side.
2. **Boundary Enforcement**: The backend enforces rate limits, request payload size caps (4MB), and strict JSON Schema validation before forwarding requests to the provider.
3. **Decoupled Evolution**: The mobile UI and prompt engineering / provider adapters can evolve and deploy independently without requiring app store updates for minor backend adjustments.

---

### Q2: Why choose a local-first SQLite architecture instead of a managed cloud database like Firebase or Supabase?
**Answer**:  
Academic researchers frequently handle sensitive, unpublished, or proprietary hypotheses, embargoed clinical data, or unpatented inventions. Forcing users to sync drafts to a cloud database raises severe intellectual property and compliance barriers.  
Local-first persistence ensures:
1. **Absolute Data Sovereignty**: Drafts and research notes reside on the user's physical device by default.
2. **Offline Usability**: Users can organize projects, edit sections, view history, and draft material without an active internet connection.
3. **Simplicity and Reliability**: Transactional SQLite migrations with linear versioning eliminate cloud synchronization conflict bugs and external infrastructure costs during the MVP phase.

---

### Q3: What does JSON Schema validation prove, and what does it NOT prove?
**Answer**:  
Schema validation (via JSON Schema `Draft-07` and Pydantic v2) proves:
- **Structural Integrity**: The document contains all required fields (`title`, `abstract`, `sections`, `references`, `review_warnings`).
- **Type Safety**: Fields conform to bounded strings, valid enums, non-empty lists, and integer ranges.
- **Contract Adherence**: Client and server agree on the wire format without silent field loss or runtime deserialization crashes.

Schema validation **DOES NOT** prove:
- **Scientific Truth**: A schema-valid paragraph can still state that water boils at 50°C.
- **Logical Soundness**: It does not verify whether mathematical deductions or statistical inferences are valid.
- **Citation Authenticity**: It does not verify whether a cited paper exists in the real world.

---

### Q4: How does Resbud prevent the model from hallucinating experimental results?
**Answer**:  
Resbud attacks hallucination through a multi-tiered constraint pipeline:
1. **Explicit Negative Encoding**: Research facts distinguish between `unknown` and `not_conducted` / `not_available`. If results are marked not conducted, the system prompt explicitly forbids inventing measurements.
2. **Structured Review Warnings**: The pre-generation integrity scanner scans the input and flags missing empirical findings (`MISSING_RESULTS`).
3. **Section State Marking**: In the output, the section is flagged with `state: "needs_input"`, rendering a visual amber warning badge in the editor.
4. **Post-Generation Scanning**: The backend verifies that numerical claims in the output can be traced back to numbers present in the input material.

---

### Q5: How do you guarantee that regenerating a single section does not alter or corrupt unrelated sections?
**Answer**:  
Rather than requesting a whole-paper rewrite, Resbud implements targeted section regeneration:
1. **Dedicated Endpoint**: `POST /api/v1/generations/sections` accepts the current paper, target section ID, and user instructions.
2. **Isolated Proposal**: The provider returns *only* a proposed replacement for that specific section (`SectionRegenerationResponse`), leaving all other sections unrendered.
3. **Explicit User Review**: The client displays a side-by-side diff preview. If the user clicks **Reject**, the draft remains unmodified.
4. **Targeted In-Place Replacement**: Upon clicking **Accept**, the client updates only the matching section item in the `sections` array and saves an immutable snapshot (`Version N+1`). All other sections remain byte-for-byte identical to their prior state.

---

### Q6: What happens if the network drops or the provider times out during generation? Is data lost?
**Answer**:  
Data loss is prevented by state isolation and fail-safe error handling:
1. **Input Preservation**: Before generation is initiated, input fields remain bound to local controller state and are saved to SQLite.
2. **Stateless Request**: If a network timeout (HTTP 504) or connection reset occurs, the backend aborts cleanly.
3. **Client Error Presentation**: The client catches the `ApiException`, displays a friendly error snackbar with the request ID, and maintains the current page state.
4. **No Partial Overwrite**: The active draft in SQLite is only updated upon receiving a validated 200 OK response; failed calls leave the database untouched.

---

### Q7: Why do all standard automated tests run against a `FakeProvider` instead of live LLMs?
**Answer**:  
1. **Determinism**: Live LLMs are non-deterministic and can produce varying outputs, leading to flaky test suites.
2. **Cost and Rate Limits**: Running hundreds of CI tests against commercial APIs incurs unnecessary token costs and risks hitting vendor rate limits.
3. **Fault Injection**: `FakeProvider` can deterministically simulate edge cases that are difficult to reproduce with a live model, such as network timeouts, malformed JSON structures, missing section IDs, and rate limit throttling (429).
4. **Zero-Dependency CI**: Allows tests to run in hermetic environments without API keys or internet access. Live provider tests are isolated in an opt-in integration suite (`test_openai_provider.py`).

---

### Q8: How is user research privacy protected in server logs?
**Answer**:  
Resbud enforces a zero-content logging invariant:
1. **Custom Middleware**: `RequestBoundaryMiddleware` and error handlers capture operational metadata (`request_id`, method, path, HTTP status, execution duration in milliseconds) but explicitly omit request and response bodies.
2. **Secret Redaction**: Logging formatters mask sensitive headers (`Authorization: Bearer ***`) and provider secrets.
3. **Verification**: Automated tests (`test_zero_content_and_secret_redaction_in_logs`) capture log output during generation calls and assert that neither user draft sentences, research questions, nor generated text appear in log buffers.

---

### Q9: How are backend resources protected against denial-of-service and abuse?
**Answer**:  
1. **Streaming Body Size Limit**: `RequestBoundaryMiddleware` measures incoming stream bytes and immediately halts streaming with HTTP 413 if the payload exceeds 4 MiB, before memory allocation occurs.
2. **Sliding-Window Rate Limiting**: `InMemoryRateLimiter` enforces a per-IP / per-token quota (default 60 requests/minute), returning HTTP 429 with standard `Retry-After` headers.
3. **Output Token Caps**: `provider_max_output_tokens` limits provider generation to 12,000 tokens, bounding latency and cost.
4. **CORS Restrictions**: Exact origin matching rejects wildcard `*` domains.

---

### Q10: How does Resbud ensure database migrations are safe and recoverable?
**Answer**:  
1. **Linear Versioning**: The `schema_migrations` table records applied versions (`version: 1`, `version: 2`).
2. **Transactional Execution**: In `LocalProjectRepository`, migration steps execute inside a single SQLite transaction.
3. **Rollback Safety**: If any migration statement fails (e.g. syntax error or disk full), SQLite rolls back all uncommitted alterations, leaving the existing database in a readable and uncorrupted state (verified in `local_project_repository_test.dart`).

---

### Q11: Why is DOCX generation implemented on the backend in-memory rather than on the client?
**Answer**:  
1. **Ecosystem Maturity**: Python's `python-docx` provides robust, compliant OpenXML synthesis with full control over paragraph styling, XML namespaces, heading hierarchies, and font tables. Dart OpenXML generation libraries are less mature and prone to reader incompatibility.
2. **In-Memory Security**: The backend generates the document as an in-memory `io.BytesIO` stream and returns it as a binary response (`application/vnd.openxmlformats-officedocument.wordprocessingml.document`). No temporary DOCX files are written to the server's disk, preventing file leaks.

---

### Q12: How are duplicate submissions prevented in the UI?
**Answer**:  
When generation or section regeneration is triggered:
1. `_generationPhase` is set to `generating`.
2. The UI disables the submit button and renders an inline progress indicator.
3. Taps during this phase are ignored by the button handler.
4. If an unexpected error occurs, state resets to `ready` or `recoverableFailure`, re-enabling submission.

---

### Q13: What are the trade-offs of storing version history as immutable JSON snapshots?
**Answer**:  
- **Advantages**:
  1. Instant rollback: restoring an earlier draft is a simple `INSERT` of the old JSON payload as a new version.
  2. Zero drift: snapshots are immune to schema changes made to earlier versions.
  3. No diff computation overhead: viewing a past version does not require parsing and applying a chain of delta patches.
- **Trade-offs**:
  1. Storage overhead: each version stores the complete paper structure (~10–50 KB). For an MVP with 5–20 versions per project, total database size remains under 2 MB, which is negligible on modern mobile devices.

---

### Q14: How does Resbud handle untrusted text imported from `.docx` files?
**Answer**:  
1. **Zip Safety**: `SourceDocumentImporter` validates the ZIP archive header and rejects zip-bomb compression ratios or directory traversal filenames.
2. **XML Isolation**: It extracts only the `word/document.xml` entry, parsing paragraph (`<w:p>`) and text (`<w:t>`) nodes while discarding macros, external hyperlinks, and executable scripts.
3. **Graceful Failures**: If the file is encrypted, password-protected, or malformed, it throws a typed `SourceImportException`, alerting the user without crashing the app or clearing existing project notes.

---

### Q15: What architectural changes would be required to support multi-user real-time collaboration in the future?
**Answer**:  
Transitioning from local-first to multi-user collaborative editing would require:
1. **Conflict-Free Replicated Data Types (CRDTs)** or **Operational Transformation (OT)** (e.g., Yjs or Automerge) to handle concurrent edits at the character level.
2. **WebSocket Gateway**: Adding bidirectional WebSocket or gRPC streaming to FastAPI for real-time document change propagation.
3. **Distributed Presence and Auth**: Storing active document sessions in Redis and synchronizing user identity through OAuth/OIDC tokens.
4. **End-to-End Encryption (E2EE)**: To preserve Resbud's privacy principles, drafts should be encrypted on-device before syncing through the cloud relay.
