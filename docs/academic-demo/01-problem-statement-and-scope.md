# 01 — Problem Statement, Objectives, and Scope

---

## 1. Context and Problem Statement

Academic paper writing is demanding, iterative, and structurally constrained. Early-career researchers, graduate students, and independent scholars frequently struggle with the transition from raw laboratory notes, experimental code, and disorganized draft paragraphs to standard academic manuscript structures (Abstract, Introduction, Methodology, Results, Discussion, Conclusion).

Commercial and generic AI assistants (such as unguided ChatGPT or generic writing bots) present severe academic integrity hazards when applied to research drafting:
1. **Unchecked Hallucination & Fabrication**: Generic LLMs routinely fabricate empirical results, create fictional datasets, and synthesize non-existent citations with fake DOIs and author lists.
2. **Loss of Intellectual Ownership & Privacy**: Most cloud-based writing platforms transmit and permanently retain unpublished research drafts, raw hypotheses, and intellectual property on external servers without clear boundaries.
3. **Coarse All-or-Nothing Rewrites**: Chat-based tools regenerate entire papers at once, destroying careful user-authored nuances and making granular revisions tedious.
4. **Lack of Structured Warning Systems**: Generic tools do not distinguish between *missing* information (unknown) and *explicitly not conducted* work, often generating misleading conclusions.

**Resbud** addresses these core defects by providing an on-device, local-first research paper drafting companion with strict schema boundaries, explicit research-integrity safeguards, and targeted section-level regeneration.

---

## 2. Intended Users

- **Graduate and Undergraduate Researchers**: Drafting initial seminar, conference, or workshop submissions from lab notes.
- **Academic Mentors and Advisors**: Assisting students in structuring papers while ensuring empirical claims remain faithful to supplied evidence.
- **Applied Scientists and Engineers**: Converting technical documentation and experimental logs into formal academic drafts.

---

## 3. Core Objectives

1. **Structured Synthesis**: Transform structured research facts (field, question, objectives, claimed contributions, evidence statuses) and raw source drafts into standardized academic manuscripts adhering to `PaperDraft` schema version 1.
2. **Explicit Research Integrity**:
   - Prevent fabrication of empirical numbers or experimental findings when results are unsupplied or marked "not conducted".
   - Prohibit invention of fabricated citations; restrict reference outputs to user-supplied sources or explicit verification placeholders (`[citation needed]`).
   - Flag internal claim discrepancies and structural gaps prior to submission.
3. **Local-First Privacy**:
   - Store all projects, contexts, drafts, and version histories locally on the user's device in SQLite.
   - Maintain a stateless backend that operates in-memory without persistent server storage of research content.
4. **Targeted Revision & Safe Section Regeneration**:
   - Enable single-section regeneration proposals with side-by-side preview and reject/accept controls.
   - Guarantee byte-for-byte preservation of unselected sections and existing manual revisions.
5. **Standard Interoperability**:
   - Safe import of `.txt` and `.docx` source documents.
   - Deterministic, styled `.docx` document export ready for external word processors.

---

## 4. Explicit Non-Goals (Out of Scope for MVP)

To maintain architectural focus and avoid misleading claims, the following capabilities are explicitly declared outside MVP scope:

- **Automated Literature Discovery & Web Crawling**: Resbud does not search Semantic Scholar, PubMed, or arXiv for new literature.
- **Automated Truth & Plagiarism Verification**: Resbud does not verify whether external claims are mathematically or scientifically true, nor does it run plagiarism scans.
- **Cloud Multi-User Collaborative Editing**: Resbud does not provide Google Docs-style real-time multi-cursor collaboration.
- **LaTeX Compilation Engine**: Resbud outputs clean `.docx` manuscripts; automated LaTeX compilation is deferred.
- **Probabilistic Chat Interface**: Resbud is a structured workflow app, not a conversational chatbot.
