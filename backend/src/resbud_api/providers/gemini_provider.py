"""Google Gemini REST API adapter with schema-constrained JSON output."""

import asyncio
import json
from time import perf_counter
from typing import Any, cast

import httpx
from pydantic import ValidationError

from resbud_api.core.settings import Settings
from resbud_api.domain.models import PaperDraft, PaperSection
from resbud_api.providers.base import (
    GenerationInput,
    GenerationPrompt,
    ProviderInvalidResponse,
    ProviderRateLimited,
    ProviderResult,
    ProviderTimeout,
    ProviderUnavailable,
    SectionRegenerationInput,
)

GEMINI_PAPER_DRAFT_SCHEMA: dict[str, Any] = {
    "type": "OBJECT",
    "properties": {
        "schema_version": {"type": "INTEGER"},
        "title": {"type": "STRING"},
        "abstract": {"type": "STRING"},
        "keywords": {"type": "ARRAY", "items": {"type": "STRING"}},
        "sections": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "id": {"type": "STRING"},
                    "heading": {"type": "STRING"},
                    "content": {"type": "STRING"},
                    "state": {"type": "STRING"},
                },
                "required": ["id", "heading", "content", "state"],
            },
        },
        "references": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "id": {"type": "STRING"},
                    "text": {"type": "STRING"},
                },
                "required": ["id", "text"],
            },
        },
        "review_warnings": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "code": {"type": "STRING"},
                    "message": {"type": "STRING"},
                    "severity": {"type": "STRING"},
                    "section_id": {"type": "STRING"},
                },
                "required": ["code", "message", "severity"],
            },
        },
    },
    "required": [
        "schema_version",
        "title",
        "abstract",
        "keywords",
        "sections",
        "references",
        "review_warnings",
    ],
}

GEMINI_PAPER_SECTION_SCHEMA: dict[str, Any] = {
    "type": "OBJECT",
    "properties": {
        "id": {"type": "STRING"},
        "heading": {"type": "STRING"},
        "content": {"type": "STRING"},
        "state": {"type": "STRING"},
    },
    "required": ["id", "heading", "content", "state"],
}


def clean_schema_for_gemini(raw_schema: dict[str, Any]) -> dict[str, Any]:
    """Inline $defs and remove unsupported schema keywords for Gemini OpenAPI parser."""
    defs = raw_schema.get("$defs", {})

    def resolve(node: Any, parent_key: str | None = None) -> Any:
        if isinstance(node, dict):
            if "$ref" in node:
                ref_key = node["$ref"].split("/")[-1]
                if ref_key in defs:
                    return resolve(defs[ref_key], parent_key)
            res: dict[str, Any] = {}
            for k, v in node.items():
                if k in {"$defs", "pattern", "additionalProperties", "const"}:
                    continue
                if k == "title" and parent_key != "properties":
                    continue
                if k == "anyOf" and isinstance(v, list):
                    non_null = [resolve(item, k) for item in v if item.get("type") != "null"]
                    if len(non_null) == 1:
                        res.update(non_null[0])
                        res["nullable"] = True
                        continue
                res[k] = resolve(v, k)
            return res
        if isinstance(node, list):
            return [resolve(item, parent_key) for item in node]
        return node

    return cast(dict[str, Any], resolve(raw_schema))


def strip_code_fences(text: str) -> str:
    """Extract raw JSON text if wrapped inside Markdown code blocks."""
    stripped = text.strip()
    if stripped.startswith("```"):
        lines = stripped.splitlines()
        if lines and lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].startswith("```"):
            lines = lines[:-1]
        stripped = "\n".join(lines).strip()
    return stripped


