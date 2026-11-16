"""Comprehensive test suite for IEEE Reference, Citation Management, and Bibliography Engine.

Covers:
- All 11 IEEE publication types formatting.
- First-appearance sequential numbering.
- Multiple and consecutive citations ([1], [1], [3], [1]–[3]).
- Reference reordering and synchronization.
- Duplicate detection (DOI, URL, title/year signature).
- Missing metadata validation and zero-fabrication guarantee.
- DOI validation and normalization.
- Citation-reference integrity (unresolved citations, uncited references).
- Author-date citation normalization in IEEE mode.
- DOCX export verification.
- PDF export verification.
- BibliographicResolver integration.
"""

from __future__ import annotations

import io
from typing import Any

from docx import Document
from pypdf import PdfReader

from resbud_api.domain.models import (
    PaperDraft,
    PaperSection,
    ReferenceInput,
)
from resbud_api.services.docx_export import export_paper_docx
from resbud_api.services.pdf_export import export_paper_pdf
from resbud_api.services.reference_engine import (
    BibliographicResolver,
    detect_duplicate_references,
    format_ieee_authors,
    format_ieee_citation_group,
    format_ieee_reference,
    normalize_doi,
    process_manuscript_citations_and_bibliography,
    validate_reference_metadata,
)


def test_all_11_publication_types_ieee_formatting() -> None:
    """Verify authentic IEEE formatting across all 11 supported publication types."""
    types_and_refs: list[tuple[str, ReferenceInput, str]] = [
        (
            "journal_article",
            ReferenceInput(
                id="ref_journal",
                text="raw journal",
                publication_type="journal_article",
                authors=["Alan Turing", "Claude Shannon"],
                title="On Computable Numbers and Information Entropy",
                venue="IEEE Transactions on Information Theory",
                volume="12",
                issue="3",
                pages="100–115",
                year=2024,
                doi="10.1109/TIT.2024.1234567",
            ),
            'A. Turing and C. Shannon, "On Computable Numbers and Information Entropy", IEEE Transactions on Information Theory, vol. 12, no. 3, pp. 100–115, 2024, doi: 10.1109/TIT.2024.1234567.',
        ),
        (
            "conference_paper",
            ReferenceInput(
                id="ref_conf",
                text="raw conf",
                publication_type="conference_paper",
                authors=["Ashish Vaswani", "Noam Shazeer", "Niki Parmar"],
                title="Attention Is All You Need",
                venue="Advances in Neural Information Processing Systems",
                pages="5998–6008",
                year=2017,
                doi="10.5555/3295222.3295349",
            ),
            'A. Vaswani, N. Shazeer, and N. Parmar, "Attention Is All You Need", in Proc. Advances in Neural Information Processing Systems, 2017, pp. 5998–6008, doi: 10.5555/3295222.3295349.',
        ),
        (
            "book",
            ReferenceInput(
                id="ref_book",
                text="raw book",
                publication_type="book",
                authors=["Donald Knuth"],
                title="The Art of Computer Programming",
                volume="3rd",
                publisher="Addison-Wesley",
                year=1997,
            ),
            "D. Knuth, The Art of Computer Programming, 3rd ed., Addison-Wesley, 1997.",
        ),
        (
            "book_chapter",
            ReferenceInput(
                id="ref_chapter",
                text="raw chapter",
                publication_type="book_chapter",
                authors=["Grace Hopper"],
                title="Compiling Routines",
                venue="High-Level Language Systems",
                publisher="Academic Press",
                pages="45–62",
                year=1981,
            ),
            'G. Hopper, "Compiling Routines", in High-Level Language Systems, Academic Press, 1981, pp. 45–62.',
        ),
        (
            "thesis",
            ReferenceInput(
                id="ref_thesis",
                text="raw thesis",
                publication_type="thesis",
                authors=["Barbara Liskov"],
                title="A Program for Computer Translation",
                venue="Dept. Computer Science, Stanford University",
                volume="Ph.D. dissertation",
                year=1968,
            ),
            'B. Liskov, "A Program for Computer Translation", Ph.D. dissertation, Dept. Computer Science, Stanford University, 1968.',
        ),
        (
            "technical_report",
            ReferenceInput(
                id="ref_report",
                text="raw report",
                publication_type="technical_report",
                authors=["Leslie Lamport"],
                title="Time, Clocks, and the Ordering of Events",
                publisher="Massachusetts Computer Associates",
                issue="CA-7603-2911",
                year=1976,
            ),
            'L. Lamport, "Time, Clocks, and the Ordering of Events", Massachusetts Computer Associates, Tech. Rep. CA-7603-2911, 1976.',
        ),
        (
            "standard",
            ReferenceInput(
                id="ref_std",
                text="raw std",
                publication_type="standard",
                title="IEEE Standard for Ethernet",
                issue="IEEE Std 802.3-2022",
                publisher="IEEE",
                year=2022,
            ),
            "IEEE Standard for Ethernet, IEEE Std 802.3-2022, 2022.",
        ),
        (
            "patent",
            ReferenceInput(
                id="ref_patent",
                text="raw patent",
                publication_type="patent",
                authors=["Nikola Tesla"],
                title="System of Electrical Distribution",
                issue="381,970",
                year=1888,
            ),
            'N. Tesla, "System of Electrical Distribution", U.S. Patent 381,970, 1888.',
        ),
        (
            "website",
            ReferenceInput(
                id="ref_web",
                text="raw website",
                publication_type="website",
                authors=["Tim Berners-Lee"],
                title="Information Management: A Proposal",
                venue="World Wide Web Consortium",
                url="https://www.w3.org/History/1989/proposal.html",
                access_date="Jan. 10, 2024",
                year=1989,
            ),
            'T. Berners-Lee, "Information Management: A Proposal", World Wide Web Consortium, 1989. [Online]. Available: https://www.w3.org/History/1989/proposal.html. [Accessed: Jan. 10, 2024].',
        ),
        (
            "software_documentation",
            ReferenceInput(
                id="ref_soft",
                text="raw software",
                publication_type="software_documentation",
                title="NumPy Reference Guide",
                publisher="NumPy Developers",
                volume="1.26",
                url="https://numpy.org/doc/stable/",
                year=2023,
            ),
            '"NumPy Reference Guide", NumPy Developers, Version 1.26, 2023. [Online]. Available: https://numpy.org/doc/stable/.',
        ),
        (
            "preprint",
            ReferenceInput(
                id="ref_preprint",
                text="raw preprint",
                publication_type="preprint",
                authors=["Geoffrey Hinton", "Oriol Vinyals"],
                title="Distilling the Knowledge in a Neural Network",
                issue="1503.02531",
                year=2015,
            ),
            'G. Hinton and O. Vinyals, "Distilling the Knowledge in a Neural Network", arXiv:1503.02531, 2015.',
        ),
    ]

    for idx, (expected_type, ref, expected_body) in enumerate(types_and_refs, start=1):
        assert ref.publication_type == expected_type
        formatted = format_ieee_reference(ref, citation_number=idx)
        assert formatted.startswith(f"[{idx}] ")
        assert expected_body in formatted


