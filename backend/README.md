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

The package uses a `src/` layout. The first milestone provides only the FastAPI application entry point; routes and product behavior are introduced in subsequent prompts.
