# Prompt 09 — TXT and DOCX Source Import

```text
Implement the source-document import capability according to the reconciled product and API contract. First determine whether extraction is defined as an API endpoint or a client-side capability. Follow the documented decision; do not invent an endpoint without updating OpenAPI and tests.

The MVP accepts `.txt` and `.docx` only. Reject all other formats. The importer must:
- Enforce file-size limits before expensive processing and validate extension/content type as a usability check, not as the sole security control.
- Parse text safely and deterministically; never execute macros, embedded links, scripts, or other document content.
- Handle empty files, malformed DOCX ZIP/XML structures, unsupported encodings, and documents whose extracted text exceeds the generation limit.
- Preserve paragraphs in readable order and normalize line endings without silently rewriting the user's research claims.
- Avoid extracting or logging more metadata than necessary.
- Return clear, safe errors that the client can display.
- Keep data in memory for parsing; do not create persistent server copies or temporary files unless necessary and reliably cleaned up.
- Add tests for normal TXT, UTF-8 edge cases, normal DOCX, tables/paragraph handling according to the documented scope, malformed DOCX, zip bombs/over-compressed payload protections where supported, oversized input, empty documents, and unsupported extensions.

If backend import is implemented, ensure the privacy notice says document contents are uploaded for extraction and are not retained by default. If extraction is client-side, document its limitations and test on supported devices. Update API/OpenAPI/client contracts together.
```
