# Resbud

**Research Paper Draft Maker** — repository documentation and implementation contracts.

Resbud helps students and early-stage researchers turn a rough draft and supplied project information into a structured, editable research paper draft. It improves organization and academic clarity without pretending to conduct research, verify findings, or certify a paper as correct.

> **Project rule:** the source material is authoritative. Missing evidence must be surfaced, not invented.

## Status

Pre-implementation specification. These documents define the intended MVP; they are not a claim that the features have already been implemented. Update decisions when evidence from implementation or testing requires a change.

## MVP at a glance

- Cross-platform mobile client: Flutter and Dart.
- Backend: Python and FastAPI.
- AI integration: one server-side model provider behind a provider adapter.
- Local persistence: SQLite on the device; the API does not retain research content by default.
- Inputs: structured project details, pasted draft text, `.txt` and `.docx` source files, and user-supplied references.
- Outputs: editable structured paper, visible missing-information warnings, and a formatted `.docx` export.
- Release boundary: local development first; authenticated, rate-limited access is required before remote beta distribution.

## Read the docs in this order

1. [`docs/00-product-spec.md`](docs/00-product-spec.md) — product, audience, scope, and principles.
2. [`docs/01-requirements-and-acceptance.md`](docs/01-requirements-and-acceptance.md) — requirements and testable acceptance criteria.
3. [`docs/02-architecture.md`](docs/02-architecture.md) — components, boundaries, data flows, and repository layout.
4. [`docs/03-api-contract.md`](docs/03-api-contract.md) — HTTP behavior, validation, errors, and endpoint contracts.
5. [`docs/04-paper-schema.md`](docs/04-paper-schema.md) — structured paper and generation behavior.
6. [`docs/05-data-model-and-storage.md`](docs/05-data-model-and-storage.md) — local data, versioning, migrations, and retention.
7. [`docs/06-security-privacy.md`](docs/06-security-privacy.md) — trust boundaries, API keys, data handling, and release gates.
8. [`docs/07-testing-and-evaluation.md`](docs/07-testing-and-evaluation.md) — test strategy and repeatable AI-quality evaluation.
9. [`docs/08-development-workflow.md`](docs/08-development-workflow.md) — coding standards, local setup, Git, and definition of done.
10. [`docs/09-milestones-and-learning-plan.md`](docs/09-milestones-and-learning-plan.md) — build order and concepts to learn at each stage.
11. [`docs/10-demo-and-academic-evaluation.md`](docs/10-demo-and-academic-evaluation.md) — demo plan, evidence, limitations, and viva preparation.
12. [`docs/adr/`](docs/adr/) — architectural decisions and their trade-offs.
13. [`contracts/`](contracts/) — machine-readable JSON Schemas and OpenAPI contract.

## Non-negotiable engineering principles

1. Validate at boundaries. Treat API input, imported documents, and model output as untrusted.
2. Separate domain logic from framework code, UI code, and provider-specific code.
3. Keep provider secrets on the server. Never put a shared secret in a mobile bundle.
4. Preserve the original source and prior saved drafts when generation or export fails.
5. Test behavior and failure paths; do not test only whether a route returns `200`.
6. Make AI quality measurable with a fixed evaluation set; do not rely on one impressive demo.
7. Keep the MVP narrow. Add infrastructure only when a requirement or measured bottleneck justifies it.
8. Be honest about limitations in the UI, demo, and academic report.

## Initial repository shape

```text
resbud/
├── README.md
├── docs/
│   ├── 00-product-spec.md
│   ├── 01-requirements-and-acceptance.md
│   ├── 02-architecture.md
│   ├── 03-api-contract.md
│   ├── 04-paper-schema.md
│   ├── 05-data-model-and-storage.md
│   ├── 06-security-privacy.md
│   ├── 07-testing-and-evaluation.md
│   ├── 08-development-workflow.md
│   ├── 09-milestones-and-learning-plan.md
│   ├── 10-demo-and-academic-evaluation.md
│   └── adr/
├── contracts/
│   ├── openapi.yaml
│   ├── generation-request.schema.json
│   └── paper-draft.schema.json
├── backend/
│   ├── pyproject.toml
│   ├── src/resbud_api/
│   │   ├── main.py
│   │   ├── api/
│   │   ├── core/
│   │   ├── domain/
│   │   ├── services/
│   │   ├── providers/
│   │   ├── export/
│   │   └── observability/
│   └── tests/
└── mobile/
    ├── pubspec.yaml
    ├── lib/
    │   ├── app/
    │   ├── features/
    │   ├── data/
    │   └── shared/
    └── test/
```

This is a target structure, not a mandate to create empty folders in advance. Add modules when they have a clear responsibility.

## First implementation goal

Build and test the backend contract first, using a deterministic fake provider. Then integrate a real provider behind the same interface. Only after the API contract and failure behavior are stable should the mobile client depend on it.
