# 03 — Five-to-Eight Minute Academic Demo Script

This script provides an exact, repeatable demonstration procedure designed for examiners, mentors, and academic review panels. It utilizes a realistic synthetic research scenario with **deliberately missing experimental results** to demonstrate Resbud's research integrity constraints, warning systems, isolated section regeneration, and persistence.

---

## Scenario Overview

- **Project Title**: *Equivariant Graph Neural Networks for Molecular Conformer Energy Prediction*
- **Research Field**: Computer Science / Computational Chemistry
- **Research Question**: Can 3D equivariant message passing predict quantum ground-state energies within chemical accuracy (1 kcal/mol)?
- **Method**: Provided (E(3)-equivariant convolution with spherical harmonics).
- **Dataset**: Provided (QM9 dataset containing 134k organic molecules).
- **Results**: **Explicitly Not Conducted / Unavailable** *(The critical demo integrity gate)*.
- **Source Draft**: Unstructured author lab notes on message-passing filters.

---

## Demonstration Timeline (Total: 6–7 Minutes)

```
[00:00 - 00:45] Phase 1: Problem Context & Motivation
[00:45 - 01:45] Phase 2: Project Creation & Structured Inputs
[01:45 - 02:45] Phase 3: Pre-generation Integrity Warnings
[02:45 - 03:45] Phase 4: Generation & Structured Inspection
[03:45 - 05:00] Phase 5: Section Regeneration (Preview, Reject, Accept)
[05:00 - 05:45] Phase 6: Persistence & Process Reload
[05:45 - 06:30] Phase 7: DOCX Export & Standard Document Inspection
[06:30 - 07:00] Phase 8: Architectural Summary & Q&A Transition
```

---

## Detailed Step-by-Step Script

### Phase 1: Motivation and Problem Statement (00:00 - 00:45)
- **Visual**: Show empty Project List screen on mobile device/emulator.
- **Spoken**:  
  *"Good morning. Commercial LLMs frequently hallucinate experimental results and invent academic citations when students draft research papers. Resbud addresses this by pairing local-first privacy with schema-constrained generation and research integrity rules. I will demonstrate a complete vertical drafting cycle using a scenario where experiments have not yet been conducted, proving that Resbud flags missing evidence rather than fabricating empirical measurements."*

### Phase 2: Project Creation and Structured Inputs (00:45 - 01:45)
- **Visual Action**:
  1. Tap `+` (New project).
  2. Enter Title: `Equivariant Graph Neural Networks for Molecular Conformer Energy Prediction`.
  3. Enter Field: `Computer Science`. Tap **Create**.
  4. Fill Research Question, Objectives, and Claimed Contribution.
  5. Under **Research Evidence**:
     - Set Method to `Provided` (enter description).
     - Set Dataset to `Provided` (QM9).
     - Set Results to **`Explicitly Not Conducted / Unavailable`**. *(Point out this distinction to examiners)*.
  6. Tap **Import Document** to import `synthetic_notes.txt` into Existing Draft.
- **Spoken**:  
  *"Notice the distinction here. In generic tools, leaving results blank often causes the AI to invent metrics like 'our model achieved 98.4% accuracy'. In Resbud, 'Explicitly Not Conducted' is formally encoded in the request context."*

### Phase 3: Pre-Generation Integrity Warnings (01:45 - 02:45)
- **Visual Action**:
  1. Tap **Review before generation**.
  2. Show the summary dialog displaying:
     - 4 supplied items.
     - Warning: `Results is explicitly not conducted.`
     - Notice: `No user-supplied references; citations must not be assumed verified.`
  3. Dismiss dialog and tap **Save project**.
  4. Point out the top AppBar badge: transitions from `Unsaved` to `Saved`.
- **Spoken**:  
  *"Before sending a single byte to any model, Resbud runs client-side integrity validation. It warns the researcher that results are absent and informs them of the exact citation boundaries. Furthermore, inputs are persisted locally to SQLite."*

### Phase 4: Generation and Structured Inspection (02:45 - 03:45)
- **Visual Action**:
  1. Tap **Generate**.
  2. Observe the loading bar: the button disables to prevent duplicate submissions.
  3. App transitions to **Paper Editor**.
  4. Inspect the top banner:
     - Prominent Human Review Disclaimer.
     - Review Warnings Card: `MISSING_RESULTS` (Severity: Warning).
  5. Scroll to **Results and Discussion**:
     - Point out the section content: explicitly states experimental evaluation has not been conducted and provides structured placeholders for empirical findings.
- **Spoken**:  
  *"The generated paper adheres to our versioned PaperDraft schema. Crucially, look at the Results section: Resbud did not fabricate a single benchmark score or p-value. It flagged the gap and marked the section with an amber 'Needs input' badge."*

### Phase 5: Section Regeneration (Preview, Reject, Accept) (03:45 - 05:00)
- **Visual Action**:
  1. Make a manual edit in the **Introduction** section: append `[Verified baseline: 2026]`.
  2. Tap **Save edits** (creates Version 2).
  3. Scroll to **Methodology** section. Tap **Regenerate section**.
  4. Enter user guidance: `Detail the spherical harmonics projection filter.`
  5. Tap **Request Preview**.
  6. Show side-by-side diff in the preview sheet.
  7. Tap **Reject replacement**: Methodology remains unchanged.
  8. Tap **Regenerate section** again -> **Accept replacement**.
  9. Point out:
     - Methodology is updated with the new text.
     - **Introduction still contains `[Verified baseline: 2026]`**. All unselected sections survived byte-for-byte.
- **Spoken**:  
  *"Unlike chat bots where re-prompting rewrites the whole paper, Resbud supports surgical single-section regeneration. Notice our manual addition in the Introduction remained completely intact when Methodology was replaced."*

### Phase 6: Persistence and Process Reload (05:00 - 05:45)
- **Visual Action**:
  1. Tap the **Version History** button in the top bar.
  2. Show immutable version log:
     - `v1`: Initial Generation
     - `v2`: Manual Edit
     - `v3`: Section Regeneration: Methodology
  3. Navigate back to Project List.
  4. Close and re-open the project (or simulate app relaunch).
  5. Verify that all 3 versions and draft states are instantly restored from SQLite.
- **Spoken**:  
  *"Every edit and accepted proposal creates an append-only version snapshot on the device. Closing the app or restarting the device causes zero data loss."*

### Phase 7: DOCX Export and Reader Verification (05:45 - 06:30)
- **Visual Action**:
  1. Tap **Export DOCX** in the AppBar.
  2. Confirm save location.
  3. Open the resulting `.docx` in LibreOffice Writer / Microsoft Word.
  4. Show formatted document structure: Title, Abstract, Section Headings (Heading 2), clean body paragraphs, and references list.
- **Spoken**:  
  *"The export service builds a clean, publication-ready DOCX in memory. Heading hierarchy, paragraph margins, and citations match journal submission standards."*

### Phase 8: Conclusion and Architectural Summary (06:30 - 07:00)
- **Spoken**:  
  *"To summarize: Resbud demonstrates that academic AI tools can be built with rigorous research-integrity constraints, zero server retention of student research, and deterministic software engineering. The system is verified by 105 backend and 111 mobile automated tests running 100% offline. I welcome your questions."*
