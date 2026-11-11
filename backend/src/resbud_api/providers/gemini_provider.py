"""Google Gemini REST API adapter with schema-constrained JSON output."""

import asyncio
import json
from time import perf_counter
from typing import Any, cast

import httpx
from pydantic import ValidationError

from resbud_api.core.settings import Settings
from resbud_api.domain.models import (
    PaperDraft,
    PaperSection,
    ResearchAnalysisRequest,
    ResearchAnalysisResponse,
)
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


VALID_WARNING_CODES = {
    "MISSING_METHOD",
    "MISSING_DATASET_DETAILS",
    "MISSING_RESULTS",
    "MISSING_LIMITATIONS",
    "CITATION_NEEDED",
    "REFERENCE_INCOMPLETE",
    "CLAIM_NEEDS_REVIEW",
    "INPUT_CONFLICT",
    "SECTION_NOT_APPLICABLE",
    "GENERAL_REVIEW",
}
VALID_SEVERITIES = {"info", "warning", "critical"}


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
        self._model = settings.provider_model or "gemini-3.5-flash"
        self._candidate_models: list[str] = []
        for m in [
            self._model,
            "gemini-3.5-flash",
            "gemini-3.1-flash-lite",
            "gemini-3.5-flash-lite",
        ]:
            if m and m not in self._candidate_models:
                self._candidate_models.append(m)
        self._active_model_index: int = 0
        self._max_output_tokens = settings.provider_max_output_tokens
        self._base_url = base_url.rstrip("/")
        self._timeout = httpx.Timeout(
            connect=settings.provider_connect_timeout_seconds,
            read=settings.provider_read_timeout_seconds,
            write=settings.provider_connect_timeout_seconds,
            pool=settings.provider_connect_timeout_seconds,
        )
        self._api_keys: list[str] = list(settings.all_provider_api_keys)
        if not self._api_keys and settings.provider_api_key is not None:
            raw = settings.provider_api_key.get_secret_value().strip()
            if raw:
                self._api_keys.append(raw)
        self._active_key_index: int = 0
        self._owns_client = client is None
        if client is not None:
            self._client: httpx.AsyncClient | None = client
        elif self._api_keys and self._model is not None:
            self._client = httpx.AsyncClient(timeout=self._timeout)
        else:
            self._client = None

    @property
    def _api_key(self) -> str | None:
        if self._api_keys:
            return self._api_keys[self._active_key_index % len(self._api_keys)]
        return None

    async def generate_paper(self, generation_input: GenerationInput) -> ProviderResult:
        result = await self._request(generation_input.prompt, PaperDraft)
        try:
            data = json.loads(result.structured_output)
            if isinstance(data, dict):
                # Ensure authoritative user references are preserved exactly as required by contract
                data["references"] = [
                    r.model_dump(mode="json") for r in generation_input.brief.references
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

    async def generate_section(self, prompt: GenerationPrompt) -> ProviderResult:
        return await self._request(prompt, PaperSection)

    async def analyze_research(self, request: ResearchAnalysisRequest) -> ResearchAnalysisResponse:
        from resbud_api.services.analysis import assess_research_quality

        if self._client is None or self._model is None or not self._api_keys:
            return assess_research_quality(request)
        try:
            prompt = GenerationPrompt(
                version="analysis-v1",
                system_instructions=(
                    "You are a senior scientific peer reviewer and academic research director. "
                    "Analyze raw research materials to extract topic, question, objectives, "
                    "methodology, and findings. Detect contradictions and missing details. "
                    "Synthesize a dynamic outline with descriptive section headings. "
                    "Return exactly one JSON object matching the schema."
                ),
                user_message=(
                    f"Research source notes:\n{request.source_material}\n\n"
                    f"Title hint: {request.title_hint or 'None'}"
                ),
                output_schema="ResearchAnalysisResponse",
            )
            res = await self._request(prompt, ResearchAnalysisResponse)
            return ResearchAnalysisResponse.model_validate_json(res.structured_output)
        except Exception:
            return assess_research_quality(request)

    async def _request(
        self,
        prompt: GenerationPrompt,
        output_model: type[PaperDraft] | type[PaperSection] | type[ResearchAnalysisResponse],
    ) -> ProviderResult:
        if self._client is None or self._model is None or not self._api_keys:
            raise ProviderUnavailable

        model_name = self._model
        if not model_name.startswith("models/"):
            model_name = f"models/{model_name}"

        url = f"{self._base_url}/v1beta/{model_name}:generateContent"

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
        total_models = len(self._candidate_models)
        total_keys = len(self._api_keys)
        response: httpx.Response | None = None
        succeeded = False

        for model_attempt in range(total_models):
            model_idx = (self._active_model_index + model_attempt) % total_models
            current_model = self._candidate_models[model_idx]
            model_name = (
                current_model if current_model.startswith("models/") else f"models/{current_model}"
            )
            url = f"{self._base_url}/v1beta/{model_name}:generateContent"

            for key_attempt in range(total_keys):
                key_idx = (self._active_key_index + key_attempt) % total_keys
                current_key = self._api_keys[key_idx]
                headers = {
                    "x-goog-api-key": current_key,
                    "Content-Type": "application/json",
                }

                try:
                    response = await self._client.post(url, headers=headers, json=payload)
                except httpx.TimeoutException as exc:
                    if key_attempt < total_keys - 1 or model_attempt < total_models - 1:
                        continue
                    raise ProviderTimeout from exc
                except (httpx.ConnectError, httpx.NetworkError) as exc:
                    if key_attempt < total_keys - 1 or model_attempt < total_models - 1:
                        continue
                    raise ProviderUnavailable from exc
                except httpx.HTTPError as exc:
                    if key_attempt < total_keys - 1 or model_attempt < total_models - 1:
                        continue
                    raise ProviderUnavailable from exc

                if response.status_code == 429:
                    if key_attempt < total_keys - 1:
                        continue
                    if model_attempt < total_models - 1:
                        break  # Fall back to next model candidate
                    # Backoff retry in case of short temporary rate spikes on free tier
                    await asyncio.sleep(2.5)
                    try:
                        response = await self._client.post(url, headers=headers, json=payload)
                    except Exception:
                        pass
                    if response.status_code == 429:
                        raise ProviderRateLimited

                if response.status_code in {401, 403} or response.status_code >= 500:
                    if key_attempt < total_keys - 1 or model_attempt < total_models - 1:
                        continue
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
                        response = await self._client.post(
                            url, headers=headers, json=fallback_payload
                        )
                    except httpx.TimeoutException as exc:
                        if key_attempt < total_keys - 1 or model_attempt < total_models - 1:
                            continue
                        raise ProviderTimeout from exc
                    except (httpx.ConnectError, httpx.NetworkError, httpx.HTTPError) as exc:
                        if key_attempt < total_keys - 1 or model_attempt < total_models - 1:
                            continue
                        raise ProviderUnavailable from exc
                    if response.status_code == 429:
                        if key_attempt < total_keys - 1:
                            continue
                        if model_attempt < total_models - 1:
                            break
                        raise ProviderRateLimited
                    if response.status_code in {401, 403} or response.status_code >= 500:
                        if key_attempt < total_keys - 1 or model_attempt < total_models - 1:
                            continue
                        raise ProviderUnavailable
                    if response.status_code != 200:
                        if model_attempt < total_models - 1:
                            break
                        raise ProviderInvalidResponse
                elif response.status_code != 200:
                    if model_attempt < total_models - 1:
                        break
                    raise ProviderInvalidResponse

                # Success with current_key and current_model! Set them as active
                self._active_key_index = key_idx
                self._active_model_index = model_idx
                self._model = current_model
                succeeded = True
                break

            if succeeded:
                break

        if response is None or response.status_code != 200:
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
                seen_ids: set[str] = set()
                for sec in parsed.get("sections", []):
                    if isinstance(sec, dict):
                        if "section_id" in sec and "id" not in sec:
                            sec["id"] = sec.pop("section_id")
                        raw_id = str(sec.get("id") or "section").lower()
                        raw_sec_id = raw_id.replace("-", "_").replace(" ", "_")
                        sec_id = "".join(c for c in raw_sec_id if c.isalnum() or c == "_")
                        if not sec_id or not sec_id[0].isalpha():
                            sec_id = f"sec_{sec_id}"
                        original_id = sec_id[:40]
                        final_id = original_id
                        counter = 1
                        while final_id in seen_ids:
                            counter += 1
                            suffix = f"_{counter}"
                            final_id = f"{original_id[: 40 - len(suffix)]}{suffix}"
                        seen_ids.add(final_id)
                        sec["id"] = final_id
                        if sec.get("state") not in {"draft", "needs_input", "not_applicable"}:
                            sec["state"] = "draft"
                parsed.setdefault("schema_version", 1)
                parsed.setdefault("review_warnings", [])
                for warning in parsed.get("review_warnings", []):
                    if isinstance(warning, dict):
                        code = str(warning.get("code") or "GENERAL_REVIEW").upper().strip()
                        if code not in VALID_WARNING_CODES:
                            if "DATASET" in code or "MATERIAL" in code:
                                code = "MISSING_DATASET_DETAILS"
                            elif "METHOD" in code:
                                code = "MISSING_METHOD"
                            elif "RESULT" in code:
                                code = "MISSING_RESULTS"
                            elif "LIMITATION" in code:
                                code = "MISSING_LIMITATIONS"
                            elif "CITE" in code or "CITATION" in code:
                                code = "CITATION_NEEDED"
                            elif "REF" in code:
                                code = "REFERENCE_INCOMPLETE"
                            elif "CONFLICT" in code:
                                code = "INPUT_CONFLICT"
                            else:
                                code = "GENERAL_REVIEW"
                        warning["code"] = code
                        sev = str(warning.get("severity") or "warning").lower().strip()
                        if sev not in VALID_SEVERITIES:
                            sev = "warning"
                        warning["severity"] = sev
                        if not warning.get("message"):
                            warning["message"] = "Review recommended for this section."
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
