import copy
import json
from pathlib import Path
from typing import Any

import pytest
import yaml
from jsonschema import Draft202012Validator
from openapi_spec_validator import validate
from pydantic import ValidationError

from resbud_api.core.errors import ApiErrorResponse, ResbudError, api_error_payload, safe_http_error
from resbud_api.domain.models import (
    GenerationRequest,
    GenerationResponse,
    PaperDraft,
    PaperPreferences,
    ProjectContext,
    ReferenceInput,
    ReviewWarning,
    SectionRegenerationRequest,
    SectionRegenerationResponse,
)

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).parent / "fixtures"
GENERATION_SCHEMA = json.loads((ROOT / "contracts/generation-request.schema.json").read_text())
PAPER_SCHEMA = json.loads((ROOT / "contracts/paper-draft.schema.json").read_text())
GENERATION_FIXTURE = json.loads((FIXTURES / "generation-request.valid.json").read_text())
PAPER_FIXTURE = json.loads((FIXTURES / "paper-draft.valid.json").read_text())


@pytest.mark.parametrize(
    ("fixture", "schema"),
    [
        (GENERATION_FIXTURE, GENERATION_SCHEMA),
        (PAPER_FIXTURE, PAPER_SCHEMA),
    ],
)
def test_valid_fixtures_match_json_schemas(fixture: dict[str, Any], schema: dict[str, Any]) -> None:
    Draft202012Validator.check_schema(schema)
    Draft202012Validator(schema).validate(fixture)


def test_generation_request_matches_contract_and_preserves_reference_text() -> None:
    request = GenerationRequest.model_validate(GENERATION_FIXTURE)
    serialized = request.model_dump(mode="json", exclude_unset=True)

    Draft202012Validator(GENERATION_SCHEMA).validate(serialized)
    assert serialized == GENERATION_FIXTURE
    assert request.references[0].text == "  Example Author. (2025). Example title.  "


def test_multiline_nonblank_source_and_provided_details_are_valid() -> None:
    request = copy.deepcopy(GENERATION_FIXTURE)
    request["source_draft"] = "\nOriginal\ntext\n"
    request["project"]["methodology_status"] = "provided"
    request["project"]["methodology"] = "\nLab\nmethod\n"

    validated = GenerationRequest.model_validate(request)
    assert validated.source_draft == "\nOriginal\ntext\n"
    assert validated.project.methodology_status == "provided"
    assert validated.project.methodology == "\nLab\nmethod\n"
    assert Draft202012Validator(GENERATION_SCHEMA).is_valid(request)


def test_paper_draft_matches_contract_and_serializes_deterministically() -> None:
    paper = PaperDraft.model_validate(PAPER_FIXTURE)
    first = paper.model_dump(mode="json")
    second = PaperDraft.model_validate(first).model_dump(mode="json")

    Draft202012Validator(PAPER_SCHEMA).validate(first)
    assert first == second
    assert first["references"][0]["text"] == "  Example Author. (2025). Example title.  "


def test_required_fields_are_rejected_by_schema_and_model() -> None:
    request = copy.deepcopy(GENERATION_FIXTURE)
    del request["project"]["research_question"]

    with pytest.raises(ValidationError):
        GenerationRequest.model_validate(request)
    assert list(Draft202012Validator(GENERATION_SCHEMA).iter_errors(request))


def test_over_limit_source_draft_is_rejected_by_schema_and_model() -> None:
    request = {**GENERATION_FIXTURE, "source_draft": "x" * 50001}

    with pytest.raises(ValidationError):
        GenerationRequest.model_validate(request)
    assert list(Draft202012Validator(GENERATION_SCHEMA).iter_errors(request))


def test_invalid_enum_and_extra_properties_are_rejected() -> None:
    invalid_enum = copy.deepcopy(GENERATION_FIXTURE)
    invalid_enum["preferences"]["citation_style"] = "mla"
    with pytest.raises(ValidationError):
        GenerationRequest.model_validate(invalid_enum)
    assert list(Draft202012Validator(GENERATION_SCHEMA).iter_errors(invalid_enum))

    extra_property = {**GENERATION_FIXTURE, "unexpected": "value"}
    with pytest.raises(ValidationError):
        GenerationRequest.model_validate(extra_property)
    assert list(Draft202012Validator(GENERATION_SCHEMA).iter_errors(extra_property))


