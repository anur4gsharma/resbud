# 03 — HTTP API Contract

The machine-readable contract is [`../contracts/openapi.yaml`](../contracts/openapi.yaml). This document records intended behavior and operational rules.

## 1. Conventions

- Base path: `/api/v1`.
- Transport: HTTPS outside local development.
- Request/response format: JSON, except the DOCX file response.
- Time values: RFC 3339 UTC timestamps where used.
- Validation: strict typed schemas; unknown properties are rejected.
- Every response should include or allow correlation through a `request_id`.
- Every HTTP response includes `X-Request-ID`; error bodies repeat the same value as `request_id`.
- A syntactically valid incoming `X-Request-ID` is propagated; invalid/missing values are replaced with an opaque UUID.
- HTTP bodies are capped at 4 MiB before application parsing, including requests without `Content-Length`.
- Error responses use a stable `code`; the UI must not parse human-readable messages to determine behavior.

## 2. Endpoints

| Method and path | Purpose | Success |
|---|---|---|
| `GET /health/live` | Liveness: process can answer HTTP | `200` |
| `GET /health/ready` | Readiness: required configuration is present; do not expose secrets | `200` or `503` |
| `POST /api/v1/generations` | Generate one structured research paper draft | `200` |
| `POST /api/v1/generations/sections` | Regenerate one selected section using the current paper and research brief | `200` |
| `POST /api/v1/exports/docx` | Export the submitted current paper as DOCX | `200` with file bytes |

No endpoint stores a draft in the backend by default. Health endpoints must not reveal environment variables, secret values, full provider diagnostics, or detailed internal paths.

### Source-file import

There is deliberately no upload/import endpoint in API v1. The mobile client extracts text on-device, previews it, and places the accepted text in the ordinary generation request. No file bytes are sent to Resbud merely to import them. Generation subsequently transmits the selected text to the API and configured provider under the disclosure in `06-security-privacy.md`.

The client accepts `.txt` (UTF-8) and non-encrypted `.docx` only. It rejects files over 10 MiB before parsing. Text files must decode as valid UTF-8; DOCX parsing must bound ZIP entry count to 1,000 and aggregate uncompressed size to 50 MiB, and read only the main document body (not macros, embedded objects, comments, or external links). DOCX paragraphs stay in body order; table cells are joined with tabs and rows with line breaks. Line endings are normalized to LF, with text otherwise preserved. Extracted source may not exceed 50,000 characters. Empty extracted text, invalid ZIP/XML, missing `word/document.xml`, encrypted packages, and exceeded parser bounds produce a recoverable import error; project data is unchanged because the importer returns a candidate string and does not write to project storage. These limits and errors are part of the client contract, not HTTP statuses. Tests cover valid files, boundary sizes, invalid encodings, malformed and encrypted DOCX, archive expansion limits, empty extraction, and the importer's no-write behavior.

## 3. Generate request

The request contains:

- `schema_version`: currently `1`.
- `project`: title, research field, research question, objectives, claimed contribution, and available method/material/results/limitations details.
- `source_draft`: text from the user's original draft.
- `references`: references supplied by the user, each with a stable request-local ID and original text.
- `preferences`: desired word count, desired sections, and citation style preference.

The request schema is the source of truth for field types and constraints. `source_draft` must contain at least one non-whitespace character. Limits such as maximum input text size must be configurable and checked before provider invocation.

Local development can explicitly select the deterministic fake provider with `RESBUD_GENERATION_PROVIDER=fake`; its response identifies `fake` / `deterministic-demo` and carries a visible demo warning. The OpenAI adapter is selected by server configuration with `RESBUD_GENERATION_PROVIDER=openai`, `RESBUD_PROVIDER_MODEL`, and `RESBUD_PROVIDER_API_KEY`. It requests schema-constrained output, disables response-object storage, and still validates the returned `PaperDraft` locally. Returned references must exactly match the supplied references. Resbud does not persist request or paper content; provider processing and applicable provider retention terms still apply.

The OpenAI adapter caps output at `RESBUD_PROVIDER_MAX_OUTPUT_TOKENS` (default 12,000) and uses separately configured connection and read timeouts (defaults 5 and 90 seconds). Its SDK retries are disabled to avoid repeating a potentially billable call. The token cap does not guarantee a specific cost; cost depends on the configured model and input size. Model availability is account-specific and must be checked with the optional local smoke test in `docs/07-openai-provider.md`.

## 4. Generate response

A successful response contains:

- `schema_version`;
- `generation_id` (a request/result identifier, not a persistent cloud record);
- `paper` (`PaperDraft`);
- `review_warnings`;
- `meta` with provider/model identifiers if safe to expose, generation duration, and token/cost data if the provider returns it.

