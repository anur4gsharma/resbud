# 05 — Limitations and Threats to Validity

A rigorous academic evaluation must explicitly articulate what a system *cannot* do and where threats to experimental validity lie. This document outlines the fundamental technical, scientific, and platform limitations of Resbud.

---

## 1. Scientific and Content Limitations

### 1.1 Schema Validity Does Not Equal Scientific Truth
- **Distinction**: Resbud enforces strict JSON Schema (`Draft-07`) and Pydantic validation across all inputs and outputs.
- **Limitation**: A manuscript that is 100% schema-valid can still contain scientifically false deductions, invalid statistical interpretations, or flawed logical leaps. Schema validation proves syntactic correctness, structural completeness, and type safety, but **cannot prove empirical truth**.

### 1.2 Generated Content Can Still Be Inaccurate
- **Probabilistic Risk**: When backed by a real LLM provider (e.g. OpenAI `gpt-4o`), generation remains fundamentally probabilistic.
- **Mitigation**: Resbud structures prompts to emphasize faithfulness to input material and scans outputs for common integrity hazards. However, subtle hallucinations or misattributions of user-supplied facts can occur. Human review by qualified domain experts is mandatory prior to any academic submission.

### 1.3 No Automatic Citation or Authenticity Verification
- **User Responsibility**: Resbud preserves references supplied by the user and detects unreferenced claims via placeholder analysis (`[citation needed]`).
- **Limitation**: Resbud **does not** verify whether a cited paper exists, whether author names and publication venues are authentic, or whether the cited work actually supports the proposition. Automated bibliographic discovery is intentionally out of scope.

---

## 2. Model and Provider Threats to Validity

### 2.1 Provider Model Drift and Upstream Variability
- Commercial LLM providers frequently update weights, system filters, and tokenization models without prior notice.
- A prompt that produces faithful, restrained academic output on one model version may behave differently on a subsequent model checkpoint.
- Resbud mitigates this via explicit JSON schema response formatting and deterministic regression fixtures, but cannot insulate against all upstream model behavior changes.

### 2.2 Token Ceilings and Output Truncation
- To prevent runaway inference costs and denial-of-service, provider output is capped at `12,000` tokens.
- Highly detailed manuscripts or monographs exceeding this budget will require drafting section-by-section using the targeted section regeneration flow.

---

## 3. Storage and Platform Constraints

### 3.1 Local Storage and Device Loss Risk
- **Local-First Trade-Off**: Resbud stores all drafts and versions in an on-device SQLite database (`projects.sqlite`).
- **Limitation**: Because there is zero cloud backup or remote synchronization by design, uninstalling the mobile application or losing the physical device will cause permanent loss of unsaved projects unless the user has exported their work to DOCX.

### 3.2 Operating System Process Lifecycle
- Mobile operating systems (Android/iOS) can terminate background applications under memory pressure.
- Resbud persists project state transactionally before navigating and upon every manual save, but unsaved text actively being typed into a text controller at the instant of an OS kill relies on Flutter widget state preservation.

### 3.3 Platform Build Constraints
- The mobile codebase is cross-platform Flutter, but native iOS compilation requires macOS, Xcode, and Apple developer certificates. In Linux or Windows development environments, iOS compilation is unavailable.
