# 35 — IEEE Conference Research Paper Format Architecture and Specification

## 1. Executive Summary

This specification establishes the first-class **IEEE Conference Research Paper** format (`ieee_conference`) in Resbud. Rather than simply applying visual styling or CSS two-column text flow, Resbud implements an authentic academic publishing pipeline that generates genuine Microsoft WordprocessingML (`.docx`) and high-fidelity ReportLab PDF documents conforming precisely to IEEE conference publication standards.

The implementation is reverse-engineered from and verified against the canonical reference document:
**`ASEP 2 RP.docx`** (Automated Posture Analysis and Ergonomic Risk Assessment).

---

## 2. Template Identity

| Property | Value | Description |
| :--- | :--- | :--- |
| **Display Name** | IEEE Conference Paper | User-facing display title in web and mobile interfaces |
| **Internal ID** | `ieee_conference` | Canonical template identifier across API and domain models |
| **Category** | Academic Research | Predefined format classification |
| **Default Page Layout** | `two_column_academic` | Full-width title/author header followed by two-column continuous body |
| **Default Typography** | Times New Roman | 24pt title, 11pt authors, 10pt primary headings, 10pt body, 9pt abstract/affiliations |
| **Default Equation Format** | `omml` | Native Office Math Markup Language editable in Word Equation Editor |
| **Default Citation Format** | `ieee` | Numbered bracket citations (`[1]`, `[2]–[4]`) |
| **Default Reference Format** | IEEE bibliography | Unnumbered centered `REFERENCES` section with hanging indentation |

---

## 3. Reference Geometry and WordprocessingML Architecture

Analysis of `ASEP 2 RP.docx` reveals two distinct WordprocessingML sections linked by a continuous section break (`<w:type w:val="continuous"/>`):

```
+-----------------------------------------------------------------------+
|  PAGE: US Letter (8.5" x 11" = 12240 dxa x 15840 dxa)                 |
|  Margins: Top = 0.75" (1080 dxa), Bottom = 0.75" (1080 dxa)           |
|           Left = 0.625" (900 dxa), Right = 0.625" (900 dxa)           |
|  Printable Width = 7.25" (10440 dxa)                                  |
|                                                                       |
|  SECTION 0: Single-Column Title and Author Block (Header)              |
|  - Paper Title (24pt, Centered, Bold)                                 |
|  - Borderless Author Tables (10440 dxa total width, centered)         |
+-----------------------------------------------------------------------+
======================== Continuous Section Break =======================
+-----------------------------------+   +-------------------------------+
|  SECTION 1: Two-Column Body       |   |                               |
|  - Columns: 2 (w:cols num="2")    |   |                               |
|  - Spacing: 0.25" / 18pt (360 dxa)|   |                               |
|                                   |   |                               |
|  Abstract— (Bold Italic 9pt)      |   |                               |
|  Index Terms— (Bold Italic 9pt)   |   |                               |
|                                   |   |                               |
|  I. INTRODUCTION                  |   |  II. METHODOLOGY              |
|  (Small caps, 10pt bold, centered)|   |  (Small caps, centered)       |
|                                   |   |                               |
|  Body text (10pt Times, justified)|   |  A. Mathematical Formulation  |
|  Line spacing: 1.05x, spaceAfter:4|   |  (Italic, left-aligned)       |
|                                   |   |                               |
|  [Equation / Table / Figure]      |   |  Native OMML equations:       |
|                                   |   |  $$\mathbf{E} = \sum...$$     |
|                                   |   |                               |
|                                   |   |  REFERENCES (Unnumbered)      |
|                                   |   |  [1] Author, Title, 2024.     |
+-----------------------------------+   +-------------------------------+
```

### 3.1 Page Dimensions & Margin twips (dxa)

