# Prompt 10 — DOCX Export Service

```text
Implement DOCX export for the validated PaperDraft. Follow `docs/03-api-contract.md`, the paper schema, and the security/privacy spec.

Requirements:
- Implement a dedicated exporter using `python-docx` or the already-approved project library; keep formatting logic outside route handlers.
- Export the current submitted paper object in stable section order, with title, abstract, keywords, sections, and supplied references where applicable.
- Use real DOCX heading/paragraph styles and a clean, readable default format. Do not claim compliance with a journal's template unless implemented and tested.
- Preserve text faithfully. Do not make a new LLM call during export and do not alter research claims.
- Return standard DOCX MIME type and safe `Content-Disposition` filename. Sanitize filenames and never use paper content as a filesystem path.
- Generate in memory when practical; do not retain exports server-side. Protect against oversized payloads.
- Return stable errors if the paper fails validation or document generation fails; saved client content must remain unaffected.

Tests must validate the response headers and binary output, reopen the result as a DOCX, extract the document text to check all expected sections and references are present in order, test unsafe filenames/special characters, malformed paper input, and export failures. Include at least one output fixture/manual check in LibreOffice or another DOCX reader if available. State when visual rendering could not be tested.
```
