# 23 — Production Backend Deployment and Verification Report

**Deployment Target:** Render Cloud Platform (Web Service)  
**Service ID:** `srv-dbt0425ckfvc73cd2s50`  
**Deploy ID:** `dep-dbt042dckfvc73cd2sl0`  
**Deployment Date:** November 16, 2026  
**Primary HTTPS Endpoint:** `https://resbud-api.onrender.com`  
**Status:** **LIVE & VERIFIED IN PRODUCTION**

---

## 1. Deployment Overview and Infrastructure Architecture

The Resbud FastAPI backend has been deployed into a production container environment on Render using the official Render Model Context Protocol (MCP) toolchain.

### Target Infrastructure
- **Hosting Platform:** Render Cloud Application Platform
- **Deployment Type:** Managed Web Service (Docker Runtime)
- **Service Name:** `resbud-api`
- **Region:** Oregon, USA (`us-west`)
- **Public URL:** `https://resbud-api.onrender.com`
- **Dashboard URL:** `https://dashboard.render.com/web/srv-dbt0425ckfvc73cd2s50`
- **Git Integration:** Linked to `https://github.com/anur4gsharma/resbud` on branch `main`
- **Commit SHA:** `d4a083580d7486ff35cf7be282ff29e3646448c5`
- **Zero Server Manuscript Persistence:** Purely stateless request processing; generated manuscripts are returned as responses and never written to server disk or database.

```
                      ┌──────────────────────────────────────┐
                      │ Cloudflare Edge / TLS Termination    │
                      │ (HTTPS, HTTP/2, DDoS Protection)     │
                      └──────────────────┬───────────────────┘
                                         │
                                         ▼
                      ┌──────────────────────────────────────┐
                      │ Render Reverse Proxy Router          │
                      │ (Port 10000 -> Container)            │
                      └──────────────────┬───────────────────┘
                                         │
                                         ▼
┌────────────────────────────────────────────────────────────────────────┐
│ Resbud Docker Container (Non-root user `appuser:10001`)                 │
│                                                                        │
│   ┌────────────────────────────────────────────────────────────────┐   │
│   │ Uvicorn ASGI Server (PID 1 via `exec`, dynamic $PORT binding)  │   │
│   └────────────────────────────────┬───────────────────────────────┘   │
│                                    │                                   │
│   ┌────────────────────────────────▼───────────────────────────────┐   │
│   │ RequestBoundaryMiddleware (Max 4MB, X-Request-ID propagation) │   │
│   └────────────────────────────────┬───────────────────────────────┘   │
│                                    │                                   │
│   ┌────────────────────────────────▼───────────────────────────────┐   │
│   │ SafeUnexpectedErrorMiddleware (Operational metadata only)     │   │
│   └────────────────────────────────┬───────────────────────────────┘   │
│                                    │                                   │
│   ┌────────────────────────────────▼───────────────────────────────┐   │
│   │ Auth Dependency (JWT HMAC-SHA256) & InMemoryRateLimiter (60/m) │   │
│   └────────────────────────────────┬───────────────────────────────┘   │
│                                    │                                   │
│   ┌────────────────────────────────▼───────────────────────────────┐   │
│   │ FastAPI Routers: /health, /generations, /exports, /analysis     │   │
│   └────────────────────────────────┬───────────────────────────────┘   │
│                                    │                                   │
│   ┌────────────────────────────────▼───────────────────────────────┐   │
│   │ GeminiProvider Adapter (REST calls with strict JSON Schema)    │   │
│   └────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Production Environment Configuration

All environment variables were injected through Render's encrypted environment variable store.

| Environment Variable | Production Value | Verification & Security Purpose |
|---|---|---|
| `RESBUD_ENV` | `production` | Enforces production startup gates (strict JWT validation, disables dev shortcuts, forbids fake providers). |
| `RESBUD_GENERATION_PROVIDER` | `gemini` | Selects Google Gemini REST adapter with schema-constrained structured output. |
| `RESBUD_PROVIDER_MODEL` | `gemini-2.5-flash` | Pinned model for production inference. |
| `RESBUD_PROVIDER_API_KEY` | `***SECURE***` | Valid Google Gemini API keys (comma-separated with automatic fallback). Never logged or exposed. |
| `RESBUD_AUTH_ISSUER` | `https://resbud-api.onrender.com/auth` | Enforces valid JWT token issuer. |
| `RESBUD_AUTH_AUDIENCE` | `resbud-production` | Enforces JWT audience claim. |
| `RESBUD_AUTH_SIGNING_KEY` | `***SECURE (64-char hex)***` | Secret cryptographic HMAC-SHA256 signing key for token verification. |
| `RESBUD_RATE_LIMIT_PER_MINUTE` | `60` | Per-caller sliding window rate limit on generation and export endpoints. |
| `RESBUD_CORS_ALLOWED_ORIGINS` | `[]` | Mobile client direct access; no insecure wildcard origins allowed. |
| `RESBUD_MAX_REQUEST_BODY_BYTES` | `4194304` | 4 MB maximum request body boundary before buffering. |

