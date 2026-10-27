import pytest
from pydantic import SecretStr, ValidationError

from resbud_api.core.settings import MAX_REQUEST_BODY_BYTES, Settings


def test_development_is_ready_without_paid_provider_configuration() -> None:
    settings = Settings(environment="development", _env_file=None)

    assert settings.readiness_issues() == []


def test_production_reports_missing_configuration_without_values() -> None:
    settings = Settings(environment="production", _env_file=None)

    assert settings.readiness_issues() == [
        "generation_provider",
        "auth_issuer",
        "auth_audience",
    ]


def test_production_is_ready_when_required_configuration_is_present() -> None:
    settings = Settings(
        environment="production",
        generation_provider="openai",
        provider_model="test-model",
        provider_api_key=SecretStr("synthetic-test-key"),
        auth_issuer="https://identity.example.test/",
        auth_audience="resbud-test",
        _env_file=None,
    )

    assert settings.readiness_issues() == []


def test_example_secret_placeholder_is_not_treated_as_a_credential() -> None:
    settings = Settings(
        environment="production",
        generation_provider="openai",
        provider_model="test-model",
        provider_api_key="replace-with-your-local-secret",
        auth_issuer="https://identity.example.test/",
        auth_audience="resbud-test",
        _env_file=None,
    )

    assert settings.readiness_issues() == ["provider_api_key"]


def test_wildcard_cors_origin_is_rejected() -> None:
    with pytest.raises(ValidationError):
        Settings(cors_allowed_origins=["*"], _env_file=None)


def test_cors_paths_are_rejected_because_origins_are_exact() -> None:
    with pytest.raises(ValidationError):
        Settings(cors_allowed_origins=["https://example.test/app"], _env_file=None)


def test_request_body_limit_cannot_exceed_documented_maximum() -> None:
    with pytest.raises(ValidationError):
        Settings(max_request_body_bytes=MAX_REQUEST_BODY_BYTES + 1, _env_file=None)


def test_environment_variables_use_documented_resbud_names(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("RESBUD_ENV", "production")
    monkeypatch.setenv("RESBUD_GENERATION_PROVIDER", "openai")
    monkeypatch.setenv("RESBUD_PROVIDER_MODEL", "test-model")
    monkeypatch.setenv("RESBUD_PROVIDER_API_KEY", "synthetic-test-key")
    monkeypatch.setenv("RESBUD_AUTH_ISSUER", "https://identity.example.test")
    monkeypatch.setenv("RESBUD_AUTH_AUDIENCE", "resbud-test")
    monkeypatch.setenv("RESBUD_CORS_ALLOWED_ORIGINS", '["https://client.example.test"]')
    monkeypatch.setenv("RESBUD_MAX_REQUEST_BODY_BYTES", "2048")

    settings = Settings(_env_file=None)

    assert settings.environment == "production"
    assert settings.generation_provider == "openai"
    assert settings.provider_model == "test-model"
    assert settings.provider_api_key is not None
    assert settings.auth_audience == "resbud-test"
    assert settings.cors_allowed_origins == ["https://client.example.test"]
    assert settings.max_request_body_bytes == 2048


def test_provider_timeout_and_token_limits_are_bounded() -> None:
    with pytest.raises(ValidationError):
        Settings(provider_max_output_tokens=16001, _env_file=None)
    with pytest.raises(ValidationError):
        Settings(provider_connect_timeout_seconds=0.5, _env_file=None)
    with pytest.raises(ValidationError):
        Settings(provider_read_timeout_seconds=301, _env_file=None)
