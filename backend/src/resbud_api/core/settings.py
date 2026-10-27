"""Typed runtime settings and safe readiness checks."""

from collections.abc import Callable
from functools import lru_cache
from typing import Literal, cast
from urllib.parse import urlsplit

from pydantic import AnyHttpUrl, Field, SecretStr, TypeAdapter, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

Environment = Literal["development", "test", "production"]
GenerationProvider = Literal["fake", "openai", "disabled"]
MAX_REQUEST_BODY_BYTES = 4 * 1024 * 1024
_HTTP_URL = TypeAdapter(AnyHttpUrl)


class Settings(BaseSettings):
    """Runtime configuration loaded from RESBUD_* environment variables or .env."""

    model_config = SettingsConfigDict(
        env_prefix="RESBUD_",
        env_file=".env",
        env_file_encoding="utf-8",
        env_ignore_empty=True,
        extra="ignore",
        populate_by_name=True,
    )

    environment: Environment = Field(..., validation_alias="RESBUD_ENV")
    generation_provider: GenerationProvider = Field(
        default="disabled", validation_alias="RESBUD_GENERATION_PROVIDER"
    )
    provider_model: str | None = Field(
        default=None, max_length=100, validation_alias="RESBUD_PROVIDER_MODEL"
    )
    provider_max_output_tokens: int = Field(
        default=12000, ge=256, le=16000, validation_alias="RESBUD_PROVIDER_MAX_OUTPUT_TOKENS"
    )
    provider_connect_timeout_seconds: float = Field(
        default=5.0,
        ge=1.0,
        le=30.0,
        validation_alias="RESBUD_PROVIDER_CONNECT_TIMEOUT_SECONDS",
    )
    provider_read_timeout_seconds: float = Field(
        default=90.0,
        ge=5.0,
        le=300.0,
        validation_alias="RESBUD_PROVIDER_READ_TIMEOUT_SECONDS",
    )
    provider_api_key: SecretStr | None = Field(
        default=None, validation_alias="RESBUD_PROVIDER_API_KEY"
    )
    auth_issuer: AnyHttpUrl | None = Field(default=None, validation_alias="RESBUD_AUTH_ISSUER")
    auth_audience: str | None = Field(default=None, validation_alias="RESBUD_AUTH_AUDIENCE")
    cors_allowed_origins: list[str] = Field(
        default_factory=list, validation_alias="RESBUD_CORS_ALLOWED_ORIGINS"
    )
    max_request_body_bytes: int = Field(
        default=MAX_REQUEST_BODY_BYTES,
        ge=1024,
        le=MAX_REQUEST_BODY_BYTES,
        validation_alias="RESBUD_MAX_REQUEST_BODY_BYTES",
    )

    @model_validator(mode="after")
    def reject_fake_provider_in_production(self) -> "Settings":
        if self.environment == "production" and self.generation_provider == "fake":
            raise ValueError("the fake generation provider cannot be enabled in production")
        return self

    @field_validator("provider_model", mode="before")
    @classmethod
    def normalize_provider_model(cls, value: object) -> object:
        if isinstance(value, str):
            return value.strip() or None
        return value

    @field_validator("provider_api_key", mode="before")
    @classmethod
    def ignore_provider_key_placeholders(cls, value: object) -> object:
        if isinstance(value, str) and value.strip().lower() in {
            "replace-me",
            "replace-with-your-local-secret",
            "your-api-key",
        }:
            return None
        return value

    @field_validator("cors_allowed_origins")
    @classmethod
    def validate_cors_origins(cls, origins: list[str]) -> list[str]:
        normalized: list[str] = []
        for origin in origins:
            parsed = urlsplit(str(_HTTP_URL.validate_python(origin)))
            if (
                "*" in origin
                or parsed.path not in {"", "/"}
                or parsed.query
                or parsed.fragment
                or parsed.username
                or parsed.password
            ):
                raise ValueError("CORS origins must be exact HTTP(S) origins")
            normalized.append(f"{parsed.scheme}://{parsed.netloc}")
        return normalized

    @field_validator("auth_audience", mode="before")
    @classmethod
    def normalize_auth_audience(cls, value: object) -> object:
        if isinstance(value, str):
            return value.strip() or None
        return value

    def readiness_issues(self) -> list[str]:
        """Return non-sensitive names of required production settings that are absent."""
        if self.environment != "production":
            return []

        missing: list[str] = []
        if self.generation_provider == "disabled":
            missing.append("generation_provider")
        if self.generation_provider == "openai":
            if (
                self.provider_api_key is None
                or not self.provider_api_key.get_secret_value().strip()
            ):
                missing.append("provider_api_key")
            if self.provider_model is None:
                missing.append("provider_model")
        if self.auth_issuer is None:
            missing.append("auth_issuer")
        if not self.auth_audience:
            missing.append("auth_audience")
        return missing


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Return process settings; tests may clear the cache after changing env vars."""
    settings_factory = cast(Callable[[], Settings], Settings)
    return settings_factory()
