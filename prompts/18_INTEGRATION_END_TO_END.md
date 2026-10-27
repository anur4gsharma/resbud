# Prompt 18 — End-to-End Integration and Regression

```text
Integrate the complete Resbud vertical workflow and close contract mismatches. Do not add new product features. Inspect the actual app and tests; identify where the user journey is incomplete.

Verify this path:
1. Create a local project.
2. Enter structured research details and source draft, or import supported text/document content.
3. Review missing information before generation.
4. Submit to backend using fake provider and receive validated structured output/warnings.
5. Inspect the paper, edit a section, and persist the edit.
6. Request a selected-section replacement, preview it, reject it, then accept a separate replacement and prove unrelated sections survive.
7. Close/reopen the project and verify saved content/version history.
8. Export the current paper to DOCX and open/parse it to verify expected content.
9. Simulate malformed provider output, timeout, network failure, and export failure; verify no saved content is lost.

Requirements:
- Add automated integration tests across API/service/repository boundaries where feasible.
- Add Flutter integration/widget tests for critical visible state transitions. Use injected fake services; do not require a live LLM API in normal CI.
- Add a repeatable manual smoke-test guide for the Android app and local backend.
- Verify schema/OpenAPI consistency and all README links.
- Check no P0 requirement is marked done without an automated test, manual QA step, or demonstrable evidence.
- Keep tests deterministic and clean up temp files/databases.

Run all available backend and mobile checks. Provide a requirement-to-test/evidence matrix. List every untested path and environment limitation. Do not claim full end-to-end success if the app has not actually been run on a device/emulator.
```
