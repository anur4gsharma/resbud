"""Tests for dynamic research analysis, quality assessment, and document extraction."""

import asyncio
from io import BytesIO
from pathlib import Path

import httpx
import pytest
from docx import Document
from pypdf import PdfWriter

from resbud_api.core.settings import Settings
from resbud_api.domain.models import ResearchAnalysisRequest
from resbud_api.main import create_app
from resbud_api.providers.fake import FakeProvider
from resbud_api.services.analysis import assess_research_quality, extract_document_text
from resbud_api.services.docx_export import get_format_specifier_reference_path


def _app():
    return create_app(
        Settings(environment="test", _env_file=None),
        generation_provider=FakeProvider(),
    )


def test_format_specifier_reference_path_handles_absence_gracefully():
    path = get_format_specifier_reference_path()
    assert path is None or isinstance(path, Path)


def test_extract_txt_and_md():
    content = "# Research Title\n\nThis is a sample markdown draft."
    text, fmt = extract_document_text("notes.md", content.encode("utf-8"))
    assert fmt == "text"
    assert "Research Title" in text

    text_txt, fmt_txt = extract_document_text("sample.txt", b"Plain text content")
    assert fmt_txt == "text"
    assert "Plain text content" in text_txt


def test_extract_empty_and_corrupted():
    with pytest.raises(Exception) as exc_info:
        extract_document_text("empty.txt", b"")
    assert "empty" in str(exc_info.value).lower()

    with pytest.raises(Exception) as exc_info:
        extract_document_text("corrupted.pdf", b"Not a real PDF file content")
    assert "corrupted" in str(exc_info.value).lower() or "malformed" in str(exc_info.value).lower()


def test_extract_docx_in_memory():
    doc = Document()
    doc.add_heading("Quantum Decoherence In Superconductors", level=0)
    doc.add_paragraph("Empirical measurements across fluxonium qubits.")
    buf = BytesIO()
    doc.save(buf)
    docx_bytes = buf.getvalue()

    text, fmt = extract_document_text("experiment.docx", docx_bytes)
    assert fmt == "docx"
    assert "Quantum Decoherence In Superconductors" in text
    assert "fluxonium qubits" in text


def test_extract_pdf_in_memory():
    writer = PdfWriter()
    writer.add_blank_page(width=200, height=200)
    buf = BytesIO()
    writer.write(buf)
    pdf_bytes = buf.getvalue()

    with pytest.raises(Exception) as exc_info:
        extract_document_text("blank.pdf", pdf_bytes)
    err = str(exc_info.value).lower()
    assert "empty" in err or "no readable text" in err


def test_analysis_scenario_1_complete_research():
    text = (
        "# Graph Neural Networks for Quantum Chemistry\n\n"
        "Research Question: Can equivariant message passing predict molecular energies?\n\n"
        "Methodology: We employ equivariant message passing with spherical harmonics.\n\n"
        "Dataset: Evaluated on QM9 dataset consisting of 134k organic molecules.\n\n"
        "Results: Our model achieves DFT accuracy with mean absolute error of 0.012 eV.\n\n"
        "References:\n"
        "[1] Gilmer et al., 2017. Neural Message Passing for Quantum Chemistry.\n"
    )
    req = ResearchAnalysisRequest(source_material=text)
    resp = assess_research_quality(req)

    assert resp.can_proceed_directly is True
    assert resp.requires_clarification is False
    assert len(resp.suggested_outline) >= 4
    outline_ids = [s.id for s in resp.suggested_outline]
    assert "introduction" in outline_ids
    assert any("equivariant" in s.id or "molecular" in s.id for s in resp.suggested_outline)
    assert len(resp.extracted_references) >= 1


def test_analysis_scenario_2_incomplete_research():
    text = (
        "# Attention Mechanisms in Transformer Encoders\n\n"
        "The prototype evaluates scaled dot-product attention.\n"
        "Results: Accuracy is 94%.\n"
        "Experimental results are not collected on noisy test environments.\n"
    )
    req = ResearchAnalysisRequest(source_material=text)
    resp = assess_research_quality(req)

    assert resp.requires_clarification is True
    assert len(resp.questions) > 0
    question_ids = [q.id for q in resp.questions]
    assert "q_methodology" in question_ids or "q_dataset" in question_ids
    warning_codes = [w.code for w in resp.warnings]
    assert "MISSING_RESULTS" in warning_codes or "MISSING_DATASET_DETAILS" in warning_codes


def test_analysis_scenario_3_incoherent_and_contradictory():
    text = (
        "# Transformer Optimization Study\n\n"
        "Earlier draft reports accuracy was 87%, but final run claims contradictory accuracy 91%.\n"
        "The model uses conflicting parameters that differ from reported benchmarks.\n"
    )
    req = ResearchAnalysisRequest(source_material=text)
    resp = assess_research_quality(req)

    assert resp.can_proceed_directly is False
    assert resp.requires_clarification is True
    warning_codes = [w.code for w in resp.warnings]
    assert "INPUT_CONFLICT" in warning_codes
    conflict_warning = next(w for w in resp.warnings if w.code == "INPUT_CONFLICT")
    assert conflict_warning.severity == "critical"
    assert conflict_warning.why_it_matters != ""
    assert conflict_warning.potential_impact != ""


def test_analysis_endpoint_integration():
    app = _app()

    async def run_call():
        transport = httpx.ASGITransport(app=app, raise_app_exceptions=False)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post(
                "/api/v1/analyze",
                json={
                    "source_material": (
                        "# Agricultural IoT Sensor Grid\n\n"
                        "We evaluate low-power wireless sensor nodes for soil moisture telemetry.\n"
                        "Methodology: Closed-loop feedback algorithm.\n"
                        "Dataset: 50 hectares trial plot over 90 days.\n"
                        "Results: 28% water reduction with equivalent crop yield.\n"
                    )
                },
            )
            assert resp.status_code == 200
            data = resp.json()
            assert data["inferred_title"] != ""
            assert len(data["suggested_outline"]) >= 4
            headings = [s["heading"] for s in data["suggested_outline"]]
            assert any("Sensor" in h or "Agricultural" in h or "Methodology" in h for h in headings)

    asyncio.run(run_call())
