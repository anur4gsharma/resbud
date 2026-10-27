"""Deterministic invariant checks for the versioned synthetic evaluation set."""

import asyncio
import copy
import json
import re
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator

from resbud_api.domain.models import GenerationRequest, GenerationResponse
from resbud_api.providers.fake import FakeProvider
from resbud_api.services.generation import generate_paper
from resbud_api.services.prompt_builder import PROMPT_VERSION

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = Path(__file__).parent / "fixtures"
EVALUATION = Path(__file__).parent / "evaluation" / "v1"
BASE_REQUEST = json.loads((FIXTURES / "generation-request.valid.json").read_text())
MANIFEST = json.loads((EVALUATION / "manifest.json").read_text())
PAPER_SCHEMA = json.loads((ROOT / "../contracts/paper-draft.schema.json").resolve().read_text())
NUMBER = re.compile(r"\b\d+(?:[.,]\d+)*%?\b")


def _merged(base: dict[str, Any], overrides: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(base)
    for key, value in overrides.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = _merged(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result


def test_evaluation_run_manifest_matches_code_and_versioned_rubric() -> None:
    assert MANIFEST["evaluation_set"] == "resbud-backend-ai-v1"
    assert MANIFEST["paper_schema_version"] == 1
    assert MANIFEST["prompt_version"] == PROMPT_VERSION
    assert MANIFEST["run_manifest"]["provider"] == "fake"
    assert MANIFEST["run_manifest"]["model"] == FakeProvider().model_name
    assert MANIFEST["run_manifest"]["date"]
    assert "do not establish scientific truth" in MANIFEST["run_manifest"]["evaluator_notes"]


def test_fixture_ids_are_unique_and_cover_the_required_profiles() -> None:
    case_ids = [case["id"] for case in MANIFEST["cases"]]

    assert len(case_ids) == len(set(case_ids))
    assert set(case_ids) == {
        "complete-input",
        "missing-results",
        "missing-methods",
        "conflicting-claims",
        "incomplete-reference",
        "non-experimental-research",
        "unusual-academic-structure",
    }


def test_synthetic_evaluation_cases_preserve_contract_and_evidence_invariants() -> None:
    for case in MANIFEST["cases"]:
        request_data = _merged(BASE_REQUEST, case["input_overrides"])
        request = GenerationRequest.model_validate(request_data)
        response = asyncio.run(generate_paper(request, FakeProvider()))
        response_data = response.model_dump(mode="json")
        parsed_response = GenerationResponse.model_validate(response_data)
        paper_data = parsed_response.paper.model_dump(mode="json")

        Draft202012Validator(PAPER_SCHEMA).validate(paper_data)
        assert parsed_response.paper.references == request.references, case["id"]
        assert [section.id for section in parsed_response.paper.sections] == (
            request.preferences.desired_sections
            or [section.id for section in parsed_response.paper.sections]
        ), case["id"]

        warning_codes = {warning.code for warning in parsed_response.review_warnings}
        assert set(case["required_warning_codes"]) <= warning_codes, case["id"]
        assert not set(case["forbidden_warning_codes"]) & warning_codes, case["id"]

        input_text = json.dumps(request_data, ensure_ascii=False)
        output_text = " ".join(
            (
                parsed_response.paper.title,
                parsed_response.paper.abstract,
                *(section.content for section in parsed_response.paper.sections),
                *(keyword for keyword in parsed_response.paper.keywords),
                *(reference.text for reference in parsed_response.paper.references),
            )
        )
        supplied_numbers = set(NUMBER.findall(input_text))
        assert set(NUMBER.findall(output_text)) <= supplied_numbers, case["id"]

        if case["id"] == "unusual-academic-structure":
            assert "β-lactam" in parsed_response.paper.sections[0].content
        if case["id"] == "non-experimental-research":
            result_section = next(
                section for section in parsed_response.paper.sections if section.id == "results"
            )
            assert result_section.state == "not_applicable"
