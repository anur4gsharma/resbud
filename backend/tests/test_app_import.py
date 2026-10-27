from resbud_api.main import app


def test_fastapi_application_imports() -> None:
    assert app.title == "Resbud API"
    assert app.version == "0.1.0"