- **Page Width**: $8.5 \text{ inches} = 12,240 \text{ dxa}$ (twips)
- **Page Height**: $11.0 \text{ inches} = 15,840 \text{ dxa}$ (twips)
- **Top Margin**: $0.75 \text{ inches} = 1,080 \text{ dxa}$
- **Bottom Margin**: $0.75 \text{ inches} = 1,080 \text{ dxa}$
- **Left Margin**: $0.625 \text{ inches} = 900 \text{ dxa}$
- **Right Margin**: $0.625 \text{ inches} = 900 \text{ dxa}$
- **Net Printable Area**: $8.5 - 2 \times 0.625 = 7.25 \text{ inches} = 10,440 \text{ dxa}$
- **Column Gap**: $0.25 \text{ inches} = 18 \text{ pt} = 360 \text{ dxa}$
- **Column Width**: $(10,440 - 360) / 2 = 5,040 \text{ dxa} = 3.5 \text{ inches}$

---

## 4. Structured Author Model

Rather than storing author details in an unstructured string or comma-separated text line, Resbud defines structured domain entities supporting 1 to 10 authors:

### 4.1 Schema Definition

```python
class AuthorAffiliation(ContractModel):
    id: str                                    # e.g. "aff1"
    department: str | None = None              # e.g. "Dept. of Information Technology"
    institution: str                           # e.g. "B.K. Birla Institute of Engineering & Technology"
    city: str | None = None                    # e.g. "Pilani"
    state: str | None = None
    country: str | None = None                 # e.g. "India"

class AuthorMetadata(ContractModel):
    name: str                                  # Author full name (e.g. "Jane Doe")
    order: int = 1                             # 1-based publication sequence
    affiliation_ids: list[str] = []            # References to AuthorAffiliation.id
    email: str | None = None                   # Individual or corresponding email
    role_or_title: str | None = None           # e.g. "UG Student", "Associate Professor"
    is_corresponding: bool = False             # Corresponding author flag
    funding_acknowledgment: str | None = None  # Optional grant/funding note
```

### 4.2 Author Grid Calculation Algorithm

In standard IEEE conference publications (and directly demonstrated in `ASEP 2 RP.docx`), authors are arranged in borderless tables spanning the full $10,440 \text{ dxa}$ printable width. When author count exceeds 4, the blocks are partitioned across multiple rows:

| Author Count | Table Distribution | Column Widths (dxa) | Layout Rationale |
| :---: | :---: | :---: | :--- |
| **1** | `[1]` | `[10440]` | Single centered author block |
| **2** | `[2]` | `[5220, 5220]` | 1 row, 2 equal columns |
| **3** | `[3]` | `[3480, 3480, 3480]` | 1 row, 3 equal columns |
| **4** | `[2, 2]` | Row 1: `[5220, 5220]`, Row 2: `[5220, 5220]` | 2 balanced rows of 2 columns |
| **5** | `[3, 2]` | Row 1: `[3480, 3480, 3480]`, Row 2: `[5220, 5220]` | **Direct replica of `ASEP 2 RP.docx`** |
| **6** | `[3, 3]` | Row 1: `[3480, 3480, 3480]`, Row 2: `[3480, 3480, 3480]` | 2 rows of 3 columns |
| **7** | `[4, 3]` | Row 1: `[2610, 2610, 2610, 2610]`, Row 2: `[3480, 3480, 3480]` | 2 rows (4 on top, 3 below) |
| **8** | `[4, 4]` | Row 1: `[2610, 2610, 2610, 2610]`, Row 2: `[2610, 2610, 2610, 2610]` | 2 rows of 4 columns |
| **9** | `[3, 3, 3]`| 3 rows of 3 columns (`3480 dxa` each) | 3 balanced rows |
| **10** | `[4, 3, 3]`| Row 1: 4 columns, Rows 2-3: 3 columns each | 3 rows |

### 4.3 Research Integrity and Unresolved Metadata Rules

> [!IMPORTANT]
> **Strict Fabrication Safeguard**: Resbud **never** fabricates author names, institutional affiliations, departments, credentials, or email addresses.
> If metadata is incomplete during generation or export:
> 1. The validator emits an explicit unresolved warning (e.g. `Author 'Jane Doe' is missing institutional affiliation details.`).
> 2. The system renders only verified fields without inventing placeholder institutions or academic titles.

---

## 5. Heading Hierarchy and IEEE Conventions

IEEE conference publications follow strict numbering conventions for section headings:

