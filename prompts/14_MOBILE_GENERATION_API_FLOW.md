# Prompt 14 — Mobile API Client and Generation State Machine

```text
Connect the Flutter app to the generation API using the fake provider in local development first. Read the OpenAPI contract before implementing the client.

Requirements:
- Create a typed API client with configurable base URL; no hardcoded production endpoint.
- Map request/response models and stable backend error codes. Do not parse human-readable `detail` text to decide application behavior.
- Implement a clear state machine: idle/ready, validating, generating, success, and recoverable failure (plus any states the design genuinely requires). Prevent duplicate submission while a request is active.
- Show progress and explain that generation may take time; avoid fake percentage progress if the server cannot provide it.
- Configure explicit client timeout behavior. Do not silently retry a possibly billable request after ambiguous timeout; show that retrying may trigger another call.
- Preserve source input and saved paper on failure. Do not overwrite the current paper until the result has been validated and the user chooses to review/accept/save it.
- Include request/correlation ID in support-friendly error detail where safe.
- Keep network concerns out of UI widgets. Inject the client so widget tests can use deterministic fakes.

Tests: serialization/contract fixtures, mapping each stable error code, success flow, duplicate-submit prevention, timeout, offline/unavailable behavior, malformed response, and confirmation that failure leaves saved data unchanged. Use the fake backend for a repeatable manual vertical-slice demo.
```
