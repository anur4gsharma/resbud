"""In-process sliding-window rate limiter for generation and export endpoints."""

from __future__ import annotations

import time
from collections import defaultdict

from fastapi import Request

from resbud_api.core.errors import ResbudRateLimitError


class InMemoryRateLimiter:
    """Per-caller sliding-window rate limiter.

    Note on multi-instance deployments:
    This rate limiter maintains state in process memory. For horizontally-scaled
    multi-instance deployments, rate limiting must be delegated to a shared store
    (such as Redis) or an edge reverse proxy / API gateway (e.g. Cloudflare or AWS API Gateway).
    """

    def __init__(self, limit_per_minute: int = 30) -> None:
        self.limit_per_minute = limit_per_minute
        self._history: dict[str, list[float]] = defaultdict(list)

    def is_allowed(self, caller_id: str) -> tuple[bool, int]:
        now = time.time()
        window_start = now - 60.0
        # Prune calls older than 60 seconds
        history = [t for t in self._history[caller_id] if t > window_start]
        self._history[caller_id] = history

        if len(history) >= self.limit_per_minute:
            oldest = history[0]
            retry_after = max(1, int(oldest + 60.0 - now) + 1)
            return False, retry_after

        history.append(now)
        return True, 0

    def reset(self) -> None:
        self._history.clear()


async def check_rate_limit(request: Request) -> None:
    """Route dependency to enforce per-caller rate limits on cost-intensive endpoints."""
    limiter = getattr(request.app.state, "rate_limiter", None)
    if limiter is None:
        return

    user = getattr(request.state, "user", None)
    if user is not None and getattr(user, "subject", None) and user.subject != "local-dev-user":
        caller_id = f"user:{user.subject}"
    else:
        forwarded = request.headers.get("x-forwarded-for")
        if forwarded:
            caller_id = forwarded.split(",")[0].strip()
        elif request.client:
            caller_id = request.client.host
        else:
            caller_id = "unknown"

    allowed, retry_after = limiter.is_allowed(caller_id)
    if not allowed:
        raise ResbudRateLimitError(retry_after=retry_after)