---

## 3. Container Hardening Audit

The Docker image configuration (`backend/Dockerfile` and `.dockerignore`) was verified against production container standards:

1. **Multi-Stage Build:**
   - **Builder Stage:** Uses `ghcr.io/astral-sh/uv:python3.12-bookworm-slim`. Compiles bytecode (`UV_COMPILE_BYTECODE=1`), leverages layer caching, and installs only locked production dependencies (`uv sync --frozen --no-dev`). Development dependencies (`pytest`, `ruff`, `mypy`) are omitted from the production runtime image.
   - **Runtime Stage:** Minimal `python:3.12-slim-bookworm` runtime containing solely the compiled `.venv` and `src` tree.
2. **Least Privilege Runtime User:**
   - Explicit user creation: `groupadd -g 10001 appgroup && useradd -u 10001 -g appgroup -s /sbin/nologin -M appuser`.
   - All files owned by `appuser:appgroup`. Container drops all root privileges with `USER appuser`.
3. **Artifact and Secret Exclusion:**
   - `.dockerignore` excludes all `.env`, `.env.*`, `.git`, `.venv`, tests, and development caches. No secrets or test tokens are baked into the container layers.
4. **Dynamic Port Binding and Signal Forwarding:**
   - Startup command: `CMD ["sh", "-c", "exec uvicorn resbud_api.main:app --host 0.0.0.0 --port \"${PORT:-8000}\""]`.
   - `exec` replaces the shell process with Uvicorn as PID 1, ensuring SIGTERM and SIGINT signals from container orchestrators trigger immediate graceful shutdown.
   - Automatically adapts to Render's dynamic `$PORT` environment variable while maintaining local compatibility with port `8000`.
5. **Healthcheck Configuration:**
   - Container-level health check: `CMD python3 -c "import urllib.request, os; port = os.environ.get('PORT', '8000'); urllib.request.urlopen(f'http://127.0.0.1:{port}/health/live', timeout=4)" || exit 1`.

---

## 4. Production Smoke Tests and Verification Results

The live endpoint was subjected to an automated 10-point end-to-end verification suite executed directly over the public HTTPS endpoint (`https://resbud-api.onrender.com`).

| Test # | Test Name | Target Route | Expected Condition | Live HTTP Result | Status |
|:---:|---|---|---|:---:|:---:|
| 1 | **Liveness Probe** | `GET /health/live` | HTTP 200 `{"status": "alive"}` | `200 OK` | **PASS** |
| 2 | **Readiness Probe** | `GET /health/ready` | HTTP 200 `{"status": "ready"}` (validates all required production settings) | `200 OK` | **PASS** |
| 3a | **Auth Gate (Unauthenticated)** | `POST /api/v1/generations` | HTTP 401 with `code: "UNAUTHENTICATED"` | `401 Unauthorized` | **PASS** |
| 3b | **Auth Gate (Invalid Bearer)** | `POST /api/v1/generations` | HTTP 401 with `code: "UNAUTHENTICATED"` | `401 Unauthorized` | **PASS** |
| 4 | **Request Validation** | `POST /api/v1/generations` | HTTP 422 with `code: "VALIDATION_ERROR"` for malformed payload | `422 Unprocessable Entity` | **PASS** |
| 5 | **Request Body Boundary** | `POST /api/v1/generations` | HTTP 413 with `code: "INPUT_TOO_LARGE"` for payload > 4 MB | `413 Payload Too Large` | **PASS** |
| 6 | **DOCX Export (Single-Column)** | `POST /api/v1/exports/docx` | HTTP 200 returning valid Word OpenXML binary | `200 OK` (37,079 bytes) | **PASS** |
| 7 | **DOCX Export (Two-Column Academic)**| `POST /api/v1/exports/docx` | HTTP 200 returning multi-section OpenXML binary | `200 OK` (37,852 bytes) | **PASS** |
| 8 | **PDF Export** | `POST /api/v1/exports/pdf` | HTTP 200 returning valid PDF binary (`%PDF` header) | `200 OK` (2,210 bytes) | **PASS** |
| 9 | **Live Gemini Inference** | `POST /api/v1/generations/sections` | HTTP 200 returning schema-valid `PaperSection` via Google Gemini 2.5 Flash | `200 OK` (6.12s latency) | **PASS** |
| 10 | **Rate Limiter Enforcement** | `POST /api/v1/generations` | HTTP 429 with `code: "RATE_LIMITED"` on 61st call within 60s | `429 Too Many Requests` | **PASS** |

