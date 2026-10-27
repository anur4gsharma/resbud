# Prompt 17 — Security, Authentication, Rate Limits, and Privacy Release Gate

```text
Implement and verify the Resbud security controls required for the intended deployment stage. Do not imply the service is production-safe merely because development endpoints work.

First distinguish local development/test mode from remotely reachable deployment. Inspect current auth, proxy, CORS, logging, and hosting configuration. Make the smallest secure design consistent with the specification and document any decision that requires product choice.

Requirements:
- Provider keys only server-side, read from deployment secrets/environment and redacted from logs/errors.
- Remote API endpoints require authentication before beta distribution. Do not invent a fake production identity system; use the project's chosen, documented auth approach or report the exact missing prerequisite.
- Apply per-caller/per-IP rate limits and request/input size limits appropriate to generation cost. If multiple API instances are supported, do not rely on an in-process counter as a global limit; document the limitation or use a shared store only if needed.
- Restrict CORS to intended origins; use HTTPS in deployment; keep debug mode off remotely.
- Do not log source drafts, references, prompts, outputs, uploaded file bytes, auth headers, or secrets. Emit only operational metadata and stable error codes.
- Health/readiness endpoints reveal no secrets or internal stack traces.
- Avoid persisting source content server-side. Ensure temporary files are removed and upload handling is bounded.
- Add a concise user-facing disclosure of what is sent to the backend/model provider, why, and whether Resbud retains it.
- Ensure errors are safe and operational logs are useful without data leakage.

Add tests or automated checks for missing production secret, unauthenticated remote request, rate limit, CORS/configuration, secret redaction, oversized request/upload, and absence of user content in logs. Add a release checklist and state which controls depend on hosting configuration rather than code.
```
