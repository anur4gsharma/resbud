# Operations, Deployment, and Incident Guide

This guide details the packaging, operational configuration, mobile release builds, incident checklists, rollback procedures, and verified real-world privacy architecture for the Resbud private beta release.

---

## 1. Backend Containerization and Packaging

### 1.1 Multi-Stage Dockerfile

The backend container configuration is located at `backend/Dockerfile` and utilizes a hardened multi-stage build:

1. **Stage 1 (Builder)**:
   - Uses `ghcr.io/astral-sh/uv:python3.12-bookworm-slim`.
   - Uses `uv sync --frozen --no-dev --no-install-project` with layer caching to install locked dependencies from `uv.lock`.
   - Installs the application package into `/app/.venv`.
2. **Stage 2 (Runtime)**:
   - Uses `python:3.12-slim-bookworm`.
   - Runs as a dedicated non-root user (`appuser`, UID/GID `10001`).
   - Copies only the virtual environment and source code with non-root ownership.
   - Eliminates compilers, development headers, package managers, and secret files.
   - Exposes port `8000`.
   - Configures a bounded `HEALTHCHECK` querying `/health/live` with a 5s timeout and 30s interval.

### 1.2 Local Container Orchestration (`compose.yaml`)

To build and run the backend locally in a production-like container:

```bash
docker compose build
docker compose up -d
```

Verify status and bounded health:
```bash
docker compose ps
docker compose logs -f api
curl -f http://127.0.0.1:8000/health/live
```

---

## 2. Production Configuration and Fail-Closed Readiness

### 2.1 Configuration Variables

All configuration is read from `RESBUD_*` environment variables (or `.env` in local development). In production, values **must** be supplied by the host environment or a secret manager (such as AWS Secrets Manager, GCP Secret Manager, or HashiCorp Vault):

| Environment Variable | Production Requirement | Description |
|---|---|---|
| `RESBUD_ENV` | Required (`production`) | Enforces production security gates. Rejects `fake` provider. |
| `RESBUD_GENERATION_PROVIDER` | Required (`openai`) | Configures active model provider adapter. |
| `RESBUD_PROVIDER_MODEL` | Required (e.g. `gpt-4o`) | Specific LLM model deployment identifier. |
| `RESBUD_PROVIDER_API_KEY` | Required (Secret) | Server-side provider secret key. Redacted from logs. |
| `RESBUD_PROVIDER_MAX_OUTPUT_TOKENS` | Optional (default: `12000`) | Hard ceiling on output tokens per generation request. |
| `RESBUD_PROVIDER_CONNECT_TIMEOUT_SECONDS` | Optional (default: `5.0`) | Connection timeout for provider HTTP client. |
| `RESBUD_PROVIDER_READ_TIMEOUT_SECONDS` | Optional (default: `90.0`) | Read/generation timeout for provider HTTP client. |
| `RESBUD_AUTH_ISSUER` | Required (HTTPS URL) | Trusted JWT issuer (e.g., `https://auth.resbud.example.com/`). |
| `RESBUD_AUTH_AUDIENCE` | Required (String) | Expected JWT audience claim. |
| `RESBUD_AUTH_SIGNING_KEY` | Required (Secret) | HMAC-SHA256 secret key for bearer token verification. |
| `RESBUD_RATE_LIMIT_PER_MINUTE` | Optional (default: `60`) | Sliding-window request rate limit per IP/client token. |
| `RESBUD_CORS_ALLOWED_ORIGINS` | Required if Web (JSON) | Exact allowed origins list. Wildcards (`*`) are rejected. |
| `RESBUD_MAX_REQUEST_BODY_BYTES` | Optional (default: `4194304`) | Request boundary limit (4MB maximum). |

### 2.2 Fail-Closed Operational Health Checks

The backend provides two standard operational health endpoints:

1. **Liveness Check (`GET /health/live`)**:
   - Returns HTTP `200` with `{"status": "alive"}` when the ASGI event loop and Uvicorn process are responsive.
   - Used by load balancers and container orchestrators for liveness probes.
2. **Readiness Check (`GET /health/ready`)**:
   - In `development` mode, returns HTTP `200` with `{"status": "ready", "provider": "...", "environment": "development"}`.
   - In `production` mode, validates that all mandatory security configuration is present:
     - Provider credentials and model are configured.
     - Auth issuer, audience, and signing key are present.
     - Fake provider is NOT configured.
   - If any required configuration is missing, returns HTTP `503 Service Unavailable` with `{"status": "not_ready", "issues": [...]}` containing non-sensitive variable names only.

