# Prompt 20 — Deployment and Release Preparation

```text
Prepare Resbud for a controlled private beta, following the security release gate. Do not deploy or publish anything without explicit authorization and available credentials.

Deliver:
- A repeatable backend container/deployment configuration suitable for the selected hosting target. Use a non-root user where supported, bounded health checks, explicit port/config, and no secrets in image layers.
- Production configuration documentation and `.env.example`; secret values must be supplied by the deployment environment.
- Startup/readiness behavior that fails safely when required configuration is missing.
- TLS/HTTPS expectation, allowed origins, authentication, request-size limits, rate limits, logging/redaction, and operational health checks documented.
- Android build instructions and build artifact path. Keep signing keys out of Git. Document iOS build limitation on non-macOS hosts.
- A rollback/recovery note and a concise incident checklist for provider outage, elevated API cost, leaked credential, or data-loss report.
- A final privacy notice that matches real data flow, not aspirational behavior.
- Build/test commands that can be followed from a clean checkout.

Run container build and available smoke tests if tooling is available. Do not introduce Kubernetes or a queue without measured need. Do not claim deployment is done if credentials, DNS, secrets, or a real deployment target are missing; provide a deployment-ready checklist and distinguish verified vs pending.
```
