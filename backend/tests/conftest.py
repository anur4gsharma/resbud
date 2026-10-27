"""Ensure direct pytest runs use the explicit, non-production test mode."""

import os

os.environ.setdefault("RESBUD_ENV", "test")