class GeminiProvider:
    """Call Google Gemini REST API with schema-constrained JSON output."""

    provider_name = "gemini"

    def __init__(
        self,
        settings: Settings,
        client: httpx.AsyncClient | None = None,
        base_url: str = "https://generativelanguage.googleapis.com",
    ) -> None:
        self._model = settings.provider_model
        self._max_output_tokens = settings.provider_max_output_tokens
        self._base_url = base_url.rstrip("/")
        self._timeout = httpx.Timeout(
            connect=settings.provider_connect_timeout_seconds,
            read=settings.provider_read_timeout_seconds,
            write=settings.provider_connect_timeout_seconds,
            pool=settings.provider_connect_timeout_seconds,
        )
        self._api_key = (
            settings.provider_api_key.get_secret_value()
            if settings.provider_api_key is not None
            else None
        )
        self._owns_client = client is None
        if client is not None:
            self._client: httpx.AsyncClient | None = client
        elif self._api_key is not None and self._model is not None:
            self._client = httpx.AsyncClient(timeout=self._timeout)
        else:
            self._client = None

    async def generate_paper(self, generation_input: GenerationInput) -> ProviderResult:
        result = await self._request(generation_input.prompt, PaperDraft)
        try:
            data = json.loads(result.structured_output)
            if isinstance(data, dict):
                # Ensure authoritative user references are preserved exactly as required by contract
                data["references"] = [
                    {"id": r.id, "text": r.text}
                    for r in generation_input.brief.references
                ]
                data["schema_version"] = 1
                if not data.get("review_warnings"):
                    data["review_warnings"] = []
                new_json = json.dumps(data)
                return ProviderResult(
                    structured_output=new_json,
                    provider_name=result.provider_name,
                    model_name=result.model_name,
                    duration_ms=result.duration_ms,
                    input_tokens=result.input_tokens,
                    output_tokens=result.output_tokens,
                    request_id=result.request_id,
                )
        except Exception:
            pass
        return result

    async def regenerate_section(
        self, regeneration_input: SectionRegenerationInput
    ) -> ProviderResult:
        return await self._request(regeneration_input.prompt, PaperSection)

    async def _request(
        self,
        prompt: GenerationPrompt,
        output_model: type[PaperDraft] | type[PaperSection],
    ) -> ProviderResult:
        if self._client is None or self._model is None or not self._api_key:
            raise ProviderUnavailable

        model_name = self._model
        if not model_name.startswith("models/"):
            model_name = f"models/{model_name}"

        url = f"{self._base_url}/v1beta/{model_name}:generateContent"
        headers = {
            "x-goog-api-key": self._api_key,
            "Content-Type": "application/json",
        }

        if output_model == PaperDraft:
            cleaned_schema = GEMINI_PAPER_DRAFT_SCHEMA
        elif output_model == PaperSection:
            cleaned_schema = GEMINI_PAPER_SECTION_SCHEMA
        else:
            cleaned_schema = clean_schema_for_gemini(
                output_model.model_json_schema(mode="validation")
            )
        payload: dict[str, Any] = {
            "systemInstruction": {
                "parts": [{"text": prompt.system_instructions}],
            },
            "contents": [
                {
                    "role": "user",
                    "parts": [{"text": prompt.user_message}],
                }
            ],
            "generationConfig": {
                "responseMimeType": "application/json",
                "responseSchema": cleaned_schema,
                "maxOutputTokens": self._max_output_tokens,
            },
        }

        started = perf_counter()
        try:
            response = await self._client.post(url, headers=headers, json=payload)
        except httpx.TimeoutException as exc:
            raise ProviderTimeout from exc
        except (httpx.ConnectError, httpx.NetworkError) as exc:
            raise ProviderUnavailable from exc
        except httpx.HTTPError as exc:
            raise ProviderUnavailable from exc

        if response.status_code == 429:
            # Backoff retry in case of short temporary rate spikes on free tier
            await asyncio.sleep(2.5)
            try:
                response = await self._client.post(url, headers=headers, json=payload)
            except Exception:
                pass
            if response.status_code == 429:
                raise ProviderRateLimited
        if response.status_code in {401, 403}:
            raise ProviderUnavailable
        if response.status_code >= 500:
            raise ProviderUnavailable
        if response.status_code == 400:
            # Fallback attempt without responseSchema if model strictly rejected complex schema
            fallback_payload = {
                "systemInstruction": payload["systemInstruction"],
                "contents": payload["contents"],
                "generationConfig": {
                    "responseMimeType": "application/json",
                    "maxOutputTokens": self._max_output_tokens,
                },
            }
            try:
                response = await self._client.post(url, headers=headers, json=fallback_payload)
            except httpx.TimeoutException as exc:
                raise ProviderTimeout from exc
            except (httpx.ConnectError, httpx.NetworkError, httpx.HTTPError) as exc:
                raise ProviderUnavailable from exc
            if response.status_code == 429:
                raise ProviderRateLimited
            if response.status_code in {401, 403} or response.status_code >= 500:
                raise ProviderUnavailable
            if response.status_code != 200:
                raise ProviderInvalidResponse
        elif response.status_code != 200:
            raise ProviderInvalidResponse

        try:
            data = response.json()
        except Exception as exc:
            raise ProviderInvalidResponse from exc

        candidates = data.get("candidates")
        if not candidates or not isinstance(candidates, list):
            raise ProviderInvalidResponse

        candidate = candidates[0]
        finish_reason = candidate.get("finishReason")
        if finish_reason not in {"STOP", None}:
            raise ProviderInvalidResponse

        content = candidate.get("content", {})
        parts = content.get("parts", [])
        if not parts or not isinstance(parts, list):
            raise ProviderInvalidResponse

        raw_text = parts[0].get("text")
        if not isinstance(raw_text, str) or not raw_text.strip():
            raise ProviderInvalidResponse

        clean_text = strip_code_fences(raw_text)
        try:
            parsed = json.loads(clean_text)
            if isinstance(parsed, dict) and output_model is PaperDraft:
                for sec in parsed.get("sections", []):
                    if isinstance(sec, dict):
                        if "section_id" in sec and "id" not in sec:
                            sec["id"] = sec.pop("section_id")
                        raw_id = str(sec.get("id") or "section").lower()
                        raw_sec_id = raw_id.replace("-", "_").replace(" ", "_")
                        sec_id = "".join(c for c in raw_sec_id if c.isalnum() or c == "_")
                        if not sec_id or not sec_id[0].isalpha():
                            sec_id = f"sec_{sec_id}"
                        sec["id"] = sec_id[:40]
                        if sec.get("state") not in {"draft", "needs_input", "not_applicable"}:
                            sec["state"] = "draft"
                parsed.setdefault("schema_version", 1)
                parsed.setdefault("review_warnings", [])
                if "references" in parsed and isinstance(parsed["references"], list):
                    for idx, ref in enumerate(parsed["references"]):
                        if isinstance(ref, dict):
                            if not ref.get("id"):
                                ref["id"] = f"ref_{idx + 1}"
                            if not ref.get("text"):
                                ref["text"] = "Reference text"
            elif isinstance(parsed, dict) and output_model is PaperSection:
                if "section_id" in parsed and "id" not in parsed:
                    parsed["id"] = parsed.pop("section_id")
                raw_id = str(parsed.get("id") or "section").lower()
                raw_sec_id = raw_id.replace("-", "_").replace(" ", "_")
                sec_id = "".join(c for c in raw_sec_id if c.isalnum() or c == "_")
                if not sec_id or not sec_id[0].isalpha():
                    sec_id = f"sec_{sec_id}"
                parsed["id"] = sec_id[:40]
                if parsed.get("state") not in {"draft", "needs_input", "not_applicable"}:
                    parsed["state"] = "draft"

            validated = output_model.model_validate(parsed)
        except (json.JSONDecodeError, ValidationError, TypeError, ValueError) as exc:
            raise ProviderInvalidResponse from exc

        usage = data.get("usageMetadata", {})
        input_tokens = usage.get("promptTokenCount")
        output_tokens = usage.get("candidatesTokenCount")
        model_version = data.get("modelVersion") or self._model
        request_id = response.headers.get("x-goog-request-id")

        return ProviderResult(
            structured_output=validated.model_dump_json(),
            provider_name=self.provider_name,
            model_name=model_version,
            duration_ms=max(0, round((perf_counter() - started) * 1000)),
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            request_id=request_id,
        )

    async def aclose(self) -> None:
        """Release the HTTP client during shutdown."""
        if self._client is not None and self._owns_client:
            await self._client.aclose()
