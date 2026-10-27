"""Application factory and middleware assembly for Resbud."""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from starlette.middleware.cors import CORSMiddleware

from resbud_api.api.error_handlers import install_error_handlers
from resbud_api.api.routes.exports import router as exports_router
from resbud_api.api.routes.generations import router as generations_router
from resbud_api.api.routes.health import router as health_router
from resbud_api.core.request_boundary import RequestBoundaryMiddleware
from resbud_api.core.safe_errors import SafeUnexpectedErrorMiddleware
from resbud_api.core.settings import Settings, get_settings
from resbud_api.providers.base import DisabledProvider, GenerationProvider
from resbud_api.providers.fake import FakeProvider
from resbud_api.providers.openai_provider import OpenAIProvider


def create_app(
    settings: Settings | None = None,
    generation_provider: GenerationProvider | None = None,
) -> FastAPI:
    """Create an app with explicit settings, suitable for tests and deployment."""
    runtime_settings = settings or get_settings()
    if runtime_settings.environment == "production" and isinstance(
        generation_provider, FakeProvider
    ):
        raise ValueError("the fake generation provider cannot be injected in production")

    @asynccontextmanager
    async def lifespan(application: FastAPI) -> AsyncIterator[None]:
        yield
        close = getattr(application.state.generation_provider, "aclose", None)
        if close is not None:
            await close()

    app = FastAPI(
        title="Resbud API",
        version="0.1.0",
        description="API for creating structured research paper drafts.",
        debug=False,
        lifespan=lifespan,
    )
    app.state.settings = runtime_settings
    if generation_provider is not None:
        app.state.generation_provider = generation_provider
    elif runtime_settings.generation_provider == "fake":
        app.state.generation_provider = FakeProvider()
    elif runtime_settings.generation_provider == "openai":
        app.state.generation_provider = OpenAIProvider(runtime_settings)
    else:
        app.state.generation_provider = DisabledProvider()
    install_error_handlers(app)
    app.include_router(health_router)
    app.include_router(generations_router)
    app.include_router(exports_router)

    if runtime_settings.cors_allowed_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=runtime_settings.cors_allowed_origins,
            allow_credentials=False,
            allow_methods=["GET", "POST", "OPTIONS"],
            allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
            expose_headers=["X-Request-ID"],
        )

    app.add_middleware(SafeUnexpectedErrorMiddleware)

    # Added last so request IDs and body bounds wrap CORS and application responses.
    app.add_middleware(
        RequestBoundaryMiddleware,
        max_body_bytes=runtime_settings.max_request_body_bytes,
    )
    return app


app = create_app()