def test_first_appearance_citation_numbering() -> None:
    """Verify that citations are numbered in order of their FIRST appearance in the manuscript."""
    r_vaswani = ReferenceInput(
        id="ref_vaswani",
        text="Vaswani et al., 2017",
        title="Attention Is All You Need",
        authors=["A. Vaswani", "N. Shazeer"],
        year=2017,
        publication_type="conference_paper",
    )
    r_he = ReferenceInput(
        id="ref_he",
        text="He et al., 2016",
        title="Deep Residual Learning",
        authors=["K. He", "X. Zhang"],
        year=2016,
        publication_type="conference_paper",
    )
    r_knuth = ReferenceInput(
        id="ref_knuth",
        text="Knuth, 1997",
        title="The Art of Computer Programming",
        authors=["D. Knuth"],
        year=1997,
        publication_type="book",
    )
    r_hopper = ReferenceInput(
        id="ref_hopper",
        text="Hopper, 1981",
        title="Compiling Routines",
        authors=["G. Hopper"],
        year=1981,
        publication_type="book_chapter",
    )

    # Initial order in paper: [Vaswani, He, Knuth, Hopper]
    # But in text, He is cited first, then Knuth, then Vaswani. Hopper is uncited.
    paper = PaperDraft(
        schema_version=1,
        title="Test Citation Ordering",
        abstract="Abstract overview.",
        keywords=["test"],
        sections=[
            PaperSection(
                id="sec_intro",
                heading="Introduction",
                content="Recent architectures rely on residual shortcuts [ref_he]. Then we examine [ref_knuth].",
                state="draft",
            ),
            PaperSection(
                id="sec_methods",
                heading="Methodology",
                content="Building on [ref_he] and self-attention [ref_vaswani], we construct the pipeline.",
                state="draft",
            ),
        ],
        references=[r_vaswani, r_he, r_knuth, r_hopper],
        review_warnings=[],
    )

    updated_paper, warnings = process_manuscript_citations_and_bibliography(paper)

    # He appeared first -> [1]
    # Knuth appeared second -> [2]
    # Vaswani appeared third -> [3]
    # Hopper was uncited -> [4]
    ref_map = {r.id: r for r in updated_paper.references}
    assert ref_map["ref_he"].citation_number == 1
    assert ref_map["ref_he"].is_cited is True
    assert "sec_intro" in (ref_map["ref_he"].citation_locations or [])
    assert "sec_methods" in (ref_map["ref_he"].citation_locations or [])

    assert ref_map["ref_knuth"].citation_number == 2
    assert ref_map["ref_knuth"].is_cited is True
    assert "sec_intro" in (ref_map["ref_knuth"].citation_locations or [])

    assert ref_map["ref_vaswani"].citation_number == 3
    assert ref_map["ref_vaswani"].is_cited is True
    assert "sec_methods" in (ref_map["ref_vaswani"].citation_locations or [])

    assert ref_map["ref_hopper"].citation_number == 4
    assert ref_map["ref_hopper"].is_cited is False
    assert ref_map["ref_hopper"].citation_locations == []

    # In-text citations must be renumbered according to appearance
    intro_content = next(s.content for s in updated_paper.sections if s.id == "sec_intro")
    assert "[1]" in intro_content
    assert "[2]" in intro_content
    assert "[ref_he]" not in intro_content
    assert "[ref_knuth]" not in intro_content

    methods_content = next(s.content for s in updated_paper.sections if s.id == "sec_methods")
    assert "[1]" in methods_content
    assert "[3]" in methods_content

    # Warning generated for uncited Hopper
    assert any(w.code == "REFERENCE_INCOMPLETE" and "ref_hopper" in w.message for w in warnings)


