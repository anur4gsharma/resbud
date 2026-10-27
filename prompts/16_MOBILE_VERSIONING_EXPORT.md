# Prompt 16 — Version History, Save Semantics, and Export UX

```text
Complete save/reopen/version behavior and mobile DOCX export. Read the data model and export contract first.

Requirements:
- Define which actions create a version (for example generation acceptance, manual save, accepted section regeneration) and document the chosen semantics. Avoid creating a new version on every keystroke.
- Preserve the original imported/source draft separately from generated and edited paper content.
- Show saved/unsaved status accurately. Autosave may be used only if it is reliable and tested; otherwise provide clear explicit save behavior.
- Allow reopening prior versions and restoring one only after an explicit user action, without destroying the current version.
- Export the currently selected/saved paper version—not stale widget memory. Validate content before sending it.
- Handle export progress, invalid response, network failure, file save/share failure, and unsupported platform behavior without changing saved content.
- Give exported files a safe, human-readable name and handle duplicate filenames.
- If local file sharing/saving behavior differs by OS, isolate it behind a small service and document platform limitations.

Tests: version creation/order, restore behavior, original source preservation, correct current content exported, failure leaves content intact, and duplicate filename handling. Verify a real exported DOCX opens in a compatible office reader when possible; state clearly if manual visual verification is unavailable.
```