def test_preferences_reject_duplicate_section_ids_and_coerced_integer_strings() -> None:
    with pytest.raises(ValidationError, match="unique section IDs"):
        PaperPreferences(
            target_word_count=1500,
            desired_sections=["results", "results"],
            citation_style="apa_7",
        )
    with pytest.raises(ValidationError):
        PaperPreferences(
            target_word_count="1500",
            desired_sections=["results"],
            citation_style="apa_7",
        )


def test_duplicate_section_ids_are_rejected() -> None:
    paper = copy.deepcopy(PAPER_FIXTURE)
    paper["sections"][1]["id"] = paper["sections"][0]["id"]

    with pytest.raises(ValidationError, match="section IDs must be unique"):
        PaperDraft.model_validate(paper)


@pytest.mark.parametrize("section_id", ["Intro", "x", "bad-id", "1results"])
def test_malformed_section_ids_are_rejected(section_id: str) -> None:
    paper = copy.deepcopy(PAPER_FIXTURE)
    paper["sections"][0]["id"] = section_id

    with pytest.raises(ValidationError):
        PaperDraft.model_validate(paper)


def test_malformed_reference_id_is_rejected() -> None:
    with pytest.raises(ValidationError):
        ReferenceInput(id="bad id", text="Reference text")


def test_optional_fields_and_nullable_values_follow_contract() -> None:
    project = copy.deepcopy(GENERATION_FIXTURE["project"])
    project["methodology_status"] = "unknown"
    project["methodology"] = None
    project.pop("methodology")
    project["dataset_or_materials_status"] = "not_available"
    project["dataset_or_materials"] = None
    context = ProjectContext.model_validate(project)
    assert context.methodology is None
    assert context.dataset_or_materials is None

    warning = ReviewWarning(
        code="GENERAL_REVIEW",
        severity="info",
        message="Review the draft.",
        section_id=None,
    )
    assert warning.section_id is None


@pytest.mark.parametrize(
    ("status_name", "content_name"),
    [
        ("methodology_status", "methodology"),
        ("dataset_or_materials_status", "dataset_or_materials"),
        ("results_status", "results"),
        ("limitations_status", "limitations"),
    ],
)
def test_provided_status_requires_nonblank_details(status_name: str, content_name: str) -> None:
    project = copy.deepcopy(GENERATION_FIXTURE["project"])
    project[status_name] = "provided"
    project[content_name] = "  "

    with pytest.raises(ValidationError):
        ProjectContext.model_validate(project)

    request = copy.deepcopy(GENERATION_FIXTURE)
    request["project"] = project
    assert list(Draft202012Validator(GENERATION_SCHEMA).iter_errors(request))


def test_unknown_and_explicit_unavailable_states_remain_distinct() -> None:
    project = copy.deepcopy(GENERATION_FIXTURE["project"])
    project["methodology_status"] = "unknown"
    project["dataset_or_materials_status"] = "not_available"
    project["results_status"] = "not_collected"
    project["limitations_status"] = "not_identified"

    context = ProjectContext.model_validate(project)

    assert context.methodology_status == "unknown"
    assert context.dataset_or_materials_status == "not_available"
    assert context.results_status == "not_collected"
    assert context.limitations_status == "not_identified"
    Draft202012Validator(GENERATION_SCHEMA).validate(
        {**GENERATION_FIXTURE, "project": context.model_dump(mode="json")}
    )


def test_section_regeneration_target_must_exist_and_empty_instruction_is_valid() -> None:
    request = {
        "schema_version": 1,
        "generation_request": GENERATION_FIXTURE,
        "current_paper": PAPER_FIXTURE,
        "section_id": "introduction",
        "user_instruction": "",
    }
    validated_request = SectionRegenerationRequest.model_validate(request)
    assert validated_request.user_instruction == ""

    replacement = SectionRegenerationResponse(
        schema_version=1,
        section=PAPER_FIXTURE["sections"][0],
        review_warnings=[],
    )
    replacement.validate_for_request(validated_request)
    mismatched_replacement = replacement.model_copy(
        update={"section": replacement.section.model_copy(update={"id": "results"})}
    )
    with pytest.raises(ValueError, match="must match the requested section_id"):
        mismatched_replacement.validate_for_request(validated_request)

    request["section_id"] = "discussion"
    with pytest.raises(ValidationError, match="section_id must identify"):
        SectionRegenerationRequest.model_validate(request)


