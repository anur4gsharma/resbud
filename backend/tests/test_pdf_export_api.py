"""PDF export API tests that reopen the returned binary with pypdf."""

import asyncio
import copy
import json
from io import BytesIO
from pathlib import Path
from typing import Any

import httpx
import pypdf
import pytest
from fastapi import FastAPI

from resbud_api.core.settings import Settings
from resbud_api.main import create_app

FIXTURES = Path(__file__).parent / "fixtures"
PAPER = json.loads((FIXTURES / "paper-draft.valid.json").read_text())


def _request(app: FastAPI, body: object) -> httpx.Response:
    async def send_request() -> httpx.Response:
        transport = httpx.ASGITransport(app=app, raise_app_exceptions=False)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            return await client.post("/api/v1/exports/pdf", json=body)

    return asyncio.run(send_request())


def _app() -> FastAPI:
    return create_app(Settings(environment="test", _env_file=None))


def test_export_returns_valid_pdf_with_safe_headers() -> None:
    paper = copy.deepcopy(PAPER)
    paper["abstract"] = "First abstract line.\nSecond abstract line."
    paper["sections"].reverse()
    response = _request(_app(), paper)

    assert response.status_code == 200
    assert response.headers["content-type"] == "application/pdf"
    assert (
        response.headers["content-disposition"] == 'attachment; filename="resbud-example-study.pdf"'
    )
    assert response.headers["x-request-id"]
    assert response.content.startswith(b"%PDF-")

    reader = pypdf.PdfReader(BytesIO(response.content))
    assert len(reader.pages) >= 1
    extracted_text = "\n".join(page.extract_text() or "" for page in reader.pages)
    assert "Example Study" in extracted_text
    assert "ABSTRACT" in extracted_text


def test_export_filename_strips_path_control_and_non_ascii_characters() -> None:
    paper = copy.deepcopy(PAPER)
    paper["title"] = '../Café "results"\r\n'
    response = _request(_app(), paper)

    assert response.status_code == 200
    assert (
        response.headers["content-disposition"] == 'attachment; filename="resbud-cafe-results.pdf"'
    )
    assert "/" not in response.headers["content-disposition"]
    assert "\r" not in response.headers["content-disposition"]
    assert "\n" not in response.headers["content-disposition"]


def test_export_pdf_with_tables_figures_and_latex() -> None:
    paper = copy.deepcopy(PAPER)
    paper["sections"][0]["content"] = (
        "Inline relation $E = mc^2$ in paragraph.\n\n"
        r"$$\sigma = \sqrt{\frac{1}{N}\sum_{i=1}^N (x_i - \mu)^2}$$"
        "\n\n"
        "| Architecture | Accuracy | Latency |\n"
        "| --- | --- | --- |\n"
        "| ResNet-50 | 76.1% | 4.2ms |\n"
        "| ViT-Base | 81.8% | 11.5ms |\n\n"
        "![Sample Architecture Schematic]("
        "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk"
        "+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==)\n\n"
        "Concluding remark."
    )
    response = _request(_app(), paper)

    assert response.status_code == 200
    assert response.content.startswith(b"%PDF-")

    reader = pypdf.PdfReader(BytesIO(response.content))
    assert len(reader.pages) >= 1
    extracted = "\n".join(page.extract_text() or "" for page in reader.pages)
    assert "ResNet-50" in extracted
    assert "Sample Architecture Schematic" in extracted


def test_pdf_malformed_paper_is_rejected_with_stable_validation_error() -> None:
    paper = copy.deepcopy(PAPER)
    paper.pop("title")

    response = _request(_app(), paper)

    assert response.status_code == 422
    assert response.json()["code"] == "VALIDATION_ERROR"
    assert response.headers["x-request-id"] == response.json()["request_id"]


def test_pdf_document_generation_failure_returns_safe_stable_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    import resbud_api.services.pdf_export as exporter

    def fail(_paper: object) -> Any:
        raise RuntimeError("private document content or path")

    monkeypatch.setattr(exporter, "_build_story", fail)
    response = _request(_app(), PAPER)

    assert response.status_code == 500
    assert response.json()["code"] == "INTERNAL_ERROR"
    assert "private document content" not in response.text
    assert response.headers["x-request-id"] == response.json()["request_id"]


def test_pdf_oversized_export_is_rejected_with_safe_error(monkeypatch: pytest.MonkeyPatch) -> None:
    import resbud_api.services.pdf_export as exporter

    monkeypatch.setattr(exporter, "MAX_EXPORT_BYTES", 1)
    response = _request(_app(), PAPER)

    assert response.status_code == 413
    assert response.json()["code"] == "INPUT_TOO_LARGE"


def test_pdf_renders_declarative_chart_block() -> None:
    paper = copy.deepcopy(PAPER)
    paper["sections"][0]["content"] = (
        "Preliminary observation.\n\n"
        "```chart\n"
        "type: bar\n"
        "title: Comparative Throughput\n"
        "labels: [Base, Optimized, Ours]\n"
        "values: [120, 240, 480]\n"
        "ylabel: Req/sec\n"
        "```\n\n"
        "Concluding observation."
    )
    response = _request(_app(), paper)

    assert response.status_code == 200
    assert response.content.startswith(b"%PDF-")
    reader = pypdf.PdfReader(BytesIO(response.content))
    assert len(reader.pages) >= 1