```
+--------------------------------------------------------------------------+
| Heading Level | IEEE Numbering | Style / Typography                      |
+---------------+----------------+-----------------------------------------+
| Level 1 (H1)  | Roman: I., II. | 10pt Bold, Small Caps, Centered         |
| Unnumbered H1 | None           | 10pt Bold, Small Caps, Centered         |
|               |                | (REFERENCES, ACKNOWLEDGMENT)            |
| Level 2 (H2)  | Letter: A., B. | 10pt Italic, Title Case, Left-Aligned   |
| Level 3 (H3)  | Parentheses:   | 10pt Italic, Title Case, Left-Aligned,  |
|               | 1), 2)         | Run-in with colon                       |
+--------------------------------------------------------------------------+
```

### 5.1 Unnumbered IEEE Sections

The following sections must never receive Roman numeral numbering in IEEE conference papers:
- `REFERENCES` / `BIBLIOGRAPHY`
- `ACKNOWLEDGMENT` / `ACKNOWLEDGMENTS`
- `AUTHOR CONTRIBUTIONS`
- `APPENDIX` / `APPENDICES`

The template implementation automatically strips artificial numeric prefixes (e.g. `6. References` or `IV. References`) and formats the heading as unnumbered centered small-caps `REFERENCES`.

---

## 6. Abstract and Index Terms Format

In IEEE conference style, the Abstract and Index Terms are placed at the beginning of the two-column body (Section 1) rather than in the full-width header:

1. **Abstract**:
   - Run-in style: `Abstract—` in **bold italic 9pt Times New Roman**, immediately followed by the bold 9pt abstract text.
   - Justified alignment, 1.05 line spacing.
   - No equation numbers, citations, or references inside the abstract.
2. **Index Terms**:
   - Run-in style: `Index Terms—` in **bold italic 9pt Times New Roman**, immediately followed by comma-separated keywords in regular 9pt Times New Roman.
   - Followed by 10pt space before the first body section heading (`I. INTRODUCTION`).

---

## 7. Mathematical Typesetting Integration (Native OMML)

Mathematical formulas authoring syntax is standard LaTeX. During DOCX export with the IEEE conference template:

1. Inline math (`$x$`, `$\alpha \in [0, 1]$`) is converted into inline Office Math Markup Language (`<m:oMath>`) runs within the paragraph text.
2. Display math (`$$\mathbf{E} = \sum_{i=1}^K ...$$`) is converted into display OMML blocks (`<m:oMathPara>`) centered within the column width.
3. Microsoft Word natively recognizes these objects as editable equations (accessible through Word's built-in Equation Tools ribbon).

---

## 8. Verification and Test Suite Coverage

The implementation is verified by comprehensive automated test suites:

- **`backend/tests/test_ieee_conference_template.py`**:
  - `test_ieee_template_registry`: Validates configuration parameters, column count, margins, and typography.
  - `test_ieee_roman_and_letter_numbering`: Validates bijective base-26 and Roman numeral conversions.
  - `test_ieee_heading_formatting`: Validates H1 Roman formatting, unnumbered References/Acknowledgment, H2 lettered subheadings, and H3 numbered subheadings.
  - `test_ieee_author_grid_calculations`: Tests author distributions for 1 through 10 authors.
  - `test_author_metadata_validation`: Ensures missing metadata produces warnings without fabricating.
  - `test_ieee_docx_export_replicates_reference_geometry`: Unpacks exported DOCX zip archive and validates WordprocessingML:
    - Section 0 single column Letter with 0.75" / 0.625" margins.
    - Section 1 continuous 2-column with 360 twips gap.
    - Borderless author tables with 3480 and 5220 dxa grid columns.
    - `Abstract—` and `Index Terms—` run-in text.
    - Native OMML `<m:oMath>` equations.
  - `test_ieee_export_api_endpoints`: Verifies HTTP `/api/v1/exports/docx` and `/api/v1/exports/pdf` with `?template=ieee_conference`.
- **`mobile/test/ieee_conference_template_test.dart`**:
  - Serialization and deserialization of `AuthorMetadataPayload` and `AuthorAffiliationPayload`.
  - Wire contract roundtrip through `PaperPreferencesPayload` and `PaperDraftPayload`.
  - Paginated canvas widget rendering with 5-author grid, run-in abstract, and Roman numeral headings.