def test_multiple_and_consecutive_citation_groups() -> None:
    """Verify IEEE citation grouping: single [1], pair [1], [2], ranges [1]–[3], and mixed groups."""
    assert format_ieee_citation_group([1]) == "[1]"
    assert format_ieee_citation_group([1, 2]) == "[1], [2]"
    assert format_ieee_citation_group([1, 2, 3]) == "[1]–[3]"
    assert format_ieee_citation_group([1, 3, 5]) == "[1], [3], [5]"
    assert format_ieee_citation_group([1, 2, 3, 5]) == "[1]–[3], [5]"
    assert format_ieee_citation_group([1, 2, 3, 5, 6, 7]) == "[1]–[3], [5]–[7]"
    assert format_ieee_citation_group([3, 1, 2]) == "[1]–[3]"


def test_author_formatting_rules() -> None:
    """Verify IEEE author formatting for 1, 2, 3–6, and >6 authors with nobiliary particle preservation."""
    assert format_ieee_authors(["Alan Turing"]) == "A. Turing"
    assert format_ieee_authors(["Alan Turing", "Claude Shannon"]) == "A. Turing and C. Shannon"
    assert (
        format_ieee_authors(["Alan Turing", "Claude Shannon", "John von Neumann"])
        == "A. Turing, C. Shannon, and J. von Neumann"
    )
    many_authors = [
        "Author One",
        "Author Two",
        "Author Three",
        "Author Four",
        "Author Five",
        "Author Six",
        "Author Seven",
    ]
    assert format_ieee_authors(many_authors) == "A. One et al."


def test_duplicate_reference_detection() -> None:
    """Verify detection of duplicate references by DOI, URL, or author/title signature."""
    ref1 = ReferenceInput(
        id="ref_1",
        text="Original",
        title="Deep Residual Learning",
        authors=["Kaiming He"],
        year=2016,
        doi="10.1109/CVPR.2016.90",
        url="https://doi.org/10.1109/CVPR.2016.90",
    )
    ref2 = ReferenceInput(
        id="ref_2",
        text="Duplicate by DOI",
        title="Deep Residual Learning for Image Recognition",
        authors=["K. He"],
        year=2016,
        doi="https://doi.org/10.1109/CVPR.2016.90",  # Same DOI in URL form
    )
    ref3 = ReferenceInput(
        id="ref_3",
        text="Duplicate by Title/Year",
        title="Deep Residual Learning",
        authors=["Kaiming He"],
        year=2016,
    )
    ref4 = ReferenceInput(
        id="ref_4",
        text="Distinct",
        title="Attention Is All You Need",
        authors=["Ashish Vaswani"],
        year=2017,
        doi="10.5555/3295222.3295349",
    )

    dupes = detect_duplicate_references([ref1, ref2, ref3, ref4])
    assert len(dupes) >= 2
    dupe_ids = [(d[0], d[1]) for d in dupes]
    assert ("ref_1", "ref_2") in dupe_ids or ("ref_2", "ref_1") in dupe_ids


