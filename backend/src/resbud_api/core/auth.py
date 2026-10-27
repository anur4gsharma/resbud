"""Authentication models, JWT verification, and route security dependencies."""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import time
from dataclasses import dataclass
from typing import Any, cast

from fastapi import Request
from pydantic import SecretStr

from resbud_api.core.errors import ResbudError
from resbud_api.core.settings import Settings


@dataclass(frozen=True)
class AuthenticatedUser:
    subject: str
    issuer: str
    audience: str
    claims: dict[str, Any]


def _base64url_decode(segment: str) -> bytes:
    rem = len(segment) % 4
    if rem > 0:
        segment += "=" * (4 - rem)
    return base64.urlsafe_b64decode(segment.encode("ascii"))


def _base64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def create_token(
    payload: dict[str, Any],
    signing_key: SecretStr | str | None = None,
    header: dict[str, Any] | None = None,
) -> str:
    """Create a signed or unsigned JWT string for tests or internal tokens."""
    hdr = header or {"alg": "HS256" if signing_key else "none", "typ": "JWT"}
    hdr_b64 = _base64url_encode(json.dumps(hdr, separators=(",", ":")).encode("utf-8"))
    payload_b64 = _base64url_encode(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    signing_input = f"{hdr_b64}.{payload_b64}".encode("ascii")

    if signing_key:
        key_str = (
            signing_key.get_secret_value()
            if isinstance(signing_key, SecretStr)
            else signing_key
        )
        sig = hmac.new(key_str.encode("utf-8"), signing_input, hashlib.sha256).digest()
        sig_b64 = _base64url_encode(sig)
    else:
        sig_b64 = ""

    return f"{hdr_b64}.{payload_b64}.{sig_b64}"


def decode_and_verify_token(
    token: str,
    expected_issuer: str,
    expected_audience: str,
    signing_key: SecretStr | None = None,
) -> AuthenticatedUser:
    """Validate a JWT Bearer token against issuer, audience, and expiry."""
    parts = token.split(".")
    if len(parts) != 3:
        raise ResbudError(401)

    header_b64, payload_b64, signature_b64 = parts

    try:
        header_bytes = _base64url_decode(header_b64)
        payload_bytes = _base64url_decode(payload_b64)
        header = json.loads(header_bytes.decode("utf-8"))
        payload = json.loads(payload_bytes.decode("utf-8"))
    except Exception as exc:
        raise ResbudError(401) from exc

    if not isinstance(header, dict) or not isinstance(payload, dict):
        raise ResbudError(401)

    # Validate signature if a signing key is configured
    if signing_key is not None and signing_key.get_secret_value().strip():
        key_bytes = signing_key.get_secret_value().encode("utf-8")
        signed_content = f"{header_b64}.{payload_b64}".encode("ascii")
        expected_sig = hmac.new(key_bytes, signed_content, hashlib.sha256).digest()
        try:
            actual_sig = _base64url_decode(signature_b64)
        except Exception as exc:
            raise ResbudError(401) from exc
        if not hmac.compare_digest(expected_sig, actual_sig):
            raise ResbudError(401)

    # Validate claims: exp, nbf, iss, aud, sub
    now = time.time()
    exp = payload.get("exp")
    if exp is not None:
        if not isinstance(exp, (int, float)) or exp < (now - 60):
            raise ResbudError(401)

    nbf = payload.get("nbf")
    if nbf is not None:
        if not isinstance(nbf, (int, float)) or nbf > (now + 60):
            raise ResbudError(401)

    iss = payload.get("iss")
    if not isinstance(iss, str):
        raise ResbudError(401)

    if iss.rstrip("/") != expected_issuer.rstrip("/"):
        raise ResbudError(401)

    aud = payload.get("aud")
    if isinstance(aud, list):
        if expected_audience not in aud:
            raise ResbudError(401)
    elif isinstance(aud, str):
        if aud != expected_audience:
            raise ResbudError(401)
    else:
        raise ResbudError(401)

    sub = payload.get("sub", "")
    if not isinstance(sub, str) or not sub.strip():
        raise ResbudError(401)

    return AuthenticatedUser(
        subject=sub,
        issuer=iss,
        audience=expected_audience,
        claims=payload,
    )


async def get_current_user(request: Request) -> AuthenticatedUser:
    """Dependency that authenticates requests on protected application routes."""
    settings = cast(Settings, request.app.state.settings)
    auth_header = request.headers.get("authorization")

    # In development or test environment without an auth_issuer configured:
    # Allow local unauthenticated access for local development / testing.
    if settings.environment != "production" and settings.auth_issuer is None:
        if not auth_header:
            user = AuthenticatedUser(
                subject="local-dev-user",
                issuer="local-dev",
                audience="resbud-local",
                claims={},
            )
            request.state.user = user
            return user

    # In production, or whenever an auth_issuer is configured, require a valid Bearer token.
    if not auth_header or not auth_header.lower().startswith("bearer "):
        raise ResbudError(401)

    token = auth_header[7:].strip()
    if not token:
        raise ResbudError(401)

    if settings.auth_issuer is None or not settings.auth_audience:
        # Production with incomplete auth configuration fails closed.
        raise ResbudError(401)

    user = decode_and_verify_token(
        token=token,
        expected_issuer=str(settings.auth_issuer),
        expected_audience=settings.auth_audience,
        signing_key=settings.auth_signing_key,
    )
    request.state.user = user
    return user
