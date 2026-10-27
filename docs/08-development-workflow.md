# 08 — Development Workflow and Engineering Standards

## 1. Work in small vertical slices

Implement one behavior end-to-end, verify it, then expand. Prefer a small tested API feature over a large batch of unintegrated modules.

## 2. Suggested local development setup

### Backend

Use Python 3.12–3.14 and `uv` for reproducible dependency management. Flutter support starts at stable 3.41 with Dart 3.11; update these baselines only after running the checks on the new toolchain.

Typical setup once `pyproject.toml` exists:

```bash
cd backend
uv sync --locked --dev
uv run ruff format --check src tests
uv run ruff check src tests
uv run mypy src
uv run pytest
uv run uvicorn resbud_api.main:app --reload
```

If using a `src/` layout, configure the package installation correctly so tests import the same package shape as the application. Avoid working around import errors with ad hoc `sys.path` changes; fix package configuration and run tests from the documented project root.

Add configured tools such as Ruff and a type checker to the development dependency group. Lock dependencies and commit the lockfile.

### Mobile

Install Flutter stable 3.41 or newer (Dart 3.11 or newer) and verify it with:

```bash
flutter doctor
cd mobile
flutter pub get
flutter analyze
flutter test
```

Record the Flutter/Dart version and target platform tested in the README or CI. Android can be developed on Linux; iOS build/signing requires macOS with Xcode.

## 3. Configuration

- Parse environment configuration through one settings module.
- Validate required settings at startup rather than failing midway through a request.
- Commit `.env.example`, never `.env`.
- Use separate dev/test/prod settings.
- Default to safe limits and fail closed in production-like environments.
- Tests should inject configuration and fake providers, not require a developer's personal credentials.

## 4. Code organization and dependencies

- Keep route handlers thin; use-case services contain workflow logic.
- Domain models should not depend on FastAPI, provider SDKs, SQLite, or Flutter types.
- Keep provider-specific API calls inside a provider adapter.
- Avoid a generic abstraction until there are at least two real use cases or a clear testability benefit.
- Avoid catch-all exceptions that hide bugs. Catch known failure classes at boundaries, log a safe request ID, and return stable errors.
- Add comments to explain non-obvious decisions, not to restate each line.

## 5. Git workflow

Use small branches or focused commits. Each meaningful change should answer:

- What requirement/bug does this change address?
- What was changed and why?
- Which tests were run?
- What risks or behavior changes remain?

Commit docs and schema changes alongside the implementation they define. Avoid giant commits containing unrelated refactors, UI changes, and provider integration.

Suggested commit style:

```text
feat(api): define generation request contract
 test(api): cover provider timeout mapping
 docs(security): clarify remote release gate
 fix(storage): preserve last version on save failure
```

The exact conventional-commit format is optional; consistency and traceability are not.

## 6. Definition of done

A change is done when:

- its behavior matches a requirement or a documented design decision;
- input and error behavior are defined;
- tests cover the happy path and relevant failure paths;
- lint/type/test checks pass;
- logs and errors do not expose private content or secrets;
- documentation/contracts are updated if behavior changed;
- the feature has been exercised in the actual integration path;
- known limitations are recorded honestly.

“Code compiles” is necessary but not sufficient.

## 7. Debugging procedure

1. Reproduce the problem with the smallest input/case.
2. Read the full traceback or structured error; identify the first relevant application frame.
3. Determine which boundary failed: client, transport, validation, domain logic, provider, storage, or export.
4. Add a minimal regression test before making a broad fix when practical.
5. Fix the cause at the correct layer rather than adding an unrelated workaround.
6. Re-run the focused test, the relevant test suite, and the end-to-end path.
7. Record the cause and any new guardrail if the bug exposed a design gap.

## 8. Engineering habits to practice

- Type annotations and explicit data contracts.
- Dependency injection for provider clients and repositories.
- Structured errors rather than string matching.
- Timeouts on external calls.
- Transaction boundaries for local version updates.
- Safe configuration and secret rotation.
- Schema evolution and migrations.
- Test doubles and deterministic test fixtures.
- Observable behavior without logging sensitive payloads.
- Architecture decisions recorded with consequences and alternatives.
