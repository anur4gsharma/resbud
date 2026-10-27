# Prompt 07 — Real LLM Provider Adapter

```text
Add one real LLM provider to Resbud behind the provider interface already established. First inspect the provider abstraction and current dependencies; select the provider already configured by the project if one exists. Do not add multi-provider routing or expose provider selection to users.

Requirements:
- Credentials come only from server environment/secret configuration. Never add real keys to code, `.env.example`, tests, client config, docs, or logs.
- Set explicit connection/read timeouts and a bounded output-token/response budget supported by the chosen SDK/API.
- Request schema-constrained/structured output when the provider supports it, but still validate output locally.
- Normalize provider response, usage/token metadata, request IDs where available, and errors into provider-neutral types.
- Map authentication/configuration errors, rate limits, timeouts, network errors, and invalid response structures into stable application errors without leaking raw SDK exceptions.
- No blind automatic retry after uncertain failures. If a retry is supported, it must be bounded, justified, and documented; no silent repeat of a potentially billable generation call.
- Do not log prompt or draft contents. Do not store request/response bodies.
- Fake provider must remain usable in tests without network access or credentials.

Add adapter unit tests using mocked SDK responses; do not rely on live API keys in CI. Add one optional manual smoke-test procedure for a configured developer key, without recording the key. Check model selection and model availability from configuration rather than hardcoding it in multiple modules.

Update `.env.example`, README setup, cost/limit documentation, and provider-specific notes. Run the full backend test suite. Clearly distinguish mocked tests from any live-provider test actually performed.
```
