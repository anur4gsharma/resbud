"""Application factory and middleware assembly for Resbud."""

from fastapi import FastAPI
from starlette.middleware.cors import CORSMiddleware

from resbud_api.api.error_handlers import install_error_handlers
from resbud_api.api.routes.health import router as health_router
from resbud_api.core.request_boundary import RequestBoundaryMiddleware
from resbud_api.core.safe_errors import SafeUnexpectedErrorMiddleware
from resbud_api.core.settings import Settings, get_settings


def create_app(settings: Settings | None = None) -> FastAPI:
    """Create an app with explicit settings, suitable for tests and deployment."""
    runtime_settings = settings or get_settings()
    app = FastAPI(
        title="Resbud API",
        version="0.1.0",
        description="API for creating structured research paper drafts.",
        debug=False,
    )
    app.state.settings = runtime_settings
    install_error_handlers(app)
    app.include_router(health_router)

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
