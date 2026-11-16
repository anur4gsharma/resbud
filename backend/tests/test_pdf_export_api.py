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


def test_two_column_academic_pdf_export_structure() -> None:
    paper = copy.deepcopy(PAPER)
    paper["page_layout"] = "two_column_academic"
    paper["author_info"] = "Dr. Jane Doe and Dr. John Smith"
    paper["affiliation"] = "Department of Computer Science, University of Technology"
    paper["keywords"] = ["Neural Networks", "Optimization", "High Performance Computing"]
    paper["sections"].append(
        {
            "id": "methodology",
            "heading": "Methodology",
            "state": "draft",
            "content": (
                "We propose a novel framework for distributed processing.\n\n"
                r"$$\mathcal{L}_{total} = \alpha \mathcal{L}_{MSE} + \beta \mathcal{L}_{KL}$$"
                "\n\n"
                "| Architecture | Parameter Count | Top-1 Accuracy |\n"
                "| --- | --- | --- |\n"
                "| ResNet-18 | 11.7M | 69.8% |\n"
                "| ResNet-50 | 25.6M | 76.1% |\n\n"
                "Concluding observation on convergence stability."
            ),
        }
    )

    response = _request(_app(), paper)
    assert response.status_code == 200
    assert response.content.startswith(b"%PDF-")

    reader = pypdf.PdfReader(BytesIO(response.content))
    assert len(reader.pages) >= 1
    extracted_text = "\n".join(page.extract_text() or "" for page in reader.pages)
    assert "Example Study" in extracted_text
    assert "Dr. Jane Doe and Dr. John Smith" in extracted_text
    assert "University of Technology" in extracted_text
    assert "Abstract" in extracted_text
    assert "Index Terms" in extracted_text
    assert "Neural Networks" in extracted_text
    assert "ResNet-50" in extracted_text


def test_two_column_academic_pdf_export_via_query_param() -> None:
    async def request_with_query() -> httpx.Response:
        transport = httpx.ASGITransport(app=_app(), raise_app_exceptions=False)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            return await client.post("/api/v1/exports/pdf?layout=two_column_academic", json=PAPER)

    response = asyncio.run(request_with_query())
    assert response.status_code == 200
    assert response.content.startswith(b"%PDF-")
    reader = pypdf.PdfReader(BytesIO(response.content))
    assert len(reader.pages) >= 1


@pytest.mark.parametrize("citation_style", ["apa_7", "ieee", "user_supplied", "other"])
def test_two_column_academic_pdf_independent_of_citation_style(citation_style: str) -> None:
    paper = copy.deepcopy(PAPER)
    paper["page_layout"] = "two_column_academic"
    paper["references"] = [
        {
            "id": "ref_1",
            "text": f"Author, A. (2024). Foundational Study in {citation_style} format.",
        }
    ]
    response = _request(_app(), paper)
    assert response.status_code == 200
    reader = pypdf.PdfReader(BytesIO(response.content))
    extracted = "\n".join(page.extract_text() or "" for page in reader.pages)
    assert "References" in extracted
    assert "Foundational Study" in extracted


def test_two_column_academic_pdf_with_no_references() -> None:
    paper = copy.deepcopy(PAPER)
    paper["page_layout"] = "two_column_academic"
    paper["references"] = []
    response = _request(_app(), paper)
    assert response.status_code == 200
    reader = pypdf.PdfReader(BytesIO(response.content))
    assert len(reader.pages) >= 1


