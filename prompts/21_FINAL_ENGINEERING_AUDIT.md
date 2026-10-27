# Prompt 21 — Final Engineering and Product Audit

**Run after the core implementation and before calling the MVP complete.**

```text
Act as an independent senior engineer reviewing the Resbud repository. Do not implement new features immediately. Audit for correctness, contract consistency, security, data loss, test quality, and whether the product meets its P0 acceptance criteria.

Inspect the repository and diff; read specs/contracts; run available checks. Look specifically for:
- TODOs or placeholders in P0 paths, fake provider accidentally enabled in release mode, swallowed exceptions, unchecked casts, blocking work on UI thread, unbounded input/output, unsafe file paths, resource leaks, uncaught async errors, duplicate submissions, stale export data, broken migrations, and silent data overwrites.
- Provider keys/secrets in tracked files or app assets; content in logs; debug endpoints/settings enabled remotely.
- Schema mismatch between Pydantic/domain types, JSON Schema, OpenAPI, and Flutter serialization.
- Route handlers doing provider/business/export logic; unnecessary dependency complexity; dead code and unused packages.
- Tests that only assert status 200, overly broad mocks, brittle timing, skipped assertions, untested error paths, and flaky network dependencies.
- Incorrect claims about citation verification, scientific correctness, privacy, or platform support.
- README instructions that fail on clean setup and broken document links.

Output a prioritized findings report with severity (Blocker/High/Medium/Low), evidence path/line, impact, and a concrete fix. Fix Blocker and High findings within the current scope, add regression tests, then rerun checks. Do not make broad refactors unrelated to a finding. If a security/product decision cannot be safely implemented without owner input, clearly block release and explain why.

Finish with a P0 acceptance matrix: requirement, implementation path, automated test/manual evidence, result, limitation. State exact commands run and which results are verified. Never describe unrun tests as passed or mark a requirement complete without evidence.
```
