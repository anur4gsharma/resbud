# Prompt 13 — Project Creation and Research Input UI

```text
Build the Resbud project creation/editing and research input flow in Flutter. Follow the product spec and schemas exactly; this is not a general-purpose word processor or a chat UI.

Required input areas: working title, research field, research question, objectives, claimed contribution, method status/details, dataset/materials status/details, results status/details, limitations status/details, existing draft, user-supplied references, target word count, desired sections, and citation preference. Use the exact enums and required/optional rules from the validated contract. Make the difference between “not collected/not available/not applicable” and “left blank/unknown” understandable.

Requirements:
- Validate user experience locally, while treating backend validation as authoritative.
- Show helpful field-level errors and reasonable character/count limits.
- Support paste/edit of a draft and import `.txt`/`.docx` through the approved importer path.
- Provide a pre-generation summary showing supplied fields and key missing-information warnings before the user incurs an API call.
- Add explicit save/back/cancel behavior that cannot accidentally erase a draft.
- Support loading, empty, validation-error, import-error, and success states.
- Keep layout accessible, keyboard-aware, usable on small screens, and compatible with Android first.
- Don't cram every optional field onto one overwhelming screen. Use clear grouping/progressive disclosure without hiding required input.

Add widget tests for required field validation, all status variants, import success/failure UI, save/cancel behavior, and pre-generation summary. Keep styling consistent and restrained. Do not implement real model calls in this prompt.
```