def test_pdf_export_with_various_figure_formats() -> None:
    import base64

    from PIL import Image

    def _make_b64(fmt: str, mode: str = "RGB") -> str:
        im = Image.new(mode, (120, 90), color=(50, 100, 150))
        buf = BytesIO()
        im.save(buf, format=fmt)
        return (
            "data:image/"
            + fmt.lower()
            + ";base64,"
            + base64.b64encode(buf.getvalue()).decode("ascii")
        )

    png_b64 = _make_b64("PNG", "RGBA")
    webp_b64 = _make_b64("WEBP")
    bmp_b64 = _make_b64("BMP")
    jpg_b64 = _make_b64("JPEG")

    paper = copy.deepcopy(PAPER)
    paper["sections"][0]["content"] = (
        "Evaluation of multi-format figure rendering:\n\n"
        f"![Figure 1: Transparent PNG Architecture]({png_b64})\n\n"
        f"![Figure 2: WebP Compression Results]({webp_b64})\n\n"
        f"![Figure 3: Standard Bitmap Topology]({bmp_b64})\n\n"
        f"![Figure 4: Baseline JPEG Photo]({jpg_b64})\n\n"
        "All figures embedded successfully."
    )

    response = _request(_app(), paper)
    assert response.status_code == 200
    assert response.content.startswith(b"%PDF-")

    reader = pypdf.PdfReader(BytesIO(response.content))
    extracted = "\n".join(page.extract_text() or "" for page in reader.pages)
    assert "Figure 1: Transparent PNG Architecture" in extracted
    assert "Figure 2: WebP Compression Results" in extracted
    assert "Figure 3: Standard Bitmap Topology" in extracted
    assert "Figure 4: Baseline JPEG Photo" in extracted


def test_pdf_export_with_tight_and_inline_figures() -> None:
    import base64

    from PIL import Image

    im = Image.new("RGB", (80, 80), color="blue")
    buf = BytesIO()
    im.save(buf, format="PNG")
    b64 = "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode("ascii")

    paper = copy.deepcopy(PAPER)
    paper["sections"][0]["content"] = (
        "Prose before tight figure.\n"
        f"![Figure 1: Tight Line Diagram]({b64})\n"
        "Prose after tight figure, and inline "
        f"![Figure 2: Inline Diagram]({b64}) within text flow."
    )

    response = _request(_app(), paper)
    assert response.status_code == 200
    reader = pypdf.PdfReader(BytesIO(response.content))
    extracted = "\n".join(page.extract_text() or "" for page in reader.pages)
    assert "Figure 1: Tight Line Diagram" in extracted
    assert "Figure 2: Inline Diagram" in extracted


def test_pdf_export_with_corrupt_figure_recovers_gracefully() -> None:
    paper = copy.deepcopy(PAPER)
    paper["sections"][0]["content"] = (
        "Preliminary observation.\n\n"
        "![Figure 1: Corrupted Data](data:image/png;base64,not-valid-base64-data-at-all)\n\n"
        "Subsequent narrative."
    )

    response = _request(_app(), paper)
    assert response.status_code == 200
    reader = pypdf.PdfReader(BytesIO(response.content))
    extracted = "\n".join(page.extract_text() or "" for page in reader.pages)
    assert "Figure 1: Corrupted Data" in extracted


def test_pdf_export_review_notes_appendix_disabled_strips_editorial_notes() -> None:
    paper = copy.deepcopy(PAPER)
    paper["sections"][0]["content"] = (
        "The model achieves state-of-the-art results [1] and [1-3] across parameter range [0, 1].\n\n"
        "[Note: Specific experimental results were not provided in the prompt.]\n\n"
        "[Methodological Scope Note: Further empirical expansion is constrained due to lack of dataset.]\n\n"
        "The experimental evaluation has not yet been conducted."
    )

    async def request_no_notes() -> httpx.Response:
        transport = httpx.ASGITransport(app=_app(), raise_app_exceptions=False)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            return await client.post(
                "/api/v1/exports/pdf?include_review_notes_appendix=false", json=paper
            )

    response = asyncio.run(request_no_notes())
    assert response.status_code == 200
    reader = pypdf.PdfReader(BytesIO(response.content))
    extracted = "\n".join(page.extract_text() or "" for page in reader.pages)

    # Bracketed editorial notes must be stripped
    assert "Specific experimental results were not provided in the prompt" not in extracted
    assert "Further empirical expansion is constrained" not in extracted
    assert "Author Review Notes" not in extracted

    # Academic citations, math brackets, and factual prose must be preserved
    assert "[1]" in extracted
    assert "[1-3]" in extracted
    assert "[0, 1]" in extracted
    assert "The experimental evaluation has not yet been conducted." in extracted