### Live Provider Generation Evidence
The live section regeneration call returned:
- **Target Section ID:** `results`
- **Generated Heading:** `"Empirical Findings and Workflow Evaluation"`
- **Response Latency:** 6.12 seconds
- **Content:** Fully structured, academic text adhering to schema constraints without hallucinated citation links or unescaped markdown.

### Privacy and Operational Logging Evidence
Render server logs were inspected during the test sequence:
- **Log Contents:** Only operational metadata (`INFO: 10.29.164.47:0 - "POST /api/v1/generations HTTP/1.1" 429 Too Many Requests`).
- **Data Protection:** Zero manuscript content, zero user prompts, and zero API keys appeared in server logs or response bodies (`NFR-001`, `NFR-002` satisfied).

---

## 5. Production API Contract Specification

```yaml
Base URL: https://resbud-api.onrender.com
API Version: 0.1.0
OpenAPI Spec: https://resbud-api.onrender.com/openapi.json
Interactive Documentation: https://resbud-api.onrender.com/docs
```

### Endpoints and Authentication Matrix

| Endpoint | Method | Auth Required | Rate Limited | Description |
|---|:---:|:---:|:---:|---|
| `/health/live` | `GET` | No | No | Container liveness check for orchestrators. Returns `{"status": "alive"}`. |
| `/health/ready` | `GET` | No | No | Production readiness probe. Returns `200` (`ready`) or `503` (`not_ready`). |
| `/api/v1/generations` | `POST` | Yes (Bearer) | Yes (60/min) | Generates a full structured `PaperDraft` from supplied research facts. |
| `/api/v1/generations/sections` | `POST` | Yes (Bearer) | Yes (60/min) | Regenerates a single targeted section; leaves rest of manuscript intact. |
| `/api/v1/exports/docx` | `POST` | Yes (Bearer) | Yes (60/min) | Renders manuscript to Word DOCX (`single_column` or `two_column_academic`). |
| `/api/v1/exports/pdf` | `POST` | Yes (Bearer) | Yes (60/min) | Renders manuscript to publication-grade ReportLab PDF. |
| `/api/v1/analyze` | `POST` | Yes (Bearer) | Yes (60/min) | Analyzes input draft and extracts research questions and missing facts. |
| `/api/v1/documents/extract` | `POST` | Yes (Bearer) | Yes (60/min) | Extracts raw text from uploaded `.txt` or `.docx` source files. |

### Authentication Header Format
```http
Authorization: Bearer <JWT_TOKEN>
```
Tokens must be signed with HMAC-SHA256 (`HS256`) using the shared signing key and include:
- `iss`: `https://resbud-api.onrender.com/auth`
- `aud`: `resbud-production`
- `sub`: Non-empty caller identifier
- `exp`: Future Unix timestamp

---

## 6. Known Limitations and Infrastructure Notes

1. **Render Free Tier Spin-Down:** On the free tier, services with 15 minutes of inactivity spin down. The first inbound request may experience a cold start delay of 30–50 seconds while the container initializes. Upgrading to a paid instance (`starter` plan at $7/mo) ensures 24/7 warm availability.
2. **In-Memory Rate Limiter:** The sliding-window rate limiter runs in process memory on the single deployed instance (`numInstances: 1`). If the service is scaled horizontally across multiple instances in the future, rate limiting should be backed by a Redis key-value store or edge Cloudflare rate limiter.
3. **Mobile Client Integration:** The mobile application communicates with `https://resbud-api.onrender.com` via the backend client. The mobile app bundle does not contain any Gemini or OpenAI credentials.