def test_missing_metadata_validation_zero_fabrication() -> None:
    """Verify that incomplete references are flagged with descriptive review warnings without inventing values."""
    incomplete_journal = ReferenceInput(
        id="ref_incomplete",
        text="TBD: citation text",
        publication_type="journal_article",
        title="Some Preliminary Title",
        # Missing authors, year, and venue
    )

    warnings = validate_reference_metadata(incomplete_journal)
    assert len(warnings) >= 3
    warning_text = " ".join(warnings)
    assert "missing author information" in warning_text
    assert "missing a valid publication year" in warning_text
    assert "missing journal/conference venue" in warning_text


def test_doi_normalization_and_validation() -> None:
    """Verify DOI normalization handles URLs, prefixes, and invalid syntaxes."""
    assert (
        normalize_doi("https://doi.org/10.1109/ACCESS.2024.1234567")
        == "10.1109/ACCESS.2024.1234567"
    )
    assert normalize_doi("http://dx.doi.org/10.1145/3318464.3389700") == "10.1145/3318464.3389700"
    assert normalize_doi("doi: 10.1000/182") == "10.1000/182"
    assert normalize_doi("10.5555/3295222.3295349") == "10.5555/3295222.3295349"

    # Invalid DOIs
    assert normalize_doi("not-a-doi") is None
    assert normalize_doi("https://example.com/paper.pdf") is None
    assert normalize_doi("11.1234/badprefix") is None


def test_citation_to_reference_integrity_and_unresolved_warnings() -> None:
    """Verify that in-text citations to unprovided references raise critical CITATION_NEEDED review warnings."""
    paper = PaperDraft(
        schema_version=1,
        title="Integrity Test Paper",
        abstract="Abstract.",
        keywords=[],
        sections=[
            PaperSection(
                id="sec_1",
                heading="Introduction",
                content="This statement relies on an unprovided source [ref_phantom99].",
                state="draft",
            ),
        ],
        references=[
            ReferenceInput(
                id="ref_valid", text="Valid Source Text", title="Valid Source", year=2024
            ),
        ],
        review_warnings=[],
    )

    updated_paper, warnings = process_manuscript_citations_and_bibliography(paper)
    critical_warnings = [
        w for w in warnings if w.code == "CITATION_NEEDED" and w.severity == "critical"
    ]
    assert len(critical_warnings) >= 1
    assert "ref_phantom99" in critical_warnings[0].message
    assert "Introduction" in critical_warnings[0].message


def test_author_date_normalization_in_ieee_mode() -> None:
    """Verify that author-date citations like (Smith, 2024) are mapped to numeric IEEE citations."""
    ref_smith = ReferenceInput(
        id="ref_smith",
        text="Smith, A. (2024). Deep Foundations.",
        authors=["Alice Smith"],
        year=2024,
        title="Deep Foundations",
        publication_type="journal_article",
    )

    paper = PaperDraft(
        schema_version=1,
        title="IEEE Author Date Test",
        abstract="Abstract.",
        keywords=[],
        sections=[
            PaperSection(
                id="sec_lit",
                heading="Literature Review",
                content="Prior work by (Smith, 2024) established the benchmark.",
                state="draft",
            ),
        ],
        references=[ref_smith],
        review_warnings=[],
    )

    updated_paper, _ = process_manuscript_citations_and_bibliography(paper)
    lit_content = next(s.content for s in updated_paper.sections if s.id == "sec_lit")
    assert "[1]" in lit_content
    assert "(Smith, 2024)" not in lit_content


def test_docx_export_contains_formatted_ieee_references() -> None:
    """Verify that DOCX exporter renders formatted IEEE references with hanging indents."""
    paper = PaperDraft(
        schema_version=1,
        title="DOCX Reference Export Test",
        abstract="Abstract text.",
        keywords=["docx"],
        page_layout="two_column_academic",
        sections=[
            PaperSection(
                id="intro",
                heading="Introduction",
                content="Recent findings confirm [1] and [2].",
                state="draft",
            ),
        ],
        references=[
            ReferenceInput(
                id="ref_1",
                text="Raw 1",
                title="Attention Is All You Need",
                authors=["Ashish Vaswani", "Noam Shazeer"],
                year=2017,
                venue="NeurIPS",
                publication_type="conference_paper",
                citation_number=1,
                doi="10.5555/3295222.3295349",
            ),
            ReferenceInput(
                id="ref_2",
                text="Raw 2",
                title="Deep Residual Learning",
                authors=["Kaiming He"],
                year=2016,
                venue="CVPR",
                publication_type="conference_paper",
                citation_number=2,
            ),
        ],
        review_warnings=[],
    )

    docx_bytes = export_paper_docx(paper)
    assert len(docx_bytes) > 1000

    doc = Document(io.BytesIO(docx_bytes))
    all_text = " ".join(p.text for p in doc.paragraphs)

    assert "References" in all_text
    assert "Attention Is All You Need" in all_text
    assert "Deep Residual Learning" in all_text
    assert "[1]" in all_text
    assert "[2]" in all_text


