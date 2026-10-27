"""Stable API error response types."""

from dataclasses import dataclass

from pydantic import BaseModel, ConfigDict, Field, StrictInt


class ApiErrorResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    type: str
    title: str
    status: StrictInt
    detail: str
    code: str = Field(pattern=r"^[A-Z0-9_]+$")
    request_id: str = Field(max_length=100)


@dataclass(frozen=True)
class SafeHttpError:
    status: int
    code: str
    title: str
    detail: str


class ResbudError(Exception):
    """An expected application failure mapped to a fixed, safe public error."""

    def __init__(self, status: int) -> None:
        self.public_error = safe_http_error(status)
        super().__init__(self.public_error.code)


class ResbudRateLimitError(ResbudError):
    """Specific error for rate limiting to attach a Retry-After header."""

    def __init__(self, retry_after: int = 60) -> None:
        super().__init__(429)
        self.retry_after = retry_after


HTTP_ERROR_DEFAULTS: dict[int, SafeHttpError] = {
    400: SafeHttpError(
        400, "INVALID_REQUEST", "Invalid request", "The request could not be processed."
    ),
    401: SafeHttpError(401, "UNAUTHENTICATED", "Authentication required", "Sign in and try again."),
    403: SafeHttpError(
        403, "FORBIDDEN", "Access denied", "You do not have access to this resource."
    ),
    404: SafeHttpError(
        404, "INVALID_REQUEST", "Not found", "The requested resource was not found."
    ),
    405: SafeHttpError(
        405, "INVALID_REQUEST", "Method not allowed", "This request method is not supported."
    ),
    413: SafeHttpError(
        413, "INPUT_TOO_LARGE", "Request too large", "The request exceeds the allowed size."
    ),
    415: SafeHttpError(
        415, "UNSUPPORTED_MEDIA_TYPE", "Unsupported media type", "Use a supported content type."
    ),
    422: SafeHttpError(
        422,
        "VALIDATION_ERROR",
        "Request validation failed",
        "Correct the highlighted fields and try again.",
    ),
    429: SafeHttpError(429, "RATE_LIMITED", "Request limit reached", "Wait before trying again."),
    502: SafeHttpError(
        502,
        "PROVIDER_INVALID_RESPONSE",
        "Upstream response unavailable",
        "The request could not be completed. Your saved draft is unchanged.",
    ),
    503: SafeHttpError(
        503,
        "PROVIDER_UNAVAILABLE",
        "Service unavailable",
        "The service is not ready. Try again later.",
    ),
    504: SafeHttpError(
        504,
        "PROVIDER_TIMEOUT",
        "Request timed out",
        "The request timed out. Check your saved draft before retrying.",
    ),
}


def safe_http_error(status: int) -> SafeHttpError:
    """Return a public, content-free error for a given HTTP status."""
    return HTTP_ERROR_DEFAULTS.get(
        status,
        SafeHttpError(500, "INTERNAL_ERROR", "Internal error", "An unexpected error occurred."),
    )


def api_error_payload(error: SafeHttpError, request_id: str) -> ApiErrorResponse:
    """Build the canonical JSON error body from a fixed safe error definition."""
    return ApiErrorResponse(
        type="about:blank",
        title=error.title,
        status=error.status,
        detail=error.detail,
        code=error.code,
        request_id=request_id,
    )