### 2.3 Network Boundaries and TLS Expectations

- **TLS/HTTPS**: The application process binds to cleartext HTTP on port `8000`. Production deployments **must** terminate TLS 1.3 at a reverse proxy, API gateway, or cloud load balancer (e.g., Cloudflare, AWS ALB, NGINX) before forwarding traffic to the container. The proxy must pass standard forwarding headers:
  - `X-Forwarded-Proto: https`
  - `X-Forwarded-For: <client-ip>`
- **CORS Protection**: CORS headers are only emitted for origins explicitly listed in `RESBUD_CORS_ALLOWED_ORIGINS`. Wildcards and path components are rejected at configuration parse time.
- **Request Size Boundaries**: The `RequestBoundaryMiddleware` rejects payloads larger than `max_request_body_bytes` before body streaming completes, returning HTTP `413 Payload Too Large`.

---

## 3. Mobile Client Release Packaging

### 3.1 Android Build Instructions

Prerequisites: Flutter SDK 3.41+ and Android SDK Command-line Tools / Build-tools.

1. **Prepare Release Keystore**:
   Create a Java keystore if not already existing:
   ```bash
   keytool -genkey -v -keystore ~/.android-certs/resbud-release.jks \
       -keyalg RSA -keysize 2048 -validity 10000 -alias resbud
   ```
2. **Configure `key.properties` (Outside Version Control)**:
   Create `mobile/android/key.properties` (this file is excluded by `.gitignore`):
   ```properties
   storePassword=<keystore-password>
   keyPassword=<alias-password>
   keyAlias=resbud
   storeFile=/absolute/path/to/resbud-release.jks
   ```
3. **Build Android APK (for private beta sideloading / testing)**:
   ```bash
   cd mobile
   flutter build apk --release
   ```
   **Artifact Path**: `mobile/build/app/outputs/flutter-apk/app-release.apk`
4. **Build Android App Bundle (for Google Play distribution)**:
   ```bash
   cd mobile
   flutter build appbundle --release
   ```
   **Artifact Path**: `mobile/build/app/outputs/bundle/release/app-release.aab`

### 3.2 iOS Build Limitation

- **Host Limitation**: Building native iOS binaries (`.ipa` or Runner archive) requires **macOS** with **Xcode 15+** and CocoaPods installed.
- **Linux/Windows Environment**: The current development environment is Linux. iOS compilation cannot be performed locally and must be built on a macOS CI runner or dedicated Mac build machine.

---

## 4. Rollback and Recovery Runbook

### 4.1 Backend Rollback Procedure

All backend container images are immutable and tagged with git commit hashes:

1. Identify the last known good commit SHA (e.g., `git log -n 5 --oneline`).
2. Update the container image tag in your deployment manifest or orchestration configuration:
   ```bash
   docker service update --image resbud-api:<previous-stable-sha> resbud-api
   ```
3. Verify that the rollback instance passes readiness checks:
   ```bash
   curl -f http://<instance-ip>:8000/health/ready
   ```

### 4.2 Database and Schema Recovery

- **Mobile Client Storage**: Resbud uses an on-device SQLite database.
- **Migration Safety**: SQLite migrations are linear and transactional. Each migration runs inside a transaction that rolls back automatically if any statement fails.
- **Version Snapshots**: Generated drafts, edits, and section replacements are recorded as append-only immutable rows in the `paper_versions` table. A failed edit or corrupt draft can be immediately restored from any previous version via the UI or SQLite query (`SELECT * FROM paper_versions WHERE project_id = ?`).

---

## 5. Incident Checklists

### Incident 1: Provider Outage or Degradation

**Symptoms**: Increased HTTP 504 (Timeout) or 502/503 (Provider Invalid/Unavailable) error rates.

1. **Verify Provider Health**:
   - Check OpenAI Status Page (`https://status.openai.com/`).
   - Inspect backend operational logs for `[ERROR] HTTP 504 - PROVIDER_TIMEOUT` or `PROVIDER_UNAVAILABLE`.
2. **Client Resilience Verification**:
   - Ensure mobile clients display the user-friendly offline/timeout dialog with the associated Request ID.
   - Verify that client-side drafts remain fully intact in SQLite and are not cleared by failed generation calls.
3. **Mitigation Actions**:
   - If provider latency has increased globally, temporarily increase `RESBUD_PROVIDER_READ_TIMEOUT_SECONDS` up to 120s.
   - If provider is completely unavailable, notify beta users via the beta communication channel. Do not change code or clear client caches.

### Incident 2: Elevated API Cost or Quota Exhaustion

