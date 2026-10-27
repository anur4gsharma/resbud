# Prompt 03 — FastAPI Foundation, Configuration, and Errors

```text
Implement the backend foundation for Resbud only: application assembly, typed configuration, health endpoints, request IDs, and a stable error format. Follow the reconciled API/architecture/security docs.

Requirements:
- Create the FastAPI app through a testable application factory if suitable.
- Add `/health/live` and `/health/ready`. Readiness checks required configuration without exposing secret values or provider diagnostics. Incomplete required production config must fail safely; local test/development behavior must be explicit.
- Use typed settings with documented environment variables and safe defaults. Do not log the settings object if it may contain secrets.
- Generate or propagate a request/correlation ID and include it in error responses and response headers where specified.
- Normalize validation and application errors to the documented stable JSON error shape with safe user-facing detail and stable error codes.
- Keep CORS restrictive and environment-aware; do not use wildcard origins with credentials.
- Add bounded request-body size handling where appropriate and ensure unexpected exceptions return a safe response while logging only redacted operational details.
- Keep route modules thin. Do not add provider or database behavior yet.

Tests must cover liveness/readiness, missing configuration, request ID propagation, invalid payload error shape, safe generic 500 behavior, and confirmation that exception/response logs do not contain sensitive request content.

Run format, lint/type checks configured in the repo, and pytest. Update setup docs and the error contract if implementation reveals a mismatch. Report exact results.
```