def test_pdf_export_review_notes_appendix_enabled_adds_appendix() -> None:
    paper = copy.deepcopy(PAPER)
    paper["review_warnings"] = [
        {
            "code": "MISSING_RESULTS",
            "severity": "warning",
            "message": "Empirical validation dataset was not provided.",
            "section_id": paper["sections"][0]["id"],
        }
    ]
    paper["sections"][0]["content"] = (
        "Preliminary discussion citing [1].\n\n"
        "[Note: Specific experimental results were not provided in the prompt.]\n\n"
        "Prose narrative continues."
    )

    async def request_with_notes() -> httpx.Response:
        transport = httpx.ASGITransport(app=_app(), raise_app_exceptions=False)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            return await client.post(
                "/api/v1/exports/pdf?include_review_notes_appendix=true", json=paper
            )

    response = asyncio.run(request_with_notes())
    assert response.status_code == 200
    reader = pypdf.PdfReader(BytesIO(response.content))
    extracted = "\n".join(page.extract_text() or "" for page in reader.pages)

    # Author Review Notes appendix must be present with unresolved notes
    assert "Author Review Notes" in extracted
    assert "Empirical validation dataset was not provided." in extracted
    assert "Specific experimental results were not provided" in extracted


def test_pdf_export_with_placement_metadata_and_diverse_formats() -> None:
    import base64

    from PIL import Image

    # 1. PNG
    im_png = Image.new("RGBA", (120, 90), color=(255, 0, 0, 180))
    buf_png = BytesIO()
    im_png.save(buf_png, format="PNG")
    b64_png = "data:image/png;base64," + base64.b64encode(buf_png.getvalue()).decode("ascii")

    # 2. JPEG
    im_jpg = Image.new("RGB", (160, 100), color=(0, 200, 0))
    buf_jpg = BytesIO()
    im_jpg.save(buf_jpg, format="JPEG")
    b64_jpg = "data:image/jpeg;base64," + base64.b64encode(buf_jpg.getvalue()).decode("ascii")

    # 3. WebP
    im_webp = Image.new("RGB", (100, 100), color=(0, 0, 220))
    buf_webp = BytesIO()
    im_webp.save(buf_webp, format="WEBP")
    b64_webp = "data:image/webp;base64," + base64.b64encode(buf_webp.getvalue()).decode("ascii")

    paper = copy.deepcopy(PAPER)
    paper["sections"][0]["content"] = (
        "Preliminary discussion.\n\n"
        f"![Figure 1: Full Width System Architecture]({b64_png}#placement=full_width)\n\n"
        "Intermediate discussion between figures.\n\n"
        f"![Figure 2: Column Width Apparatus]({b64_jpg}#placement=column_width)\n\n"
        f"![Figure 3: WebP Empirical Chart]({b64_webp})\n\n"
        "Final remarks."
    )

    # Test single-column PDF
    response_single = _request(_app(), paper)
    assert response_single.status_code == 200
    assert response_single.content.startswith(b"%PDF-")
    reader_single = pypdf.PdfReader(BytesIO(response_single.content))
    text_single = "\n".join(page.extract_text() or "" for page in reader_single.pages)
    assert "Figure 1: Full Width System Architecture" in text_single
    assert "Figure 2: Column Width Apparatus" in text_single
    assert "Figure 3: WebP Empirical Chart" in text_single

    # Test two-column IEEE format PDF
    async def request_two_col() -> httpx.Response:
        transport = httpx.ASGITransport(app=_app(), raise_app_exceptions=False)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            return await client.post("/api/v1/exports/pdf?layout=two_column_academic", json=paper)

    response_two_col = asyncio.run(request_two_col())
    assert response_two_col.status_code == 200
    assert response_two_col.content.startswith(b"%PDF-")
    reader_two_col = pypdf.PdfReader(BytesIO(response_two_col.content))
    text_two_col = "\n".join(page.extract_text() or "" for page in reader_two_col.pages)
    assert "Figure 1: Full Width System Architecture" in text_two_col
    assert "Figure 2: Column Width Apparatus" in text_two_col
    assert "Figure 3: WebP Empirical Chart" in text_two_col
