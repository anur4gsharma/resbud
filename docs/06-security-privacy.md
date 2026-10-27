# 06 — Security, Privacy, and Trust Boundaries

This document is a minimum engineering baseline, not a legal compliance certification. Before real users submit sensitive research, review the configured provider's current data-handling terms and obtain appropriate guidance for the deployment context.

## 1. Data flow and trust boundaries

The app handles research drafts that may be unpublished, confidential, or personally identifying. Treat all user content as potentially sensitive.

1. **Device boundary:** project details and saved drafts reside in local storage.
2. **Resbud API boundary:** the generation request temporarily contains the source and project details; DOCX export temporarily contains the current paper.
3. **Model-provider boundary:** generation content is sent to the configured provider to complete the user's explicit action.
4. **Observability boundary:** only operational metadata should enter ordinary application logs.

TXT and DOCX import is performed on-device. The selected file bytes are not uploaded or retained by Resbud for extraction; only text the user chooses to submit is sent during generation. The importer reads UTF-8 TXT or the main DOCX body in memory, ignores document metadata, comments, relationships, macros, and embedded files, and applies the size and ZIP expansion limits in `03-api-contract.md`. Unsupported, encrypted, malformed, or oversized files produce a safe local error and leave the project unchanged.

Before generation, the UI must state that the selected material will be transmitted to the configured model provider. Before export, it must be clear that the current paper passes through the Resbud backend for document conversion.

## 2. Secrets management

- Store provider keys in deployment secret configuration or environment variables injected at runtime.
- Keep `.env` out of version control; commit a `.env.example` containing names and safe placeholders only.
- Never hardcode a provider key in Dart/Flutter, a mobile asset, a public configuration file, a test fixture, or documentation.
- Never log authorization headers, API keys, full provider requests, or provider exception strings that may contain sensitive details.
- Rotate a credential immediately if it is exposed; deleting it from the latest commit is not enough if it has already been pushed.
- Use different credentials for development and deployment.

A mobile app cannot safely protect a shared secret embedded in its binary. A public API must enforce caller authentication and server-side quotas; obscurity of the endpoint is not authentication.

## 3. Authentication and release boundary

Local-only development may run without authentication on loopback or in an explicitly marked development environment. The application must fail closed if unauthenticated mode is enabled in a production-like environment.

Before remote beta distribution:

- select a managed authentication/OIDC approach rather than writing a custom password system;
- validate tokens on the backend, including issuer, audience, signature, expiration, and relevant claims;
- apply per-user or otherwise abuse-resistant rate limits and cost budgets;
- protect all non-health endpoints;
- ensure CORS/network configuration is restrictive where applicable;
- configure HTTPS and a safe deployment process;
- define a way to revoke access and rotate credentials.

Configure CORS only when a browser client needs it: allow the explicitly configured origins and required methods/headers, never a wildcard origin with credentials. Native Flutter clients do not rely on CORS as an access-control mechanism. Set a documented maximum HTTP request-body size (4 MiB for the current JSON contract, accounting for escaped text) before JSON parsing; continue enforcing smaller field, file, and provider-token budgets at their respective boundaries. Readiness reports only `ready`/`503` based on required runtime configuration for the selected mode; it must not make a paid model call or disclose which secret is missing. Liveness reports only process health. These endpoints do not replace authentication on application routes.

The typed settings require an explicit `RESBUD_ENV` (`development`, `test`, or `production`) and use `RESBUD_GENERATION_PROVIDER`, `RESBUD_PROVIDER_MODEL`, `RESBUD_PROVIDER_API_KEY`, `RESBUD_PROVIDER_MAX_OUTPUT_TOKENS`, `RESBUD_PROVIDER_CONNECT_TIMEOUT_SECONDS`, `RESBUD_PROVIDER_READ_TIMEOUT_SECONDS`, `RESBUD_AUTH_ISSUER`, `RESBUD_AUTH_AUDIENCE`, `RESBUD_CORS_ALLOWED_ORIGINS`, and `RESBUD_MAX_REQUEST_BODY_BYTES`. The app does not assume a local mode when the environment is unset. Local demo mode must explicitly set `RESBUD_GENERATION_PROVIDER=fake`; responses identify the fake provider and include a demo warning. Production rejects fake mode. OpenAI mode requires an explicitly configured model and server-side key; disabled mode is not ready. Production readiness is `503` until the selected provider configuration, auth issuer, and auth audience are configured. This is a readiness gate, not authentication enforcement; application routes remain unavailable for release until authentication is implemented.

Authentication provider selection is a deployment decision and must be captured in an ADR before implementation. Do not describe a remote unauthenticated demo server as production-ready.

## 4. Input and model-output validation

- Enforce body size and field length limits before expensive calls.
- Validate enum values, IDs, and schemas strictly.
- Treat imported documents and model responses as untrusted data.
- Do not run, evaluate, or interpret model output as code, a shell command, a path, an SQL fragment, or a template expression.
- Never allow text inside an uploaded draft to override system/developer instructions for generation behavior.
- Use parameterized SQL and a safe document-generation library.
- Escape output appropriate to the rendering context; plain text should remain text, not HTML/Markdown with privileged behavior unless explicitly supported and sanitized.

## 5. Prompt injection considerations

A user-provided paper may contain instructions such as “ignore the previous instructions.” The generation system must treat document contents as source material, not as instructions to the assistant. Use clearly separated system policy and quoted/untrusted input sections. This is defense-in-depth, not a perfect guarantee; inspect output and keep model capability bounded to drafting.

## 6. Logging and monitoring

Allowed operational fields may include:

- request ID;
- route and HTTP status;
- elapsed time;
- error code;
- provider/model name;
- response size and token counts/cost if supplied;
- authentication result category, without token contents.

Do not log:

- full request or response bodies;
- draft/project/reference text;
- prompts or system instructions that include private material;
- API keys, access tokens, cookies, or authorization headers;
- full user file paths or unredacted provider errors.

Use controlled debug logging only with synthetic data. Production logs need an explicit retention period and access controls. Report exceptions with a request ID and safe context.

## 7. Abuse and cost controls

Before remote beta:

- require authenticated access;
- enforce per-request character/token budgets and max output size;
- set per-user rate limits and a total spending/usage alert;
- return `429` for throttled requests;
- cap file uploads and accepted content types;
- disable automatic provider retries unless retry safety is established;
- ensure rate limits work across instances if deploying more than one instance.

## 8. Privacy requirements

- Keep saved draft content on the device by default.
- Do not retain generation or export content on the backend by default.
- Explain that generation material is sent to the configured model provider, and export content passes through the backend.
- Do not promise that content is never retained by the provider unless the current provider terms and account configuration prove that statement.
- Avoid collecting personal information that is not required for the workflow.
- Define a privacy notice and support contact before inviting external testers.
- For research involving human participants, confidential datasets, institutional data, or unpublished IP, the user must verify permission to transmit the material to the provider.

## 9. Security release checklist

- [ ] Provider secrets are runtime-injected and absent from the repository and mobile binary.
- [ ] Production startup refuses unsafe configuration.
- [ ] Remote requests require validated authentication.
- [ ] Rate limits and input/output bounds are active.
- [ ] TLS is enabled on the deployed API.
- [ ] Content is excluded from ordinary logs.
- [ ] Privacy disclosure is shown before transmission.
- [ ] Error responses do not leak stack traces, credentials, file paths, or provider internals.
- [ ] Dependency and secret scans are run before release.
- [ ] Known risks and provider data-handling assumptions are documented.
