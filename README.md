# Resbud — Research Paper Draft Maker

Resbud turns user-provided research material into an editable paper draft while keeping projects and versions on the device by default. This repository is being implemented in small milestones; only the bootstrap foundation is in place so far.

## Start here

1. Read the product requirements, architecture, API, paper schema, and local storage specs in `docs/`.
2. Start your coding-agent session with `prompts/00_GLOBAL_OPERATING_RULES.md`.
3. Prompt 01 has reconciled the specs and contracts. Continue with one numbered prompt at a time.
4. Review diffs and actual check results before moving to the next prompt.

## Contents

- `docs/`: intended product behavior, requirements, architecture, API behavior, research-integrity rules, security/privacy, testing, and academic evaluation.
- `docs/adr/`: decisions made while reconciling the specification; unresolved deployment choices are recorded in the audit report.
- `contracts/`: request/paper JSON Schemas and OpenAPI YAML.
- `prompts/`: 23 individually runnable coding-agent prompts from repository audit through final review and viva prep.
- `PROMPTS_ALL_IN_ONE.md`: concatenated reference for searching/reading. Do not submit the entire file to an agent as one request.
- `SPEC_README_ORIGINAL.md`: original specification package README preserved as supplied; the audit prompt should reconcile references against actual files.
- `PROMPT_PACK_README.md`: prompt usage guide.

## Engineering rule

The prompts do not replace engineering judgment. The coding agent must inspect the actual repository, resolve contract conflicts explicitly, write tests, run them, and report only verified outcomes. Keep provider keys server-side. Do not allow generated research claims or citations to bypass schema checks and human review.

## Backend setup

Requires Python 3.12–3.14 and `uv` 0.8 or newer. From the repository root:

```bash
cp .env.example backend/.env
cd backend
uv sync --locked --dev
uv run uvicorn resbud_api.main:app --reload
uv run ruff format --check src tests
uv run ruff check src tests
uv run mypy src
uv run pytest
```

The current backend bootstrap exposes an importable FastAPI application; feature routes are added in later milestones. To change Python dependencies, edit `backend/pyproject.toml`, run `uv lock`, then validate with `uv sync --locked --dev`.

The backend requires `RESBUD_ENV` explicitly; `.env.example` sets it to local `development`. Keep `.env` in `backend/` and out of version control. Settings use the `RESBUD_` prefix: `RESBUD_PROVIDER_API_KEY` is a server-side credential; `RESBUD_AUTH_ISSUER` and `RESBUD_AUTH_AUDIENCE` are required for production readiness; `RESBUD_CORS_ALLOWED_ORIGINS` is a JSON array of exact browser origins; `RESBUD_MAX_REQUEST_BODY_BYTES` is capped at 4 MiB. Development and tests are explicitly ready without a provider credential. Production returns not-ready until provider and auth configuration is present. The API currently has no auth enforcement or provider call; those arrive in later prompts.

## Mobile setup

Requires Flutter stable 3.41 or newer (Dart 3.11 or newer). The Linux Android build target is intended for development; iOS builds require macOS and Xcode. From the repository root:

```bash
cd mobile
flutter pub get
flutter analyze
flutter test
```

Flutter was not installed when this scaffold was created, so mobile checks have not yet been run. Install Flutter from the [official instructions](https://docs.flutter.dev/install) before treating the client as verified.

## Continuous integration

GitHub Actions runs the backend lint, type, and test checks plus Flutter analysis and tests. CI does not deploy or require provider credentials.
