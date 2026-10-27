# Resbud Academic Demonstration and Viva Preparation Package

This directory contains the complete academic documentation, demonstration protocol, and examination defense materials for **Resbud — Research Paper Draft Maker**.

---

## Document Index

| Document | Content Summary |
|---|---|
| [**01 — Problem Statement & Scope**](01-problem-statement-and-scope.md) | Problem definition, user personas, core objectives, and explicit out-of-scope non-goals. |
| [**02 — Architecture & Data Flow**](02-architecture-and-data-flow.md) | Mermaid architecture diagram, key data flows, trust boundaries, and technology rationale (Flutter, FastAPI, SQLite, Provider Adapter). |
| [**03 — Academic Demo Script**](03-demo-script.md) | Six-to-seven minute step-by-step demonstration script using a synthetic research scenario with deliberately missing results. |
| [**04 — Evaluation Protocol & Results**](04-evaluation-protocol-and-results.md) | Automated test suite metrics (216 tests passing), 7 deterministic evaluation profiles, exact commands, and unrun evaluation labeling. |
| [**05 — Limitations & Threats to Validity**](05-limitations-and-threats-to-validity.md) | Discussion of scientific boundaries: why schema validity ≠ scientific validity, lack of automated truth checks, and platform constraints. |
| [**06 — Academic Evidence Checklist**](06-evidence-checklist.md) | Inventory of demonstrable artifacts, required UI screenshots, failure-path demonstrations, and git commit history. |
| [**07 — Viva Voce Preparation Guide**](07-viva-qa-guide.md) | In-depth answers to the 15 most critical examination questions on architecture, security, state preservation, and hallucination risk. |

---

## Core Academic Principles

1. **Honest Claims**: Resbud does not claim "zero hallucinations" or "plagiarism detection". It proves structural adherence to `PaperDraft` schema version 1, explicit negative-fact encoding, and non-retention of student intellectual property.
2. **Deterministic Evidence**: All 216 automated tests (105 backend pytest, 111 mobile flutter tests) execute 100% offline without requiring paid tokens or network access.
3. **Traceability**: Every functional requirement (`FR-001` through `FR-016`) is mapped to automated test assertions and manual QA procedures in the [Requirement Traceability Matrix](../12-requirement-traceability-matrix.md).
