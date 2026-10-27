# 00 — Product Specification

- **Product:** Resbud — Research Paper Draft Maker
- **Status:** Proposed MVP baseline
- **Specification owner:** project team
- **Last updated:** 2026-10-26

## 1. Product vision

Resbud transforms researcher-provided material into a structured, editable research paper draft. Its value is not that it can produce many words; its value is that it helps users organize and improve writing while preserving the distinction between supplied evidence, reasonable wording changes, and information that is still missing.

### Product promise

> Turn an existing research draft and project facts into a coherent paper draft that is easier to review, edit, and export—without inventing the research.

Resbud is a drafting assistant, not a research-discovery engine, citation-verification service, plagiarism checker, or substitute for the author's judgment.

## 2. Initial user and use case

**Primary user:** a college student or early-stage researcher who has a project, rough draft, and some technical details but needs help structuring the paper and improving academic clarity.

**Primary job:** “When I have a rough draft and project facts, help me produce a coherent paper draft that I can verify and edit, rather than forcing me to start with a blank page.”

**Initial context:** individual use on a mobile device; project data remains on the device by default, except material explicitly submitted to the backend for generation or export.

## 3. Problem statement

Users may have research notes, methods, implementation details, measurements, and references in inconsistent formats. Turning them into an organized paper requires both writing effort and careful checking that the paper does not overstate what the project actually demonstrated.

Resbud addresses organization, drafting, and editability. It does not claim to solve the underlying scientific-validity problem automatically.

## 4. Core user journey

1. Create a paper project.
2. Enter a working title, research field, question, objectives, and contribution.
3. Add the existing draft and any available method, dataset, results, limitation, and reference information.
4. Review a pre-generation summary of supplied information and missing critical fields.
5. Request generation and see an explicit loading state.
6. Inspect the generated title, abstract, keywords, and sectioned draft plus review warnings.
7. Edit sections and optionally regenerate a selected section without silently replacing unrelated user edits.
8. Save and reopen the project.
9. Export the current reviewed draft as DOCX.

## 5. MVP scope

### Must have (P0)

- Project creation and editing.
- Structured project information plus existing draft text.
- Import source text from `.txt` and `.docx`.
- Validate required fields and input sizes before making a model request.
- Generate a structured paper draft through one configurable server-side model provider.
- Return clear warnings for missing inputs and content requiring human review.
- Allow section-level editing and selected-section regeneration.
- Save projects and draft versions locally.
- Export the current draft to `.docx`.
- Handle provider failures, malformed output, network errors, and timeouts without losing saved data.
- Automated tests for critical backend, storage, and user-facing behaviors.

### Explicitly deferred (P1/P2)

- Literature search or web research.
- Automated verification that a reference exists or supports a claim.
- Multiple LLM providers exposed to users.
- Cloud sync, collaboration, and account-based project storage.
- LaTeX export and journal-specific submission pipelines.
- Plagiarism detection or AI-detection claims.
- Subscription billing and public self-service onboarding.
- Advanced word-processor functionality such as tracked changes and complex tables.

## 6. Product principles

### Source material is authoritative

The model can reorganize and clarify text. It must not create experimental measurements, sample sizes, statistical values, participants, results, or references that were not provided. Missing information must be surfaced as a warning or explicit placeholder.

### The user remains the author

The app must make it clear that the output is a draft for review. Users are responsible for checking technical claims, references, ethics requirements, and institutional rules.

### Preserve work

A failed generation must not replace the input or the last saved version. Regeneration must be an explicit user action.

### Visible limitations

Warnings should explain what is missing and what the user needs to verify. Avoid vague claims such as “AI verified” or “scientifically accurate.”

### Narrow scope, solid foundations

One mobile client, one API, one provider, one export format. Add complexity only when it directly supports a user requirement or a measured constraint.

## 7. Non-goals

- Writing a paper for a user when no meaningful project material exists.
- Guaranteeing factual correctness or acceptance by a journal, university, or conference.
- Automatically searching for sources and asserting that they are valid.
- Making publication-ethics decisions on behalf of a researcher.
- Retaining research content on the backend by default.

## 8. Product success measures

Measure these on a fixed test set and a small usability trial. They are targets to evaluate, not claims of current performance.

| Measure | Initial target | How to measure |
|---|---|---|
| Core workflow completion | At least 4 of 5 test users complete generation, editing, saving, reopening, and export without developer intervention | Observe a scripted usability test |
| Critical fabrication | Zero unsupported experimental values or invented references in the fixed evaluation set | Human review against the input evidence |
| Structure | Required applicable sections exist and conform to the schema in every accepted response | Automated schema checks |
| Data preservation | 100% of tested generation/export failures preserve the last saved draft | Fault-injection and persistence tests |
| Error clarity | Every expected failure maps to an actionable message and stable error code | API/UI integration tests |
| Reproducibility | Evaluation inputs, model configuration, and scoring rubric are versioned | Repository artifacts and run log |

The 4-of-5 usability target is a small formative test, not statistical proof of broad usability.

## 9. Main risks

- Model output can sound authoritative while being wrong.
- Long inputs increase latency and provider cost.
- DOCX import/export edge cases can consume more effort than the core feature.
- A mobile application cannot safely protect a shared provider secret embedded in its bundle.
- Cross-platform packaging adds work beyond backend development.

Mitigations are defined in the security, testing, and milestone documents.

## 10. Release definition

The MVP is ready for a **private beta** only when all P0 acceptance criteria pass, the core workflow is demonstrated end-to-end, model quality has been evaluated on documented cases, provider credentials are server-side, remote access is authenticated and rate-limited, privacy disclosures are visible, and known limitations are documented.

A successful local demo alone does not meet the private-beta release bar.