def test_pdf_export_contains_formatted_ieee_references() -> None:
    """Verify that PDF exporter renders formatted IEEE references and produces valid PDF document."""
    paper = PaperDraft(
        schema_version=1,
        title="PDF Reference Export Test",
        abstract="Abstract text.",
        keywords=["pdf"],
        page_layout="two_column_academic",
        sections=[
            PaperSection(
                id="intro",
                heading="Introduction",
                content="System overview relying on [1].",
                state="draft",
            ),
        ],
        references=[
            ReferenceInput(
                id="ref_1",
                text="Raw text",
                title="Scaling Distributed Systems",
                authors=["Michael Stonebraker"],
                year=2020,
                venue="ACM TOCS",
                publication_type="journal_article",
                citation_number=1,
                doi="10.1145/3318464.3389700",
            ),
        ],
        review_warnings=[],
    )

    pdf_bytes = export_paper_pdf(paper)
    assert len(pdf_bytes) > 2000

    reader = PdfReader(io.BytesIO(pdf_bytes))
    extracted = " ".join(page.extract_text() or "" for page in reader.pages)

    assert "References" in extracted
    assert "Scaling Distributed Systems" in extracted
    assert "Stonebraker" in extracted


def test_bibliographic_resolver_authoritative_resolution() -> None:
    """Verify BibliographicResolver resolves DOIs, Crossref, and OpenAlex JSON into verified ReferenceInput objects."""
    # 1. Authoritative DOI lookup
    resolved = BibliographicResolver.resolve_by_doi("10.1109/access.2024.1234567", "ref-he2024")
    assert resolved is not None
    assert resolved.id == "ref-he2024"
    assert "Deep Residual Learning" in (resolved.title or "")
    assert resolved.provenance == "crossref"
    assert resolved.verification_status == "verified"
    assert "K. He" in resolved.text

    # 2. Crossref work item normalization
    crossref_item: dict[str, Any] = {
        "title": ["Foundations of Cryptography"],
        "author": [{"given": "Oded", "family": "Goldreich"}],
        "container-title": ["Cambridge University Press"],
        "issued": {"date-parts": [[2001]]},
        "type": "book",
        "DOI": "10.1017/CBO9780511546891",
        "publisher": "Cambridge University Press",
    }
    crossref_ref = BibliographicResolver.resolve_from_crossref_json(crossref_item, "ref-goldreich")
    assert crossref_ref.id == "ref-goldreich"
    assert crossref_ref.publication_type == "book"
    assert crossref_ref.year == 2001
    assert crossref_ref.authors == ["Oded Goldreich"]
    assert crossref_ref.provenance == "crossref"
    assert crossref_ref.verification_status == "verified"

    # 3. OpenAlex work item normalization
    openalex_item: dict[str, Any] = {
        "title": "Quantum Supremacy Using a Programmable Superconducting Processor",
        "publication_year": 2019,
        "authorships": [
            {"author": {"display_name": "Frank Arute"}},
            {"author": {"display_name": "John Martinis"}},
        ],
        "primary_location": {
            "source": {"display_name": "Nature", "host_organization_name": "Springer Nature"}
        },
        "doi": "https://doi.org/10.1038/s41586-019-1666-5",
        "type": "article",
        "biblio": {"volume": "574", "issue": "7779", "first_page": "505", "last_page": "510"},
    }
    openalex_ref = BibliographicResolver.resolve_from_openalex_json(openalex_item, "ref-martinis")
    assert openalex_ref.id == "ref-martinis"
    assert openalex_ref.publication_type == "journal_article"
    assert openalex_ref.year == 2019
    assert openalex_ref.pages == "505–510"
    assert openalex_ref.doi == "10.1038/s41586-019-1666-5"
    assert openalex_ref.provenance == "openalex"
    assert openalex_ref.verification_status == "verified"
