# Prompt 05 — First End-to-End Backend Slice with Fake Provider

```text
Implement the first complete generation slice using a deterministic fake LLM provider. This proves the architecture before adding paid external API behavior.

Requirements:
- Define a small provider interface that returns a provider-neutral result and usage metadata where available. Do not expose provider SDK types to domain/service code.
- Implement a fake provider that produces deterministic valid paper drafts from configured fixtures or simple explicit test rules. It must support controlled cases: success, timeout, unavailable provider, malformed structured response, and provider rate limit.
- Implement the generation use case: validate request → normalize research brief → build a generation input → invoke provider → parse/validate output → run deterministic integrity checks → return structured paper and warnings.
- Keep route handler thin and map failures to the stable documented API errors.
- Add `POST /api/v1/generations` according to OpenAPI. Use dependency injection to select fake provider in tests and local demo mode. Do not allow an accidental production deployment to use fake output without clear configuration or visible indication.
- The service must not retain source drafts or generated paper content server-side.
- Never treat a provider response as trusted simply because it parses as JSON.

Tests: successful generation; invalid request rejected before provider call; provider timeout; unavailable/rate-limited provider; malformed output; integrity warning behavior; request ID in errors; no source content persisted or logged. Include a deterministic fixture suitable for the mobile integration later.

This milestone is not complete until the endpoint can be exercised through FastAPI's test client and the failure cases are asserted. Update docs only for observed contract changes.
```
