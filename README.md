# Resbud — Research Paper Draft Maker

Resbud turns user-provided research material into an editable paper draft while keeping projects and versions on the device by default. This repository is being implemented in small milestones; only the bootstrap foundation is in place so far.

## Start here

Read the product requirements, architecture, API, paper schema, local storage spec, and audit report in `docs/`. Implement and review one milestone at a time.

## Contents

- `docs/`: intended product behavior, requirements, architecture, API behavior, research-integrity rules, security/privacy, testing, and academic evaluation.
- `docs/smoke-test-guide.md`: repeatable manual smoke test guide for mobile client and local backend.
- `docs/12-requirement-traceability-matrix.md`: requirement-to-test and evidence matrix for all P0 requirements.
- `docs/operations-and-incident-guide.md`: operations runbook, container deployment, release packaging, and incident checklists.
- `docs/adr/`: decisions made while reconciling the specification; unresolved deployment choices are recorded in the audit report.
- `contracts/`: request/paper JSON Schemas and OpenAPI YAML.
- `SPEC_README_ORIGINAL.md`: original specification package README preserved as supplied; reconciled paths are documented in the audit report.

## Engineering rule

Inspect the actual repository, resolve contract conflicts explicitly, write tests, run them, and report only verified outcomes. Keep provider keys server-side. Do not allow generated research claims or citations to bypass schema checks and human review.

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

The backend exposes health endpoints and a deterministic generation demo through an importable FastAPI application. To change Python dependencies, edit `backend/pyproject.toml`, run `uv lock`, then validate with `uv sync --locked --dev`.

The backend requires `RESBUD_ENV` explicitly; `.env.example` sets local development and explicitly selects the deterministic fake generation provider. Keep `.env` in `backend/` and out of version control. To use the OpenAI adapter, configure `RESBUD_GENERATION_PROVIDER=openai`, a model available to your OpenAI project via `RESBUD_PROVIDER_MODEL`, and the server-side `RESBUD_PROVIDER_API_KEY`. The output is capped at 12,000 tokens by default, with configurable connection/read timeouts; see [OpenAI provider setup](docs/07-openai-provider.md). Production rejects fake mode and is not ready until provider and auth configuration is present. Authentication enforcement remains a release gate.

## Mobile setup

Requires Flutter stable 3.41 or newer (Dart 3.11 or newer). The Linux Android build target is intended for development; iOS builds require macOS and Xcode. From the repository root:

```bash
cd mobile
flutter pub get
flutter analyze
flutter test
```

Run `flutter analyze` and `flutter test` to execute the full automated mobile test suite. See the [Manual Smoke Test Guide](docs/smoke-test-guide.md) for step-by-step instructions on running the Android app against a local backend.

## Continuous integration

GitHub Actions runs the backend lint, type, and test checks plus Flutter analysis and tests. CI does not deploy or require provider credentials. All automated checks run offline using deterministic test doubles and fake providers.

## Deployment and operations

To build and run the backend container locally or in staging:

```bash
docker compose build
docker compose up -d
```

See the [Operations, Deployment, and Incident Guide](docs/operations-and-incident-guide.md) for production configuration, fail-closed readiness checks, Android release packaging (`flutter build apk --release`), rollback procedures, and incident response checklists.
