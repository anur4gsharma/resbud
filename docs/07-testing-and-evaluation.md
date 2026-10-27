# 07 — Testing and AI Quality Evaluation

Testing must establish two different things: whether the software behaves correctly, and whether the generated paper is useful and faithful to the supplied research. One does not prove the other.

## 1. Test pyramid

### Unit tests

Test deterministic logic without network access:

- request validation and size limits;
- mapping project fields to a normalized research brief;
- prompt construction with untrusted input separated from policy;
- response parsing and schema validation;
- warning-code generation;
- reference-ID and section-ID checks;
- provider-error mapping;
- DOCX formatting helpers and filename sanitization;
- SQLite repository, version ordering, and migrations.

### Integration tests

Use a fake provider to exercise FastAPI routes and services:

- valid generation;
- invalid/oversized input;
- timeout, provider 429, 5xx, malformed output;
- export response MIME type and bytes;
- authentication and rate limiting in deployment-mode tests;
- confirm content is absent from captured logs;
- confirm failure never writes over a saved draft.

### End-to-end tests

Use the mobile app against a local/test API and verify create → input → generate → review → edit → save → reopen → export. Add failure scenarios: network disappears during generation, malformed import, and provider failure.

### Manual QA

Check keyboard behavior, text editing, long content, small-screen layout, file-picker behavior, loading/error messaging, accessibility labels, and exported DOCX readability.

## 2. Fake provider design

The fake provider should return fixtures selected by test case, not imitate probabilistic language generation. It should also be able to simulate a delay, timeout, rate-limit error, server error, and invalid JSON. This makes route and error behavior reproducible without using tokens or a real API key.

Real provider tests should be opt-in, use synthetic/non-confidential material, have a cost limit, and never be required for ordinary CI.

## 3. AI evaluation set

Check a small, versioned set of synthetic or public-domain cases into the repository. Do not put confidential or unpublished student research into permanent fixtures without permission.

Recommended cases:

1. **Complete input:** source draft, method, results, and supplied references exist.
2. **No results collected:** user explicitly states that experiments have not been conducted.
3. **Results omitted:** result information is unknown rather than explicitly absent.
4. **No references:** paper needs citation-needed placeholders rather than invented citations.
5. **Conflicting evidence:** project fields disagree with the draft on a numeric value.
6. **Prompt injection in source:** document text attempts to override the drafting policy.
7. **Large input:** at/near configured boundaries and above the limit.
8. **Malformed model response:** missing keys, wrong types, empty content, or duplicate section IDs.
9. **Specialist vocabulary:** technical terms should not be flattened into generic prose.
10. **Section regeneration:** one section changes while the other sections remain unchanged.

Version each fixture and the scoring rubric. Store a run manifest containing date, model/provider identifier, relevant model settings, schema version, prompt version, and evaluator notes. Never include secrets.

## 4. Human review rubric

Score each category from 0 to 4:

- **0:** unacceptable / absent;
- **1:** major problems;
- **2:** mixed, requires substantial edits;
- **3:** good, minor edits required;
- **4:** strong for a first draft, no major issue found in this category.

| Category | What the evaluator checks |
|---|---|
| Faithfulness | Technical claims and meaning match supplied evidence |
| Non-fabrication | No invented result values, methods, people, datasets, or references |
| Structure | Sections are appropriate, ordered, and non-duplicative |
| Clarity | Writing is coherent, precise, and grammatically sound |
| Academic restraint | Limitations and uncertainty are not erased or overstated |
| Reference handling | Supplied references are retained; missing sources are flagged honestly |
| Editability | Content is sectioned and practical to revise/export |

**Hard failure:** any invented experimental result, fabricated reference, or material change to a critical technical claim makes the case fail regardless of its average score.

The score is a project evaluation measure, not a validated scientific benchmark. Explain evaluator count and limitations in the report.

## 5. Regression policy

- Add a new test whenever a bug is fixed.
- Keep a fixed evaluation set and compare new prompt/model configurations against it.
- Review regressions before changing the default provider model or prompt.
- Do not judge a model change from one hand-picked sample.
- Preserve negative examples so the team can verify that known failures remain fixed.

## 6. Suggested automation and quality gates

Backend CI should run:

1. formatting/lint checks;
2. type checks where configured;
3. unit and integration tests;
4. schema validation tests;
5. dependency/secret checks;
6. OpenAPI/contract consistency checks where feasible.

Mobile CI should run formatting, static analysis, unit/widget tests, and a build for the intended development target. Cross-platform platform builds must be explicitly tested; passing Dart tests alone does not prove that a platform package builds.

## 7. Metrics worth recording

- successful generation rate;
- failure rate by stable error code;
- end-to-end generation latency (median and p95, once sample size is meaningful);
- average input/output size and provider token usage/cost where available;
- proportion of evaluation cases passing the hard fabrication gate;
- category scores and reviewer notes;
- DOCX export success rate.

Do not report a precise p95 or success percentage from a tiny sample without giving the sample count and caveat.
