"""DOCX export API tests that reopen the returned binary with python-docx."""

import asyncio
import copy
import json
from io import BytesIO
from pathlib import Path
from typing import Any

import httpx
import pytest
from docx import Document
from fastapi import FastAPI

from resbud_api.core.settings import Settings
from resbud_api.main import create_app

FIXTURES = Path(__file__).parent / "fixtures"
PAPER = json.loads((FIXTURES / "paper-draft.valid.json").read_text())


def _request(app: FastAPI, body: object) -> httpx.Response:
    async def send_request() -> httpx.Response:
        transport = httpx.ASGITransport(app=app, raise_app_exceptions=False)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            return await client.post("/api/v1/exports/docx", json=body)

    return asyncio.run(send_request())


def _app() -> FastAPI:
    return create_app(Settings(environment="test", _env_file=None))


def test_export_returns_reopenable_docx_in_paper_order_with_safe_headers() -> None:
    paper = copy.deepcopy(PAPER)
    paper["abstract"] = "First abstract line.\nSecond abstract line."
    paper["sections"].reverse()
    response = _request(_app(), paper)

    assert response.status_code == 200
    assert response.headers["content-type"] == (
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    )
    assert (
        response.headers["content-disposition"]
        == 'attachment; filename="resbud-example-study.docx"'
    )
    assert response.headers["x-request-id"]
    assert response.content.startswith(b"PK")

    document = Document(BytesIO(response.content))
    paragraphs = document.paragraphs
    texts = [paragraph.text for paragraph in paragraphs]
    assert texts == [
        "Example Study",
        "Abstract",
        "First abstract line.\nSecond abstract line.",
        "Keywords",
        "workflow, evaluation",
        "Results",
        "[INSERT EXPERIMENTAL RESULTS]",
        "Introduction",
        "A draft section.",
        "References",
        "  Example Author. (2025). Example title.  ",
    ]
    assert paragraphs[0].style.name == "Title"
    assert paragraphs[1].style.name == "Heading 1"
    assert paragraphs[5].style.name == "Heading 1"


def test_export_is_present_in_generated_openapi_contract() -> None:
    operation = _app().openapi()["paths"]["/api/v1/exports/docx"]["post"]

    assert operation["operationId"] == "exportDocx"
    assert (
        operation["responses"]["200"]["content"][
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        ]["schema"]["format"]
        == "binary"
    )


def test_export_filename_strips_path_control_and_non_ascii_characters() -> None:
    paper = copy.deepcopy(PAPER)
    paper["title"] = '../Café "results"\r\n'

    response = _request(_app(), paper)

    assert response.status_code == 200
    assert (
        response.headers["content-disposition"] == 'attachment; filename="resbud-cafe-results.docx"'
    )
    assert "/" not in response.headers["content-disposition"]
    assert "\r" not in response.headers["content-disposition"]
    assert "\n" not in response.headers["content-disposition"]


def test_malformed_paper_is_rejected_with_stable_validation_error() -> None:
    paper = copy.deepcopy(PAPER)
    paper.pop("title")

    response = _request(_app(), paper)

    assert response.status_code == 422
    assert response.json()["code"] == "VALIDATION_ERROR"
    assert response.headers["x-request-id"] == response.json()["request_id"]


def test_document_generation_failure_returns_safe_stable_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    import resbud_api.services.docx_export as exporter

    def fail(_paper: object) -> Any:
        raise RuntimeError("private document content or path")

    monkeypatch.setattr(exporter, "_create_document", fail)
    response = _request(_app(), PAPER)

    assert response.status_code == 500
    assert response.json()["code"] == "INTERNAL_ERROR"
    assert "private document content" not in response.text
    assert response.headers["x-request-id"] == response.json()["request_id"]


def test_oversized_export_is_rejected_with_safe_error(monkeypatch: pytest.MonkeyPatch) -> None:
    import resbud_api.services.docx_export as exporter

    monkeypatch.setattr(exporter, "MAX_EXPORT_BYTES", 1)
    response = _request(_app(), PAPER)

    assert response.status_code == 413
    assert response.json()["code"] == "INPUT_TOO_LARGE"
