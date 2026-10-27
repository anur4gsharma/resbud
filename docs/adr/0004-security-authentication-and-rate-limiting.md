# 0004 — Security, Authentication, and Rate Limiting for Remote Release

## Context

Resbud is transitioning from local development mode to preparation for remote beta testing.
Prompt 17 requires distinguishing local loopback execution from remotely reachable deployments,
implementing required security controls (authentication, rate limiting, secrets management, CORS, zero-content logging),
and documenting decisions that depend on deployment and hosting choices.

The core application handles potentially confidential research drafts, ideas, and unpublished data.
Per `docs/06-security-privacy.md`, the backend must not store research drafts or export files persistently,
and must reject unauthenticated requests in production environments.

## Decisions

### 1. Authentication Strategy: Managed OIDC Bearer Tokens
- **Decision:** Remote API endpoints (`/api/v1/generations`, `/api/v1/generations/sections`, `/api/v1/exports/docx`) require an HTTP Bearer JWT token in production environments.
- **Why:** Custom password and credential systems create unnecessary security liabilities. Standard OIDC/OAuth2 tokens from managed identity providers (e.g., Auth0, Firebase Auth, Google Identity, Keycloak) provide battle-tested issuance, rotation, and revocation.
- **Enforcement:**
  - In `production`: The API fails closed. Requests without a valid Bearer token matching `RESBUD_AUTH_ISSUER` and `RESBUD_AUTH_AUDIENCE` receive HTTP `401 UNAUTHENTICATED`.
  - In `development` / `test`: Unauthenticated loopback requests are permitted for local development if `RESBUD_AUTH_ISSUER` is unset. If configured, token validation is enforced.
  - Health probes (`/health/live`, `/health/ready`) remain unauthenticated and leak no secret or configuration details.

### 2. Rate Limiting Strategy
- **Decision:** Apply per-caller sliding-window rate limiting on cost-intensive generation and export endpoints.
- **Enforcement:**
  - Identified by authenticated user ID (`sub` claim) when available, falling back to client IP for unauthenticated or development callers.
  - When the rate limit is exceeded, the server returns HTTP `429 RATE_LIMITED` with a `Retry-After` header and safe `ApiErrorResponse`.
  - **Limitation:** The default in-memory rate limiter is instance-local. In multi-instance deployments, rate limiting must be delegated to a shared cache (Redis) or edge gateway (Cloudflare, AWS API Gateway) to enforce a true global quota.

### 3. Server-Side Non-Retention of Content
- **Decision:** Research paper generation and DOCX conversion are strictly ephemeral in-memory operations.
- **Enforcement:**
  - Neither generation prompts, outputs, nor DOCX export binaries are persisted to server disks or databases.
  - Request boundaries enforce a 4 MiB payload cap before JSON parsing to bound memory usage.
  - Temporary files are never written to disk during document export (`BytesIO` in-memory buffers only).

### 4. Zero-Content Operational Logging
- **Decision:** Operational logs capture only request metadata (request ID, HTTP method, route path, status code, duration ms, and high-level caller classification).
- **Enforcement:**
  - No source drafts, prompts, references, paper text, file bytes, auth headers, or API secrets are written to logs.
  - Unhandled exceptions are intercepted at the ASGI middleware boundary, returning generic `500 INTERNAL_ERROR` with a correlation ID while keeping stack traces out of client responses and logs.

## Hosting vs Code Dependencies

| Control | Enforced by Code | Enforced by Hosting / Infrastructure |
|---|---|---|
| JWT validation (issuer, audience, expiry) | Yes (`resbud_api.core.auth`) | Token issuance & user management (Identity Provider) |
| Request body size limit (4 MiB) | Yes (`RequestBoundaryMiddleware`) | Reverse proxy body cap (e.g. Nginx `client_max_body_size`) |
| In-process rate limiting | Yes (`resbud_api.core.rate_limit`) | Global multi-instance quota / DDoS protection (WAF/Gateway) |
| Secret redaction & zero content logs | Yes (`SafeUnexpectedErrorMiddleware`) | Log storage access controls and retention policies |
| CORS origin restrictions | Yes (`CORSMiddleware` exact origins) | Domain DNS and edge routing |
| HTTPS / TLS encryption in transit | Partial (HSTS header recommendation) | TLS certificates & termination at load balancer / proxy |
| Provider API key security | Yes (pydantic `SecretStr`, env vars only) | Cloud KMS / Secrets Manager runtime injection |
