# 24 — Operations, Observability, and Rollback Runbook

**Target Service:** `resbud-api`  
**Hosting Environment:** Render Web Service (`srv-dbt0425ckfvc73cd2s50`)  
**Production URL:** `https://resbud-api.onrender.com`  
**Operational Lead:** Senior Backend & DevOps Engineer  

---

## 1. Privacy-Preserving Observability Architecture

Resbud enforces strict data privacy at the infrastructure boundary. Operational metrics and error logs track system health without retaining research manuscripts, user drafts, or full LLM prompts.

### 1.1 Metrics Collected & Monitoring Dashboard

Access the live metrics dashboard at:  
`https://dashboard.render.com/web/srv-dbt0425ckfvc73cd2s50/metrics`

| Metric | Source | Warning Threshold | Critical Threshold | Remediation Action |
|---|---|:---:|:---:|---|
| **CPU Utilization** | Render Container Telemetry | > 75% for 5m | > 90% for 2m | Scale instance or check for runaway mathematical LaTeX rendering loops. |
| **Memory (RAM) Usage** | Render Container Telemetry | > 700 MB | > 900 MB (1GB limit) | Restart container to clear cached fonts / matplotlib textures. |
| **HTTP 5xx Error Rate** | Cloudflare / Uvicorn Logs | > 1% of requests | > 5% of requests | Check Gemini API quotas and review `X-Request-ID` logs. |
| **HTTP 429 Rate Limits** | Uvicorn Access Log | > 10% of requests | > 25% of requests | Inspect caller IPs for abusive traffic or adjust `RESBUD_RATE_LIMIT_PER_MINUTE`. |
| **Request Latency (p95)** | Edge Proxy Telemetry | > 15s | > 45s | Check provider network latency or adjust timeout settings. |
| **Service Readiness** | `GET /health/ready` | 503 Service Unavailable | Persistent 503 | Verify environment variables (`RESBUD_PROVIDER_API_KEY`, `RESBUD_AUTH_ISSUER`). |

### 1.2 Structured Operational Logging Rules

1. **No Sensitive Data:** Never log raw user drafts, generated paragraphs, references, or API keys (`NFR-001`, `NFR-002`).
2. **Correlation ID Tracking:** Every request generates or propagates an `X-Request-ID` header.
   ```
   INFO: 10.29.164.47:0 - "POST /api/v1/generations HTTP/1.1" 422 Unprocessable Entity
   ERROR: unhandled_request_error request_id=4cd6e89d-a565-4163-b237-9cc25ac59e7d method=POST route=/api/v1/generations
   ```
3. **Problem Details Format:** All errors follow RFC-7807 with safe messages, machine codes (`UNAUTHENTICATED`, `VALIDATION_ERROR`, `INPUT_TOO_LARGE`, `RATE_LIMITED`, `INTERNAL_ERROR`), and the correlating `request_id`.

---

## 2. Incident Response Runbook

### Incident Triage Workflow

```
[Alert Fired / User Report]
           │
           ▼
[Check /health/live & /health/ready]
   ├─► Both 200 OK ──────────► Check Provider Quotas & External APIs
   └─► Ready 503 / Down ─────► Check Environment Variables & Container Logs
                                       │
                                       ▼
                       [Is Defect in Application Code?]
                                  ├─► YES ──► Trigger Instant Rollback
                                  └─► NO  ──► Check Cloud Provider Status
```

### Diagnostic Commands

#### 1. Check Service Liveness and Readiness
```bash
# Check if container is running
curl -i https://resbud-api.onrender.com/health/live

# Check if configuration and provider are ready
curl -i https://resbud-api.onrender.com/health/ready
```

#### 2. Inspect Server Logs via Render MCP Tool
```json
{
  "ServerName": "render",
  "ToolName": "list_logs",
  "Arguments": {
    "resource": ["srv-dbt0425ckfvc73cd2s50"],
    "type": ["app"],
    "direction": "backward",
    "limit": 50
  }
}
```

#### 3. Inspect Container Resource Metrics via Render MCP Tool
```json
{
  "ServerName": "render",
  "ToolName": "get_metrics",
  "Arguments": {
    "serviceId": "srv-dbt0425ckfvc73cd2s50",
    "metricType": "cpu"
  }
}
```

---

## 3. Rollback Procedures

If a newly deployed version introduces regressions, errors, or unexpected latency, execute a rollback to the previous stable release.

### Procedure A: Instant Rollback via Render Dashboard / MCP (Zero Rebuild)

Render retains pre-built container images for previous deployments. Rolling back to a previously successful deployment reactivates the image without rebuilding:

1. List recent deploys to identify the last known stable Deploy ID:
   ```json
   {
     "ServerName": "render",
     "ToolName": "list_deploys",
     "Arguments": {
       "serviceId": "srv-dbt0425ckfvc73cd2s50",
       "limit": 5
     }
   }
   ```
2. Navigate to Render Dashboard:
   `https://dashboard.render.com/web/srv-dbt0425ckfvc73cd2s50/deploys`
3. Click on the prior stable deployment (e.g. `dep-dbt042dckfvc73cd2sl0`).
4. Select **Rollback to this deploy**. Render will reroute traffic to the previous healthy container image within 15–30 seconds.

### Procedure B: Git-Driven Rollback (Standard Production Flow)

1. Identify the previous stable commit SHA on `main`:
   ```bash
   git log -n 5 --oneline
   ```
2. Revert the problematic commit or reset `main` to the stable commit:
   ```bash
   git revert <bad-commit-sha>
   git push origin main
   ```
3. Because Auto-Deploy is enabled (`autoDeploy: "yes"`), Render will automatically build and deploy the reverted commit.
4. If immediate cache bypass is required, trigger a manual deploy:
   ```json
   {
     "ServerName": "render",
     "ToolName": "trigger_deploy",
     "Arguments": {
       "serviceId": "srv-dbt0425ckfvc73cd2s50",
       "clearCache": "clear"
     }
   }
   ```

---

## 4. Secret Rotation Procedures

### 4.1 Rotating the Google Gemini Provider API Key
1. Obtain the new API key from Google AI Studio.
2. Update the environment variable on Render:
   - Go to `https://dashboard.render.com/web/srv-dbt0425ckfvc73cd2s50/env` (or use `update_environment_variables`).
   - Append the new key to `RESBUD_PROVIDER_API_KEY` (comma-separated):
     `NEW_KEY,OLD_KEY`
   - Save changes. Render triggers a zero-downtime rolling update.
3. Verify `/health/ready` returns `200 OK`.
4. Remove `OLD_KEY` from the variable once confirmed.

### 4.2 Rotating the JWT Authentication Signing Key
1. Generate a new 64-character random hex string:
   ```bash
   python3 -c "import secrets; print(secrets.token_hex(32))"
   ```
2. Update `RESBUD_AUTH_SIGNING_KEY` on Render.
3. Distribute the new token signing secret to the mobile token issuer.
4. Old tokens will be invalidated; active client sessions will authenticate with fresh tokens upon reissue.

---

## 5. Cold-Start and Scaling Recommendations

- **Current Tier:** Render Free Tier. Automatically sleeps after 15 minutes of inactivity. First request takes ~30-50s to wake up.
- **Production Upgrade Path:** Upgrade to Render `starter` plan ($7/mo) to eliminate sleep and maintain 100% warm availability.
- **Horizontal Scaling:** When scaling to multiple instances (`numInstances > 1`), configure a Redis cluster and point `InMemoryRateLimiter` to a shared Redis instance to ensure global rate limit enforcement.
