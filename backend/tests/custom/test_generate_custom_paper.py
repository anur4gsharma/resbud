"""Custom paper generation test runner using user-provided JSON fields."""

import json
from pathlib import Path
from typing import Any

import httpx
from fastapi.testclient import TestClient
from pydantic import ValidationError

from resbud_api.core.settings import Settings
from resbud_api.domain.models import GenerationRequest, GenerationResponse
from resbud_api.main import create_app

CUSTOM_DIR = Path(__file__).parent
INPUT_FILE = CUSTOM_DIR / "request_input.json"
OUTPUT_JSON = CUSTOM_DIR / "output_paper.json"
OUTPUT_DOCX = CUSTOM_DIR / "output_paper.docx"


def load_user_input() -> dict[str, Any]:
    assert INPUT_FILE.exists(), f"Input file not found: {INPUT_FILE}"
    raw_text = INPUT_FILE.read_text(encoding="utf-8")
    data: dict[str, Any] = json.loads(raw_text)
    return data


def test_user_custom_paper_generation() -> None:
    """Validate user input fields, request generation, and export docx."""
    raw_input = load_user_input()

    # 1. Field validation
    try:
        validated_request = GenerationRequest.model_validate(raw_input)
    except ValidationError as err:
        print("\n❌ Input validation failed! Please check your fields in request_input.json:")
        print(err)
        raise

    print(f"\n✅ Input fields validated successfully for: '{validated_request.project.title}'")

    # 2. Execute request against running local server or in-memory application
    response_json: dict[str, Any]
    try:
        # Check if local server is already running on port 8000
        probe = httpx.get("http://127.0.0.1:8000/health/live", timeout=2.0)
        if probe.status_code == 200:
            print("📡 Sending request to live server at http://127.0.0.1:8000...")
            resp = httpx.post(
                "http://127.0.0.1:8000/api/v1/generations",
                json=raw_input,
                timeout=120.0,
            )
            assert resp.status_code == 200, f"API error ({resp.status_code}): {resp.text}"
            response_json = resp.json()
        else:
            raise httpx.ConnectError("Server not responding")
    except (httpx.ConnectError, httpx.TimeoutException):
        print("⚙️ Live server not reached, executing with local in-memory app...")
        app = create_app(Settings(_env_file=".env"))
        with TestClient(app) as client:
            resp = client.post("/api/v1/generations", json=raw_input)
            assert resp.status_code == 200, f"App error ({resp.status_code}): {resp.text}"
            response_json = resp.json()

    # 3. Validate generated response
    generation_result = GenerationResponse.model_validate(response_json)
    paper = generation_result.paper

    # Save output JSON
    OUTPUT_JSON.write_text(json.dumps(response_json, indent=2), encoding="utf-8")
    print(f"💾 Full generated paper JSON saved to: {OUTPUT_JSON}")

    # 4. Export Word DOCX document
    try:
        app = create_app(Settings(_env_file=".env"))
        with TestClient(app) as client:
            docx_resp = client.post("/api/v1/exports/docx", json=paper.model_dump(mode="json"))
            if docx_resp.status_code == 200:
                OUTPUT_DOCX.write_bytes(docx_resp.content)
                print(f"📄 Formatted Word DOCX document saved to: {OUTPUT_DOCX}")
    except Exception as docx_err:
        print(f"⚠️ Docx export note: {docx_err}")

    # 5. Print readable summary
    print("\n" + "=" * 60)
    print("🎓 GENERATED PAPER SUMMARY")
    print("=" * 60)
    print(f"Title:    {paper.title}")
    print(f"Provider: {generation_result.meta.provider_name} ({generation_result.meta.model_name})")
    print(f"Duration: {generation_result.meta.duration_ms} ms")
    if generation_result.meta.output_tokens:
        print(f"Tokens:   {generation_result.meta.output_tokens} output tokens")
    print(f"\nAbstract:\n{paper.abstract}\n")
    print("Sections Generated:")
    for section in paper.sections:
        words = len(section.content.split())
        print(f"  • [{section.id}] {section.heading} ({words} words, state: {section.state})")

    print(f"\nReferences ({len(paper.references)}):")
    for ref in paper.references:
        print(f"  - [{ref.id}] {ref.text}")

    if paper.review_warnings:
        print(f"\nReview Warnings ({len(paper.review_warnings)}):")
        for warning in paper.review_warnings:
            sec_info = f" (section: {warning.section_id})" if warning.section_id else ""
            print(f"  ⚠️ [{warning.code}]{sec_info} {warning.message}")
    print("=" * 60 + "\n")
