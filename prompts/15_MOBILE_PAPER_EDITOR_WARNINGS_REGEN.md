# Prompt 15 — Paper Review, Section Editing, Warnings, and Regeneration

```text
Implement the paper review/editing experience for the validated PaperDraft. Follow the paper schema and user-control requirements.

The user must be able to inspect title, abstract, keywords, ordered sections, references, and review warnings. Each section's content state must be visible where it affects required user action. Warnings need severity and actionable wording; do not imply automatic scientific verification.

Requirements:
- Build a section-oriented editor suitable for a mobile MVP, not a full rich-text word processor.
- Editing changes remain local and are persisted via the repository; surface save errors.
- Show warning summaries and let a user navigate to the associated section when a section ID exists.
- For section regeneration, show target section and current text, request a replacement preview, and require explicit accept/reject. A reject must leave the original unchanged. Accepting the replacement must preserve all non-target sections, references, title, and unrelated metadata.
- Make generation/regeneration pending, error, empty, needs-input, and success states explicit.
- Keep original source material accessible so the user can compare it with the generated draft.
- Avoid claiming plagiarism detection, citation verification, or proof of factual correctness.

Tests must prove editing persistence, warning rendering/navigation, regeneration preview, rejection leaves content unchanged, acceptance changes only the target section, and errors do not erase edits. Include long-text and small-screen widget tests where practical.
```
