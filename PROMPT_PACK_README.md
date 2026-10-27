# Resbud Build Prompt Pack

This pack is a staged implementation workflow for Resbud, a research-paper drafting MVP built with Flutter/Dart, Python/FastAPI, one LLM provider, local-first persistence, structured paper output, and DOCX import/export.

It is designed to work with an AI coding agent that can inspect and edit the repository (for example, Codex, Claude Code, Cursor, or a comparable agent). The prompts are deliberately milestone-based: quality is better when the agent implements and verifies small vertical slices than when it attempts the entire application in one giant request.

## Recommended order

1. Start the coding-agent session with `prompts/00_GLOBAL_OPERATING_RULES.md`.
2. Run `01_SPEC_AND_REPOSITORY_AUDIT.md`. Fix contract/document contradictions before building features.
3. Run prompts in ascending order, but only when their prerequisites are met.
4. After each prompt, review the diff and test results before continuing.
5. Run `21_FINAL_ENGINEERING_AUDIT.md` before calling the MVP complete.
6. Run `22_ACADEMIC_DEMO_AND_VIVA.md` after real implementation/test evidence exists.

## Prompt map

| Prompt | Component | Main result |
|---|---|---|
| 00 | Shared rules | Consistent engineering behavior across the session |
| 01 | Spec audit | Resolved requirements, schema gaps, ADRs |
| 02 | Bootstrap | Reproducible repo/tooling setup |
| 03 | Backend foundation | FastAPI app, configuration, health, safe errors |
| 04 | Contracts/models | Validated domain and transport types |
| 05 | Fake-provider slice | First testable generation endpoint |
| 06 | Research integrity | Prompt construction and deterministic safeguards |
| 07 | Real provider | Provider adapter, bounded calls, secret handling |
| 08 | Section regeneration | Preview/accept flow that preserves other sections |
| 09 | Source import | Safe TXT/DOCX text extraction |
| 10 | DOCX export | Validated in-memory document export |
| 11 | Backend evaluation | Regression suite and repeatable AI test fixtures |
| 12 | Mobile foundation | Local-first persistence, migrations, repositories |
| 13 | Project inputs | Project creation, structured research form, imports |
| 14 | Generation flow | Typed API client and explicit UI states |
| 15 | Review/editor | Edit, warnings, safe section regeneration |
| 16 | Versions/export | Save/reopen/restore and mobile export handling |
| 17 | Security | Auth, rate limits, privacy and release controls |
| 18 | Integration | Full workflow tests and requirement traceability |
| 19 | UX/accessibility | Improve usability without expanding scope |
| 20 | Deployment | Release setup, operations, rollback notes |
| 21 | Final audit | Prioritized findings and evidence-based acceptance matrix |
| 22 | Academic demo | Demo script, limitations, evidence, viva preparation |

## Important: don't run them as one giant prompt

A one-shot prompt is tempting, but it encourages large unreviewable diffs, hidden contract conflicts, weak testing, and fake completion claims. Treat each prompt as one implementation milestone. If the agent reaches a design conflict, it must reconcile the docs/contracts or document the blocker rather than invent behavior silently.

The first prompts should use the fake provider and deterministic tests. Add real provider access only after request validation, response schema validation, and error handling work without a network connection. This keeps debugging cost down and lets you demonstrate engineering rigor independently from model output quality.

## Expected per-prompt workflow

- Read relevant docs/contracts and inspect current code.
- State a short plan and files to be changed.
- Implement only the requested milestone.
- Add tests and documentation updates.
- Run formatting, static checks, and tests.
- Review changed files for secrets, logging of user content, data loss, and contract drift.
- Report exact commands/results, limitations, and the next single recommended task.

## Specification audit status

Prompt 01 has been completed. The audit report is `docs/11-spec-audit-and-decisions.md`; its unresolved deployment choices remain open until a remote beta is planned. The local import, storage, and section-regeneration decisions are documented in the ADRs and synchronized contracts.

## Folder layout

- `prompts/` contains 23 prompts, including the global operating rules.
- `PROMPTS_ALL_IN_ONE.md` concatenates the prompts for easier search and offline review. For actual coding, send only one numbered task prompt at a time.
