# 09 — Milestones and Learning Plan

This plan is deliberately outcome-driven rather than calendar-driven. Do not move to the next milestone just because the current code appears to run; meet the exit criteria first.

## Milestone 0 — Understand and freeze the contract

**Build:** product specification, acceptance criteria, JSON Schemas, API contract, repository skeleton, minimal decision records.

**Learn:** requirements engineering; functional vs non-functional requirements; schema-first development; API versioning; scope control.

**Tasks:**
- Read docs 00–04 and explain them in your own words.
- Validate the JSON Schema files with a standards-compliant validator.
- Define the package layout and test commands.
- Create a traceability table from FR IDs to test names or manual QA cases.

**Exit criteria:** request, response, paper object, error object, and P0 requirements are unambiguous enough to implement without guessing.

## Milestone 1 — Backend skeleton and deterministic fake provider

**Build:** FastAPI app, settings, liveness/readiness, request/response models, error handler, fake provider, initial tests.

**Learn:** ASGI, dependency injection, Pydantic validation, HTTP status codes, `pytest`, application configuration, test doubles.

**Exit criteria:** app starts from a clean checkout; invalid requests are rejected; happy/error responses match the contract; no real API key is needed to run tests.

## Milestone 2 — Generation use case and real provider adapter

**Build:** normalized `ResearchBrief`, prompt builder, provider interface, real provider implementation, output parsing, schema validation, integrity checks, generation metadata.

**Learn:** external-service boundaries, timeouts, structured outputs, error taxonomy, prompt injection, token/cost budgets, AI evaluation.

**Exit criteria:** fake-provider suite passes; a gated real-provider smoke test produces a valid paper on synthetic input; malformed output and provider errors are safely handled; quality cases are scored and documented.

## Milestone 3 — Local persistence and document handling

**Build:** project repository, SQLite schema/migrations, version history, `.txt`/`.docx` text extraction, preview, DOCX exporter.

**Learn:** relational data modeling, transactions, schema migrations, file parsing, temporary-file safety, document formatting, versioning.

**Exit criteria:** projects survive restart; generation/export failure preserves prior versions; imports fail safely; exported files open and contain expected sections.

## Milestone 4 — Flutter user journey

**Build:** project list, input form, import workflow, generation state, section review/editor, warnings, local persistence, export UI.

**Learn:** state management, repository pattern, asynchronous UI states, platform file pickers, typed client models, widget testing, accessibility.

**Exit criteria:** a user can complete the core journey without developer intervention; network and provider failure states are usable; local saved drafts remain accessible offline.

## Milestone 5 — Release hardening

**Build:** deployment config, managed authentication, rate limits, cost limits, redacted logs, dependency/security scans, privacy notice, CI, release checklist.

**Learn:** threat modeling, least privilege, operational configuration, deployment health checks, observability, CI, release management.

**Exit criteria:** deployment cannot start in an unsafe mode; remote access requires validated identity; limits and disclosures are active; test and evaluation evidence is available.

## Milestone 6 — Academic demonstration and retrospective

**Build:** reproducible demonstration, evaluation report, architecture diagram, known-limitations list, test evidence, next-steps proposal.

**Learn:** technical communication, evidence-based evaluation, honest reporting of AI limitations, trade-off analysis.

**Exit criteria:** the demo can be repeated from a clean environment; results include negative cases and failure handling; claims in the report match evidence.

## What not to do early

- Do not start by polishing animations or branding.
- Do not add a vector database, RAG, agents, multiple model providers, or a job queue without a requirement.
- Do not build your own password authentication system.
- Do not use a real LLM in every unit test.
- Do not tune prompts around a single impressive input.
- Do not call an endpoint production-ready before authentication, cost controls, logs, and failure behavior have been reviewed.

## Learning rule

For each milestone, write a short implementation note: what you built, which boundary owns each responsibility, what failed, what tests prove it works, and what you would change at larger scale. That note is part of learning to design systems rather than merely assembling libraries.
