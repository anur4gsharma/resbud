from __future__ import annotations

import io
from typing import Any

import docx
from fastapi.testclient import TestClient

from resbud_api.core.settings import Settings
from resbud_api.main import create_app
from resbud_api.providers.fake import FakeProvider


def _test_app() -> TestClient:
    settings = Settings(environment="test", generation_provider="fake", _env_file=None)
    app = create_app(settings, generation_provider=FakeProvider())
    return TestClient(app)


def test_backend_end_to_end_vertical_slice_generation_to_docx_parsing() -> None:
    """Verify complete vertical API cycle: generation -> regen -> DOCX export -> parsing."""
    client = _test_app()

    # 1. Health checks
    live_resp = client.get("/health/live")
    assert live_resp.status_code == 200
    assert live_resp.json() == {"status": "alive"}

    ready_resp = client.get("/health/ready")
    assert ready_resp.status_code == 200
    assert ready_resp.json() == {"status": "ready"}

    # 2. POST /api/v1/generations with structured context
    generation_payload: dict[str, Any] = {
        "schema_version": 1,
        "project": {
            "title": "Deep Neural Architectures for Multimodal Medical Diagnosis",
            "research_field": "Artificial Intelligence in Medicine",
            "research_question": "Can attention-gated transformers improve diagnostic precision?",
            "objectives": [
                "Evaluate diagnostic precision across multicenter tissue cohorts",
                "Measure computational efficiency and model interpretability",
            ],
            "claimed_contribution": "A cross-attention gating mechanism for histology imaging.",
            "methodology_status": "provided",
            "methodology": "Retrospective cohort study using 5-fold cross-validation.",
            "dataset_or_materials_status": "provided",
            "dataset_or_materials": "TCGA and Camelyon16 public histopathology datasets.",
            "results_status": "not_collected",
            "results": None,
            "limitations_status": "provided",
            "limitations": "Single hardware architecture evaluation.",
        },
        "source_draft": (
            "We present a deep learning architecture for whole-slide imaging. "
            "Our model uses cross-attention gating to highlight malignant morphological features. "
            "Preliminary validation indicates high agreement with board-certified pathologists."
        ),
        "references": [
            {
                "id": "ref_1",
                "text": "Vaswani, A. et al. (2017). Attention is all you need. NeurIPS, 30.",
            },
            {
                "id": "ref_2",
                "text": "Esteva, A. et al. (2017). Dermatologist classification. Nature, 542.",
            },
        ],
        "preferences": {
            "target_word_count": 2000,
            "desired_sections": [
                "abstract",
                "introduction",
                "methodology",
                "results",
                "discussion",
                "conclusion",
            ],
            "citation_style": "apa_7",
        },
    }

    gen_response = client.post("/api/v1/generations", json=generation_payload)
    assert gen_response.status_code == 200, gen_response.text
    gen_data = gen_response.json()

    assert gen_data["schema_version"] == 1
    assert "generation_id" in gen_data
    assert gen_data["meta"]["provider_name"] == "fake"
    assert gen_data["meta"]["duration_ms"] >= 0

    paper = gen_data["paper"]
    assert paper["title"] != ""
    assert paper["abstract"] != ""
    assert len(paper["sections"]) >= 4
    section_ids = [s["id"] for s in paper["sections"]]
    assert "methodology" in section_ids
    assert "results" in section_ids

    # Notice results was not_collected, so results warning is present
    warning_codes = [w["code"] for w in gen_data["review_warnings"]]
    has_results_warning = "EXPLICIT_NOT_COLLECTED_RESULTS" in warning_codes or any(
        "RESULTS" in c for c in warning_codes
    )
    assert has_results_warning

    # 3. Section regeneration: POST /api/v1/generations/sections
    regen_payload: dict[str, Any] = {
        "schema_version": 1,
        "generation_request": generation_payload,
        "current_paper": paper,
        "section_id": "methodology",
        "user_instruction": "Detail stain normalization steps and GPU hyper-parameters.",
    }

    regen_response = client.post("/api/v1/generations/sections", json=regen_payload)
    assert regen_response.status_code == 200, regen_response.text
    regen_data = regen_response.json()

    replacement_section = regen_data["section"]
    assert replacement_section["id"] == "methodology"
    assert replacement_section["content"] != ""

    # 4. Update the paper with the regenerated section and export to DOCX
    updated_sections = []
    for sec in paper["sections"]:
        if sec["id"] == "methodology":
            updated_sections.append(replacement_section)
        else:
            updated_sections.append(sec)

    updated_paper = dict(paper)
    updated_paper["sections"] = updated_sections

    export_response = client.post(
        "/api/v1/exports/docx",
        json=updated_paper,
    )
    assert export_response.status_code == 200
    assert (
        export_response.headers["content-type"]
        == "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    )
    assert "attachment; filename=" in export_response.headers.get("content-disposition", "")
    docx_bytes = export_response.content
    assert len(docx_bytes) > 500

    # 5. Parse the generated DOCX in-memory with python-docx and verify document integrity
    doc = docx.Document(io.BytesIO(docx_bytes))
    full_text = "\n".join([p.text for p in doc.paragraphs])

    assert updated_paper["title"] in full_text
    assert "Abstract" in full_text
    assert updated_paper["abstract"] in full_text
    assert "Methodology" in full_text
    assert replacement_section["content"] in full_text
    assert "References" in full_text
    assert "Vaswani, A." in full_text


def test_backend_error_boundaries_and_rejections() -> None:
    """Verify API boundaries reject malformed requests with stable structured errors."""
    client = _test_app()

    # Malformed generation request (missing required project fields)
    bad_gen = client.post("/api/v1/generations", json={"schema_version": 1, "project": {}})
    assert bad_gen.status_code == 422
    err_json = bad_gen.json()
    assert err_json["code"] == "VALIDATION_ERROR"
    assert err_json["status"] == 422

    # Unknown section in regeneration
    bad_regen = client.post(
        "/api/v1/generations/sections",
        json={
            "schema_version": 1,
            "generation_request": {
                "schema_version": 1,
                "project": {
                    "title": "Title",
                    "research_field": "Field",
                    "research_question": "Question?",
                    "objectives": ["Obj1"],
                    "methodology_status": "unknown",
                    "dataset_or_materials_status": "unknown",
                    "results_status": "unknown",
                    "limitations_status": "unknown",
                },
                "source_draft": "Draft text here.",
                "references": [],
                "preferences": {
                    "target_word_count": 1000,
                    "desired_sections": ["intro"],
                    "citation_style": "apa_7",
                },
            },
            "current_paper": {
                "schema_version": 1,
                "title": "Title",
                "abstract": "Abstract",
                "keywords": ["test"],
                "sections": [
                    {"id": "intro", "heading": "Intro", "content": "Text", "state": "draft"}
                ],
                "references": [],
                "review_warnings": [],
            },
            "section_id": "nonexistent_section",
            "user_instruction": "",
        },
    )
    assert bad_regen.status_code == 422
    assert bad_regen.json()["code"] == "VALIDATION_ERROR"

    # Malformed paper export
    bad_export = client.post(
        "/api/v1/exports/docx",
        json={"schema_version": 1, "title": ""},
    )
    assert bad_export.status_code == 422
    assert bad_export.json()["code"] == "VALIDATION_ERROR"
