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

The package uses a `src/` layout. Copy the root `.env.example` to `backend/.env` for local development; it explicitly selects the deterministic fake generation provider. Its outputs are labeled as demo output. Production settings reject fake mode and default to a disabled provider until a real adapter is configured. The backend handles generation per request and does not persist research content.