Provider internals and raw prompts are not part of the public response. Do not expose secret-bearing exception strings.

## 5. Error contract

Use a JSON object with fields similar to:

```json
{
  "type": "about:blank",
  "title": "Request validation failed",
  "status": 422,
  "detail": "Correct the highlighted fields and try again.",
  "code": "VALIDATION_ERROR",
  "request_id": "opaque-correlation-id"
}
```

`detail` is safe for the user. It may omit internal information. `code` is stable and intended for client logic.

Framework validation errors and expected application failures use the same shape. Unexpected exceptions return `500 INTERNAL_ERROR`; logs include only request ID, method, and matched route template, never the exception message, body, or traceback.

| HTTP status | Error code | Meaning | Client behavior |
|---|---|---|---|
| `400` | `INVALID_REQUEST` | Request cannot be interpreted | Explain input issue |
| `404` | `INVALID_REQUEST` | Route/resource does not exist | Explain that the requested item was not found |
| `401` | `UNAUTHENTICATED` | Caller identity absent/invalid in deployed mode | Request sign-in |
| `403` | `FORBIDDEN` | Caller lacks permission | Explain access restriction |
| `413` | `INPUT_TOO_LARGE` | Request or file exceeds size limit | Ask user to shorten/split input |
| `415` | `UNSUPPORTED_MEDIA_TYPE` | Unsupported upload/export media type | Explain accepted types |
| `405` | `INVALID_REQUEST` | HTTP method is unsupported | Explain the request cannot be completed |
| `422` | `VALIDATION_ERROR` | Fields or values violate schema | Show a safe validation message; highlight fields only when local validation identifies them |
| `429` | `RATE_LIMITED` | Caller/instance quota reached | Show wait/retry guidance; no rapid automatic retry |
| `502` | `PROVIDER_INVALID_RESPONSE` | Provider result is unusable | Preserve source; allow deliberate retry |
| `503` | `PROVIDER_UNAVAILABLE` | Provider is unavailable/configuration is incomplete | Show temporary failure |
| `504` | `PROVIDER_TIMEOUT` | Generation exceeded bounded timeout | Preserve source; warn retry may incur another call |
| `500` | `INTERNAL_ERROR` | Unexpected server error | Show safe generic message and request ID |

### Section regeneration details

`POST /api/v1/generations/sections` receives the original `generation_request`, the full `current_paper`, the target `section_id`, and a bounded `user_instruction` (an empty string means no additional instruction). The target ID must exist exactly once in `current_paper.sections`, and a section marked `not_applicable` cannot be regenerated; otherwise return `422 VALIDATION_ERROR` with a safe detail. A `200` response contains only the proposed `PaperSection` and warnings. Its `section.id` must equal the requested ID and its content must be nonblank. It does not return a replacement `PaperDraft` and does not persist or mutate anything. The client previews the proposal and retains every existing section and reference until the user explicitly accepts; acceptance replaces only the target section in a new local draft version. Cancel or failure leaves the current version unchanged.

Framework validation errors must be normalized to this shape rather than leaking a different response format for every failure.

## 6. Timeouts, retries, and duplicate requests

- Set explicit connect/read/provider timeouts based on measured provider behavior.
- The mobile UI disables the submit action while one request is active.
- Do not blindly retry generation on a client or server. A request may have reached the provider even if the response was lost, and another call may incur additional cost.
- The initial synchronous MVP does not promise exactly-once generation. Document this limitation in the UI/help text for ambiguous timeout retries.
- If retries become a product need, add an idempotency design with a shared store, retention policy, and privacy review before implementation.

### Client cancellation

There is no server cancellation endpoint in API v1. Leaving a pending screen or cancelling the client wait stops the client from applying a late result and leaves saved content unchanged; it does not promise that the HTTP request or provider call was stopped. Tell the user that an already-submitted call may complete and incur cost. Do not automatically retry after cancellation or a lost response.

## 7. DOCX export contract

The client sends the current validated `PaperDraft` to `/api/v1/exports/docx`. The server generates a document in memory and returns the DOCX MIME type and a safe filename. It does not save the file to persistent server storage.

Because paper content passes through the backend for export, the privacy notice must disclose this. Keep a strict input-size limit, never use model-generated text as a path, and do not log document content.

## 8. API versioning and compatibility

- Changes that remove or redefine a field require an API/schema versioning decision.
- Additive optional fields may be backwards-compatible, but must still be tested against the mobile client.
- `schema_version` for paper content is distinct from the HTTP path version.
- The generated OpenAPI document should be checked in CI against the route implementation where practical.