def test_generation_response_uses_same_warning_source_and_nullable_usage_counts() -> None:
    warnings = PAPER_FIXTURE["review_warnings"]
    response = GenerationResponse.model_validate(
        {
            "schema_version": 1,
            "generation_id": "0d942247-40e8-4f71-a2c5-f95ad7c478e4",
            "paper": PAPER_FIXTURE,
            "review_warnings": warnings,
            "meta": {
                "provider_name": "fake",
                "model_name": "deterministic",
                "duration_ms": 0,
                "input_tokens": None,
                "output_tokens": None,
            },
        }
    )
    assert response.review_warnings == response.paper.review_warnings
    assert response.meta.input_tokens is None

    mismatched = response.model_dump(mode="json")
    mismatched["review_warnings"] = []
    with pytest.raises(ValidationError, match="review_warnings must match"):
        GenerationResponse.model_validate(mismatched)


def test_error_models_enforce_the_documented_shape_and_stable_codes() -> None:
    payload = api_error_payload(safe_http_error(422), "req-123")
    assert payload.model_dump(mode="json") == {
        "type": "about:blank",
        "title": "Request validation failed",
        "status": 422,
        "detail": "Correct the highlighted fields and try again.",
        "code": "VALIDATION_ERROR",
        "request_id": "req-123",
    }

    with pytest.raises(ValidationError):
        ApiErrorResponse(
            type="about:blank",
            title="Invalid",
            status=422,
            detail="Safe detail",
            code="not-a-stable-code",
            request_id="req-123",
        )
    with pytest.raises(ValidationError):
        ApiErrorResponse(
            type="about:blank",
            title="Invalid",
            status=422,
            detail="Safe detail",
            code="INVALID_REQUEST",
            request_id="x" * 101,
        )
    assert ResbudError(502).public_error.code == "PROVIDER_INVALID_RESPONSE"


def test_openapi_document_is_valid_and_matches_status_contracts() -> None:
    spec = yaml.safe_load((ROOT / "contracts/openapi.yaml").read_text())
    validate(spec)

    openapi_project = spec["components"]["schemas"]["ProjectContext"]["properties"]
    json_project = GENERATION_SCHEMA["properties"]["project"]["properties"]
    openapi_project_schema = spec["components"]["schemas"]["ProjectContext"]
    json_project_schema = GENERATION_SCHEMA["properties"]["project"]
    assert set(openapi_project) == set(json_project)
    assert set(openapi_project_schema["required"]) == set(json_project_schema["required"])
    assert openapi_project_schema["allOf"] == json_project_schema["allOf"]
    for name in (
        "methodology_status",
        "dataset_or_materials_status",
        "results_status",
        "limitations_status",
    ):
        assert openapi_project[name]["enum"] == json_project[name]["enum"]

    json_warning = PAPER_SCHEMA["properties"]["review_warnings"]["items"]["properties"]
    openapi_warning = spec["components"]["schemas"]["ReviewWarning"]["properties"]
    assert openapi_warning["code"]["enum"] == json_warning["code"]["enum"]
    assert openapi_warning["severity"]["enum"] == json_warning["severity"]["enum"]
    openapi_paper = spec["components"]["schemas"]["PaperDraft"]
    assert set(openapi_paper["properties"]) == set(PAPER_SCHEMA["properties"])
    assert set(openapi_paper["required"]) == set(PAPER_SCHEMA["required"])


def test_checked_in_openapi_operations_match_running_fastapi_routes() -> None:
    from resbud_api.core.settings import Settings
    from resbud_api.main import create_app

    checked_in = yaml.safe_load((ROOT / "contracts/openapi.yaml").read_text())
    implemented = create_app(Settings(environment="test", _env_file=None)).openapi()
    implemented_paths = implemented["paths"]

    for path, path_item in checked_in["paths"].items():
        assert path in implemented_paths
        for method, expected_operation in path_item.items():
            if method not in {"get", "post"}:
                continue
            actual_operation = implemented_paths[path][method]
            assert actual_operation["operationId"] == expected_operation["operationId"]
            if "requestBody" in expected_operation:
                assert set(actual_operation["requestBody"]["content"]) == set(
                    expected_operation["requestBody"]["content"]
                )
            if "200" in expected_operation["responses"]:
                assert set(actual_operation["responses"]["200"]["content"]) == set(
                    expected_operation["responses"]["200"]["content"]
                )

    checked_paper = checked_in["components"]["schemas"]["PaperDraft"]
    implemented_paper = implemented["components"]["schemas"]["PaperDraft"]
    assert set(checked_paper["properties"]) == set(implemented_paper["properties"])
    assert set(checked_paper["required"]) == set(implemented_paper["required"])
