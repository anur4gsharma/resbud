# Prompt 22 — Academic Demonstration, Evidence, and Viva Preparation

```text
Prepare the Resbud project for a credible academic demonstration and viva. Do not fabricate results, test outcomes, performance claims, or user-study findings.

Review the actual working implementation, commits, test reports, evaluation fixtures, and product spec. Create `docs/academic-demo/` containing:
- A concise problem statement, intended users, objective, scope, and explicit non-goals.
- Architecture diagram (Mermaid or text-based), key data flows, trust boundaries, and rationale for Flutter, FastAPI, local-first storage, provider adapter, structured output, and DOCX generation.
- A five-to-eight-minute demo script using a synthetic research example with realistic provided inputs and deliberately missing results. Demonstrate warning behavior and human review, not just a “perfect” output.
- A repeatable test/evaluation protocol, fixture descriptions, exact command lines, and a results table populated only with results actually observed. Clearly label unrun evaluations.
- A limitations/threats-to-validity section: generated content can still be wrong; schema validity is not scientific validity; no automatic source verification; model/provider variability; privacy and platform constraints.
- A list of evidence to capture: app screenshots, a successful export opened in a DOCX reader, test output, schema validation, failure-path demonstrations, and git commit history.
- At least 15 likely viva questions with accurate answers about architecture, validation, hallucination risk, provider abstraction, state preservation, testing, security, storage trade-offs, cost control, and future work.

Do not claim the application is production-ready, scientifically verified, plagiarism-free, or better than alternatives unless there is valid evidence. Separate implemented behavior, measured outcomes, and future proposals. Run or cite only tests that actually exist in the repository; do not invent benchmark numbers or usability-study findings.
```
