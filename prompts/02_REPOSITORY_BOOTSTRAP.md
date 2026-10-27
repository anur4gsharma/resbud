# Prompt 02 — Repository and Tooling Bootstrap

**Run after Prompt 01 has reconciled the specifications.**

```text
Set up the minimal Resbud repository foundation according to the reconciled architecture docs. Inspect the current project first and preserve all existing files. Do not implement the whole product.

Backend requirements:
- Python project under `backend/`, managed with `uv` if not already established.
- A clear source layout under `backend/src/resbud_api/` and tests under `backend/tests/`.
- Pin or constrain dependencies responsibly; include a lockfile where uv generates one.
- Include development commands for environment setup, running the API, formatting/linting/type checking, and tests.
- Keep configuration out of code and provide a `.env.example` containing only placeholders, never real secrets.
- Add `.gitignore` rules for virtual environments, caches, `.env`, coverage, build output, local DB files, generated documents, and IDE files.

Mobile requirements:
- Create/inspect a Flutter app under `mobile/` only if this task's repository does not already have one.
- Keep code under `lib/app`, `lib/features`, `lib/data`, and `lib/shared` only where those boundaries are useful; don't create empty architecture theatre.
- Define the supported Flutter/Dart versions and run `flutter analyze` plus available tests.

Repository requirements:
- Root README explains exact setup/run/test commands and links to the docs.
- Add formatting/lint configuration only when it is actually used.
- Add a CI workflow for fast deterministic checks if the repository's current platform supports it; do not add deploy credentials or deploy on every push.
- Never add empty placeholder modules without a defined use.

Acceptance: a clean clone can follow the instructions to install dependencies and run baseline checks; backend app imports; mobile app builds/analyzes if Flutter is available; secrets are not tracked. If Flutter or another tool is unavailable in this environment, report that as unverified instead of claiming success.
```