**Symptoms**: Backend receives HTTP 429 from OpenAI, or unexpected cost spikes in provider dashboard.

1. **Identify Abuse Source**:
   - Inspect reverse proxy logs for anomalous request rates grouped by client IP or Bearer token subject.
2. **Mitigation Actions**:
   - Reduce `RESBUD_RATE_LIMIT_PER_MINUTE` (e.g., lower to 10 requests per minute).
   - Verify `RESBUD_PROVIDER_MAX_OUTPUT_TOKENS` is capped at 12,000 tokens.
   - Block offending IPs or revoke compromised client JWT tokens at the auth provider.

### Incident 3: Leaked Credential

**Symptoms**: Secret scanning alert (GitHub Secret Scanning, GitGuardian) or credential compromise report.

1. **Revoke Immediately**:
   - In the OpenAI dashboard, immediately revoke the compromised API key.
   - In the auth provider dashboard, rotate the JWT signing secret.
2. **Deploy Replacement Secret**:
   - Generate a new provider API key and update your production secret manager.
   - Restart backend instances to load the new credentials.
3. **Verify Zero Secrets in Version Control**:
   - Run `git log -S "sk-"` to confirm no keys were committed.
   - Rotate any client beta testing tokens.

### Incident 4: User Data-Loss Report

**Symptoms**: User reports project or paper draft disappeared or was accidentally overwritten.

1. **Triage Local SQLite**:
   - The Resbud backend never stores user papers, so data recovery is entirely on-device.
   - Have the user navigate to **Version History** in the paper editor: verify if an earlier version snapshot (v1, v2, etc.) is listed.
   - Tapping **Restore Version** will restore the selected snapshot as a new version.
2. **Export Recovery**:
   - If the project is intact, prompt the user to use **Export DOCX** to create an external backup file in their device Documents folder.

---

## 6. Real Data Flow Privacy Notice

Resbud's data handling strictly matches actual operational behavior:

```
[On-Device SQLite Storage]
  - Projects, research fields, questions, objectives, drafts
  - Immutable version history (v1, v2, v3, ...)
  - Exported DOCX documents
       │
       │ User initiates Generation or Section Regeneration
       ▼ (TLS 1.3 / HTTPS)
[Resbud Backend API]
  - Validates request boundaries and JWT authentication
  - Extracts research brief into structured prompt
  - Stateless in-memory conduit: DOES NOT PERSIST DRAFTS OR PAPERS
  - Logs operational metadata only: method, status, duration, request_id
       │
       │ Model API invocation
       ▼ (TLS 1.3 / HTTPS)
[Configured LLM Provider (e.g., OpenAI API)]
  - Evaluates research brief under zero-data-retention policy
  - Returns structured PaperDraft JSON payload
       │
       │ Response streaming & schema validation
       ▼
[Resbud Backend API]
  - Validates response strictly against PaperDraft schema
  - Emits review warnings (missing results, unverifiable citations)
       │
       │ Validated payload returned
       ▼
[Mobile Client (On-Device)]
  - Saves new immutable version into local SQLite
  - Renders draft for user review and section editing
```

---

## 7. Deployment-Ready Checklist (Verified vs Pending)

| Category | Item | Status | Evidence / Notes |
|---|---|---|---|
| **Architecture** | Stateless container configuration | **Verified** | `backend/Dockerfile`, `compose.yaml` with non-root user |
| **Security** | Production fail-closed configuration | **Verified** | `Settings.readiness_issues()`, `test_security_and_auth.py` |
| **Security** | Zero user data in server logs | **Verified** | `test_generation_does_not_persist_or_log_source_content` |
| **Security** | Secret scanning & redaction | **Verified** | `SafeUnexpectedErrorMiddleware`, `.dockerignore`, `.env.example` |
| **Security** | JWT Authentication enforcement | **Verified** | `JwtAuthenticator`, 401 on unauthenticated requests |
| **Security** | Sliding-window rate limiting | **Verified** | `InMemoryRateLimiter`, 429 throttling with `Retry-After` |
| **Packaging** | Android release build scripts | **Verified** | `flutter build apk --release`, `flutter build appbundle` |
| **Infrastructure** | Production domain DNS & TLS certificates | **Pending** | Requires live beta domain assignment |
| **Infrastructure** | Production Cloud Secret Manager injection | **Pending** | Requires production cloud deployment target |
| **Store** | Google Play Developer Account setup | **Pending** | Requires commercial developer account for Play store upload |
| **Store** | Apple Developer Account & macOS runner | **Pending** | Requires macOS CI runner and Apple Developer certificate |
