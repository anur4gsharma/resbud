# Resbud API

From this directory, install the locked dependencies and run the local checks:

```bash
uv sync --locked --dev
uv run uvicorn resbud_api.main:app --reload
uv run ruff format --check src tests
uv run ruff check src tests
uv run mypy src
uv run pytest
```

The package uses a `src/` layout. Copy the root `.env.example` to `backend/.env` for local development; it explicitly selects the deterministic fake provider. For OpenAI or Gemini, set `RESBUD_GENERATION_PROVIDER=openai` or `gemini`, configure `RESBUD_PROVIDER_MODEL` (e.g. `gemini-2.5-flash`), and supply `RESBUD_PROVIDER_API_KEY` through server environment/secret configuration. See [`../docs/07-openai-provider.md`](../docs/07-openai-provider.md) for a loopback smoke test. The backend handles generation per request and does not persist research content.
