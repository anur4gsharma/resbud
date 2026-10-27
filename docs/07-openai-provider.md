# OpenAI Provider Adapter

Resbud has one real provider adapter: OpenAI's Responses API. Provider selection and model choice are server configuration; the client cannot select a vendor or model.

## Configuration

Use a model enabled for the OpenAI project that owns the API key and supports Structured Outputs. Resbud does not hardcode a model ID or check account availability at startup.

Set these server-side environment values:

| Setting | Purpose | Default |
|---|---|---:|
| `RESBUD_GENERATION_PROVIDER` | Select `openai` for the real adapter | `disabled` unless configured |
| `RESBUD_PROVIDER_MODEL` | Model ID enabled for the OpenAI project | Required for OpenAI mode |
| `RESBUD_PROVIDER_API_KEY` | Secret API credential | Required for OpenAI mode |
| `RESBUD_PROVIDER_MAX_OUTPUT_TOKENS` | Maximum response output tokens | `12000` |
| `RESBUD_PROVIDER_CONNECT_TIMEOUT_SECONDS` | Connection, write, and pool timeout | `5` |
| `RESBUD_PROVIDER_READ_TIMEOUT_SECONDS` | Response read timeout | `90` |

The SDK retry count is zero. A timeout can happen after the provider has received the request, so Resbud does not retry automatically. A later user retry may make another billable call.

The adapter uses Structured Outputs with the `PaperDraft` Pydantic schema, sets `store=false` for the Responses API, and validates the parsed object again in Resbud. Provider request IDs and token usage are normalized into provider-neutral result metadata. Credentials, prompts, drafts, response bodies, and raw SDK exceptions are not logged. `store=false` controls API response-object storage; it is not a promise about all provider-side processing or retention. Review current provider terms and project settings before sending sensitive research material. See [OpenAI Docs: Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs) and the [Responses API reference](https://developers.openai.com/api/reference/resources/responses/methods/create).

## Error mapping

- API timeout → `504 PROVIDER_TIMEOUT`.
- API authentication/permission, network, or provider server error → `503 PROVIDER_UNAVAILABLE`.
- Provider rate limit → `429 RATE_LIMITED`.
- Incomplete/refused output, invalid provider request, or unparseable structured result → `502 PROVIDER_INVALID_RESPONSE`.

Error responses contain only Resbud's stable public error text and the Resbud request ID. Provider exception messages and provider request IDs are not returned to the mobile client.

## Optional local smoke test

This procedure sends the synthetic request fixture to the configured OpenAI project. It requires a developer-managed key and may incur API cost. No live call is made in CI.

1. Copy the root `.env.example` to `backend/.env` and set `RESBUD_GENERATION_PROVIDER=openai`, `RESBUD_PROVIDER_MODEL` to a model enabled for the project, and `RESBUD_PROVIDER_API_KEY` through a trusted local secret manager. Do not paste the key into a command, fixture, or committed file.
2. Start the API from `backend/` on loopback: `uv run uvicorn resbud_api.main:app --host 127.0.0.1 --port 8000`.
3. In another terminal at `backend/`, submit only the synthetic fixture: `curl -sS -X POST http://127.0.0.1:8000/api/v1/generations -H 'Content-Type: application/json' --data-binary @tests/fixtures/generation-request.valid.json`.
4. Confirm HTTP 200, `meta.provider_name` is `openai`, `meta.model_name` matches the configured model, references match the fixture, and review warnings are present. Stop the server after the check.

No live-provider smoke test has been performed for this implementation. CI and the tests below use mocked SDK responses only.
