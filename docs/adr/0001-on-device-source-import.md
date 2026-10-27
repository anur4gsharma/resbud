# ADR 0001: Extract imported source documents on the device

- **Status:** Accepted for MVP specification
- **Date:** 2026-10-27

## Context

The product requires `.txt` and `.docx` source import, while the API contract defines generation/export only. The Flutter architecture already assigns import and import errors to the client. Adding an upload service would transmit and temporarily handle unpublished research content solely to extract text.

## Decision

The mobile client parses accepted files locally, previews extracted text, and sends text only through the explicit generation request. API v1 has no source-upload endpoint. Accept UTF-8 `.txt` and non-encrypted `.docx`, reject raw files over 10 MiB, and bound DOCX parsing to 1,000 ZIP entries and 50 MiB aggregate uncompressed data. Extract only main document body text. See `03-api-contract.md` for malformed-file behavior and required tests.

## Consequences

- Import alone does not transmit document bytes or add backend retention.
- Each mobile platform must implement and test safe bounded extraction.
- DOCX formatting, comments, embedded files, macros, and external relationships are not imported.
- Generation still sends selected extracted text to the backend and configured provider after disclosure.
- A later server-side import feature would require a new privacy, security, and API decision.

## Alternatives considered

- **Backend extraction:** simpler to centralize parser behavior but adds an upload endpoint, server parser attack surface, and transmission/retention concerns. Deferred.
- **Text-only paste:** smaller implementation but does not meet the P0 import requirement. Rejected.
