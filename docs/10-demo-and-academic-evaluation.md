# 10 — Demo Plan and Academic Evaluation

The project should be evaluated on both implementation quality and the limits of the AI feature. A polished presentation cannot compensate for weak evidence; a technically solid product also needs a clear, repeatable explanation.

## 1. Demonstration story

Use synthetic or non-confidential research material. Do not demonstrate with sensitive unpublished work unless you have explicit permission to transmit it to the selected provider.

Suggested 6–8 minute flow:

1. **Problem (45 sec):** show a messy draft and explain the time/structure problem.
2. **Inputs (60 sec):** enter the research question, objectives, method, results status, and references.
3. **Generation (60–90 sec):** show the progress state and the structured result.
4. **Integrity behavior (60 sec):** use a case with no experimental results; show that Resbud flags the gap rather than inventing measurements.
5. **Editing and persistence (60 sec):** edit a section, save, reopen, and show that the change persists.
6. **Export (45 sec):** export and open the DOCX.
7. **Engineering (60 sec):** show the architecture, API schema, test results, and a simulated provider failure.
8. **Limitations (30 sec):** clearly state what remains unverified and what is outside scope.

Rehearse the flow and keep a pre-generated fallback artifact for unstable network/provider conditions. Do not hide the fallback or present it as live output.

## 2. Evidence to collect

- Requirements-to-tests traceability.
- Backend automated test summary.
- Mobile test/analyze/build results.
- Screenshots of important states: input, loading, result with warnings, error, editor, export.
- Example input and output with sensitive information removed.
- Evaluation table for each fixed AI case and the hard-failure criteria.
- Exported DOCX opened in a standard reader.
- A diagram showing the device, API, and provider trust boundaries.
- A list of known issues and deferred features.

## 3. Suggested report structure

1. Abstract and problem statement.
2. Objectives and scope.
3. Existing workflow/problem analysis.
4. Requirements and acceptance criteria.
5. System architecture and key design decisions.
6. Implementation approach and technology choices.
7. AI generation pipeline and research-integrity constraints.
8. Testing methodology and AI evaluation rubric.
9. Results, observations, and limitations.
10. Security/privacy considerations.
11. Future work.
12. Conclusion and references.

Report only what the implementation and evaluation actually demonstrate. Distinguish design intentions from implemented behavior and measured results.

## 4. Viva questions to prepare for

- Why Flutter and FastAPI instead of one monolithic application?
- Why is the LLM provider accessed through the backend?
- Why keep user projects local in this MVP?
- What prevents malformed model output from reaching the UI?
- How do you distinguish “results not supplied” from “experiments not conducted”?
- What does schema validation prove, and what does it not prove?
- How did you evaluate hallucination/fabrication risk?
- Why is a fake provider used in most tests?
- What happens if the provider times out after processing a request?
- Why is generation not blindly retried?
- How are API secrets and research content protected?
- What changes would be necessary for multi-user cloud history or larger-scale traffic?
- What are the known limitations of `.docx` extraction and formatting?
- Which features were explicitly excluded to control scope?

## 5. Academic integrity and attribution

Follow the institution's requirements for AI-assisted work, attribution, authorship, and source citation. Resbud's generated draft should not be represented as independently verified research. Technical claims and references in the report must be checked by the author. Record the model/provider and evaluation setup where relevant to reproducibility.

## 6. Honest claims checklist

Before presenting or submitting the project, verify:

- Do not claim “zero hallucinations” based on a small test set; say how many cases were evaluated and what was observed.
- Do not claim “secure” without describing implemented controls and their verification.
- Do not claim iOS support unless the app was actually built and tested on the intended iOS target.
- Do not claim production scalability without load tests and evidence.
- Do not claim citations are verified when the system only preserves user-provided references.
- Do not present planned work as implemented features.
