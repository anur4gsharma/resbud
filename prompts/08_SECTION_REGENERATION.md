# Prompt 08 — Safe Section Regeneration

```text
Implement selected-section regeneration from the reconciled section-regeneration contract. Inspect the exact request and response schema before coding; if the contract is incomplete, fix docs/OpenAPI/schema first and test the contract.

Requirements:
- Request identifies the current paper, the current research brief/context required for factual grounding, and exactly one target section ID plus user instructions/preferences supported by the contract.
- Validate that the target section exists and that IDs/context are within limits.
- Generate replacement content using the same research-integrity policy as full generation.
- Return a preview/replacement and associated warnings. Do not mutate server-side state or save anything on the user's behalf.
- Preserve original references and paper-level metadata unless the contract explicitly permits changing them.
- Non-target sections must remain byte-for-byte unchanged in the assembled client result unless the user explicitly accepts a whole-paper change. The safest default is a response containing the replacement section and warnings, not a rewritten full paper.
- Handle malformed provider output, missing section, empty replacement, provider timeout, and unsupported section state.
- Make the UI's eventual accept/reject decision explicit; never silently replace user edits.

Test successful target regeneration, missing target, invalid request, unchanged non-target sections at service level, preservation of references/title/metadata, warning behavior, and provider failure. Add a regression test proving a regeneration cannot overwrite another section.
```
