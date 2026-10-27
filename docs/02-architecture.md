# 02 — Architecture and Component Boundaries

## 1. Architecture goals

The architecture must make the core workflow testable, keep secrets off-device, preserve local user data, and isolate provider-specific behavior. It should be simple enough for a solo developer to reason about and extend.

## 2. Logical architecture

```text
┌────────────────────────────────────────────┐
│ Flutter mobile client                      │
│ UI → feature state → repositories           │
│ Local SQLite + import/export UI             │
└─────────────────────┬──────────────────────┘
                      │ HTTPS / JSON
                      ▼
┌────────────────────────────────────────────┐
│ FastAPI application                        │
│ Request validation → use-case service      │
│        │                    │               │
│        ▼                    ▼               │
│ Research brief/domain   Provider adapter    │
│        │                    │               │
│        └──────────┬─────────┘               │
│                   ▼                         │
│ Output validation → DOCX export service     │
└───────────────────┬────────────────────────┘
                    │ provider-specific API
                    ▼
             Configured LLM provider
```

The backend is stateless with respect to research content in the MVP. Persistent projects and draft versions live locally on the device. Operational metrics may record request IDs, status, duration, payload size, provider/model identifier, token usage if available, and stable error codes—but not the content itself.

## 3. Component responsibilities

### Flutter client

- Collect and validate inputs for usability; backend validation remains authoritative.
- Import source files and display import errors.
- Persist projects and versions locally.
- Manage loading, success, empty, and error states.
- Render structured sections and warnings.
- Submit generation and export requests only after an explicit user action.
- Never contain the LLM provider's secret credential.

### API layer (`api/`)

- Define versioned routes and HTTP behavior.
- Parse/validate request and response models.
- Map known application errors to stable status codes.
- Apply request-size limits, security middleware, authentication, and rate limits according to deployment environment.
- Keep route handlers thin; do not put prompt construction or DOCX formatting logic inside endpoints.

### Domain layer (`domain/`)

- Define `ResearchBrief`, `PaperDraft`, `PaperSection`, `ReferenceInput`, `ReviewWarning`, and domain validation rules.
- Avoid dependencies on FastAPI, a specific LLM SDK, and the mobile framework.
- Express invariants that are true regardless of provider or UI.

### Use-case/services layer (`services/`)

- Orchestrate the generation pipeline: normalize input → build prompt → invoke provider → parse → validate → apply integrity checks → return result.
- Implement section regeneration while preserving non-target sections.
- Keep workflow decisions testable with a fake provider.

### Provider adapter (`providers/`)

- Expose a small interface such as `generate_paper(brief) -> ProviderResult`.
- Translate provider-specific requests, structured-output settings, timeouts, usage metadata, and errors.
- Never leak provider SDK types into the domain layer.
- Do not automatically retry generation after an ambiguous timeout; a retry can incur a second charge.

### Export service (`export/`)

- Convert validated `PaperDraft` data into a controlled DOCX template.
- Use safe filenames and avoid interpreting model text as code or file paths.
- Return a file response; do not retain the file server-side.
- Apply predictable heading, paragraph, keyword, and reference formatting.

### Observability (`observability/`)

- Generate a request ID and emit structured operational events.
- Capture duration, route, status, configured model, error code, and usage/cost metadata when available.
- Redact authorization headers, credentials, prompt text, draft text, references, and generated content.

## 4. Request lifecycle

1. The client checks locally required fields and displays a final pre-generation summary.
2. The client sends the request over HTTPS.
3. The API authenticates the caller in deployed environments, enforces request limits, and validates the request schema.
4. The generation use case converts inputs to a normalized research brief.
5. The provider adapter invokes the selected model with a bounded timeout and output budget.
6. The service parses the model response into the domain schema. Invalid responses are rejected or handled by one bounded repair attempt if explicitly configured.
7. Integrity checks verify structural properties and identify obvious unsupported-output signals. They do not claim to prove scientific truth.
8. The API returns a structured draft and warnings.
9. The client displays a preview. The user explicitly saves or accepts edits; failed generation does not overwrite saved state.
10. Export sends the currently selected paper object to the DOCX endpoint, which returns a file without persisting it.

## 5. Important architectural choices

- **Synchronous HTTP for the first version.** One request returns one result. Set explicit server/provider/client timeouts, show progress, and do not auto-retry ambiguous failures. If measured latency and reliability require it, move to a persistent job model in a later ADR.
- **Local-first project persistence.** This reduces backend data retention and removes cloud-sync work from the MVP, at the cost of no automatic cross-device recovery.
- **One provider adapter.** The interface protects the core system from vendor coupling without building a multi-provider routing platform.
- **Explicit paper schema.** The mobile client renders typed sections rather than scraping headings from unstructured prose.
- **No hidden “AI verification” pass.** Additional model calls can cost money and still fail to verify truth. Use schema validation, deterministic rules, a documented evaluation set, and human review.

## 6. Target code organization

```text
backend/src/resbud_api/
├── main.py                  # app assembly and lifespan
├── api/
│   ├── routes/
│   ├── schemas/              # transport models only
│   ├── dependencies.py
│   └── error_handlers.py
├── core/
│   ├── config.py
│   ├── logging.py
│   └── security.py
├── domain/
│   ├── models.py
│   └── rules.py
├── services/
│   ├── generation.py
│   ├── prompt_builder.py
│   ├── integrity_checks.py
│   └── section_regeneration.py
├── providers/
│   ├── base.py
│   └── configured_provider.py
├── export/
│   └── docx_exporter.py
└── observability/
    └── request_context.py
```

Do not create all modules as empty placeholders. Start with the smallest set and split files when responsibilities or test seams justify it.

## 7. Failure boundaries

- Invalid request → reject before calling the model.
- Provider timeout or rate limit → return a stable error; preserve local draft.
- Malformed model output → fail closed; do not return unvalidated free text as a successful paper object.
- Export parse/format error → return a stable error; preserve local draft.
- App process termination → rely on local saved state; unsaved edits may be lost, so autosave or explicit save behavior must be defined and tested.
- Client disconnect → do not assume the provider stopped processing; communicate that retrying may make another request.

## 8. Scaling path (not part of MVP)

Only if real measurements justify it: add persistent generation jobs and a worker queue; introduce durable server-side user records if cloud history becomes a requirement; add a shared rate-limit store for multiple API instances; move exports to a background worker for large documents; and add tracing/metrics infrastructure when operational needs justify it. Avoid Kubernetes, a distributed queue, and microservices for the first release without measured need.
