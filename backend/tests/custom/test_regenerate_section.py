"""Test targeted section regeneration using the latest generated paper."""

import json
import time
from pathlib import Path
from typing import Any

import httpx
from fastapi.testclient import TestClient

from resbud_api.core.settings import Settings
from resbud_api.domain.models import SectionRegenerationRequest, SectionRegenerationResponse
from resbud_api.main import create_app

CUSTOM_DIR = Path(__file__).parent
INPUT_FILE = CUSTOM_DIR / "request_input.json"
PAPER_FILE = CUSTOM_DIR / "output_paper.json"


def test_user_section_regeneration() -> None:
    """Regenerate a specific section using the latest generated paper and an instruction."""
    assert INPUT_FILE.exists(), f"Input file not found: {INPUT_FILE}"
    assert PAPER_FILE.exists(), (
        f"Generated paper not found at {PAPER_FILE}. "
        "Run test_generate_custom_paper.py first to generate a base paper!"
    )

    request_input = json.loads(INPUT_FILE.read_text(encoding="utf-8"))
    generation_response = json.loads(PAPER_FILE.read_text(encoding="utf-8"))
    current_paper = generation_response["paper"]

    # Choose a section to regenerate (e.g. methodology or results or the second section)
    target_section_id = (
        "results"
        if any(s["id"] == "results" for s in current_paper["sections"])
        else current_paper["sections"][0]["id"]
    )
    instruction = (
        "Expand this section with more specific experimental measurements and preserve evidence."
    )

    payload: dict[str, Any] = {
        "schema_version": 1,
        "generation_request": request_input,
        "current_paper": current_paper,
        "section_id": target_section_id,
        "user_instruction": instruction,
    }

    # Validate schema
    validated_req = SectionRegenerationRequest.model_validate(payload)
    print(
        f"\n✅ Regenerating section '{validated_req.section_id}' with instruction: '{instruction}'"
    )

    response_json: dict[str, Any]
    try:
        probe = httpx.get("http://127.0.0.1:8000/health/live", timeout=2.0)
        if probe.status_code == 200:
            print("📡 Sending to live server at http://127.0.0.1:8000...")
            time.sleep(3.0)
            resp = httpx.post(
                "http://127.0.0.1:8000/api/v1/generations/sections",
                json=payload,
                timeout=120.0,
            )
            assert resp.status_code == 200, f"API error ({resp.status_code}): {resp.text}"
            response_json = resp.json()
        else:
            raise httpx.ConnectError("Server not responding")
    except (httpx.ConnectError, httpx.TimeoutException):
        app = create_app(Settings(_env_file=".env"))
        with TestClient(app) as client:
            resp = client.post("/api/v1/generations/sections", json=payload)
            assert resp.status_code == 200, f"App error ({resp.status_code}): {resp.text}"
            response_json = resp.json()

    regen_result = SectionRegenerationResponse.model_validate(response_json)
    sec = regen_result.section

    print("\n" + "=" * 60)
    print("🔄 SECTION REGENERATION RESULT")
    print("=" * 60)
    print(f"Section ID:   {sec.id}")
    print(f"Heading:      {sec.heading}")
    print(f"State:        {sec.state}")
    print(f"Word Count:   {len(sec.content.split())} words")
    print(f"\nNew Content:\n{sec.content}\n")
    if regen_result.review_warnings:
        print(f"Warnings ({len(regen_result.review_warnings)}):")
        for w in regen_result.review_warnings:
            print(f"  ⚠️ [{w.code}] {w.message}")
    print("=" * 60 + "\n")
