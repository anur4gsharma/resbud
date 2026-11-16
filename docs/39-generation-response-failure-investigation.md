# Root-Cause Investigation Report: Generation Response Contract Failure

**Document ID:** RESBUD-DIAG-2026-GEN-001  
**Incident Reference:** Support Request ID `ce6e5924-597c-421c-9203-534697720e0f`  
**Service Impacted:** Resbud Android Application & Render Production Backend (`resbud-api`)  
**Observed Error Message:**  
`"The server response did not match the supported paper format.\nSupport request ID: ce6e5924-597c-421c-9203-534697720e0f"`  
**Investigated By:** Principal Engineer  
**Date:** November 16–17, 2026  
**Status:** **ROOT CAUSE CONFIRMED & DIAGNOSED**

---

## 1. Executive Diagnostic Summary

On November 16, 2026, an Android user reported a critical failure during research paper generation with the error string:
> *"The server response did not match the supported paper format."*  
> *Support request ID: `ce6e5924-597c-421c-9203-534697720e0f`*

Using Render MCP telemetry (`list_services`, `list_logs`, `list_deploys`), the production environment for `https://resbud-api.onrender.com` (Render service ID `srv-dbt0425ckfvc73cd2s50`) was inspected:

1. **Endpoint Called:** `POST /api/v1/generations`
2. **Backend Execution:** The request reached the FastAPI backend, was successfully authenticated, passed Pydantic input validation, executed the long-form manuscript generation pipeline (`long_form_engine.py`), and completed successfully.
3. **HTTP Status Code:** **`200 OK`** (Logged at `2026-11-16T18:52:00.627841Z` and `2026-11-16T18:53:20.627389Z`).
4. **Backend Response:** A contract-valid `GenerationResponse` JSON body was serialized and transmitted with header `X-Request-ID: ce6e5924-597c-421c-9203-534697720e0f`.
5. **Client Failure Locus:** The failure did **not** originate on the backend or in the LLM provider. The failure occurred entirely within the Flutter client's `GenerationApiClient.generate()` method during `GenerationResponse.fromJson(decoded)`.

---

## 2. Production Evidence & Deploy Correlation

### 2.1 Render Deployment Timeline
- **Deploy `dep-dbtkgf6c6qcc73bvsh3g` (Finished `18:16:24Z`):** Commit `60b45305` (PR #3).
- **Deploy `dep-dbtkub6c6qcc73c0l9kg` (Started `18:45:00Z`, Finished `18:45:50Z`):** Commit `11704011` (PR #4, introducing IEEE Conference Paper format and Semantic Figure Placement).
- **Incident Occurrence (`18:52:00Z` – `18:53:20Z`):** Production Render logs recorded:
  ```text
  INFO: 10.24.23.142:0 - "POST /api/v1/generations HTTP/1.1" 200 OK
  ```
  Correlated with support request ID `ce6e5924-597c-421c-9203-534697720e0f`.

### 2.2 Released Client Binary Correlation
- The released Android APK on disk (`releases/android/Resbud-release.apk`, SHA-256 `b86513c0e40b10610e176941243ebdac038cb0e0f33bbbbbb39b9d43e0a8beb7`) was compiled at commit `64670b9d6113dc033452d6992d0e1e2a5a211969` (`Mon Nov 16 20:56:44 2026 +0530` / `15:26 UTC`).
- At commit `64670b9`, `PaperDraftPayload.fromJson` in `mobile/lib/features/generation/generation_models.dart` contained:
  ```dart
  factory PaperDraftPayload.fromJson(Map<String, Object?> json) {
    _requireKeys(
      json,
      const {
        'schema_version', 'title', 'abstract', 'keywords',
        'sections', 'references', 'review_warnings',
      },
      'paper',
      optional: const {'page_layout', 'author_info', 'affiliation'},
    );
  ```
- And `_requireKeys` was implemented with strict closed-set validation:
  ```dart
  void _requireKeys(
    Map<String, Object?> value,
    Set<String> required,
    String label, {
    Set<String> optional = const {},
  }) {
    final missing = required.difference(value.keys.toSet());
    if (missing.isNotEmpty) throw FormatException('$label is missing required fields.');
    final allowed = {...required, ...optional};
    if (value.keys.any((key) => !allowed.contains(key))) {
      throw FormatException('$label contains unsupported fields.');
    }
  }
  ```

---

## 3. Confirmed Root Causes

### Root Cause 1: Schema Divergence Across Release Boundary
When Render deployed commit `11704011` (deploy `dep-dbtkub6c6qcc73c0l9kg`), the backend's `PaperDraft` Pydantic model gained four new fields:
- `document_template: str = "default"`
- `authors: list[AuthorMetadata] | None = None`
- `affiliations: list[AuthorAffiliation] | None = None`
- `figures: list[StructuredFigure] | None = None`

In Pydantic v2, `model_dump(mode="json")` includes all declared fields (even when defaulted or `None`). Consequently, every HTTP `200 OK` response payload from `/api/v1/generations` contained:
```json
{
  "document_template": "default",
  "authors": null,
  "affiliations": null,
  "figures": null
}
```
When the released Android client (`64670b9`) received this payload, `value.keys.any((key) => !allowed.contains(key))` detected `document_template`, `authors`, `affiliations`, and `figures` as keys not present in `{'page_layout', 'author_info', 'affiliation'}`.  
As a result, `_requireKeys` threw:
```text
FormatException: paper contains unsupported fields.
```

### Root Cause 2: Exception Swallowing and Monolithic Error Mapping in `GenerationApiClient`
In `mobile/lib/features/generation/generation_api_client.dart`:
```dart
    final requestId = _requestIdFromHeaders(response.headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _errorFromResponse(response, requestId);
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException('Expected an object response.');
      final parsed = GenerationResponse.fromJson(
        Map<String, Object?>.from(decoded),
      );
      return GenerationResult(response: parsed, requestId: requestId);
    } on Object {
      throw GenerationApiFailure(
        code: GenerationFailureCode.invalidResponse,
        requestId: requestId,
        statusCode: response.statusCode,
      );
    }
```
1. `on Object` discarded the underlying exception instance `e` and its stack trace.
2. The exact failure reason (`FormatException: paper contains unsupported fields.`) was never logged or captured.
3. Every deserialization error was flattened into `GenerationFailureCode.invalidResponse`.
4. `GenerationFailureCode.invalidResponse` mapped exclusively to the static string:
   `"The server response did not match the supported paper format."`
   misleading operators and users into believing that the server returned an invalid paper format or rejected the paper template, when in fact the server had produced a valid paper that the client binary could not parse.

### Root Cause 3: Incomplete Client Preferences Contract
In `mobile/lib/features/generation/generation_models.dart`:
`PaperPreferencesPayload` omitted `'include_review_notes_appendix'`, and `GenerationRequest.fromInputs` filtered out this field from `allowedPrefsKeys`. When toggled, the client stripped the option, and if deserialized from stored project context, `PaperPreferencesPayload.fromJson` threw `FormatException('preferences contains unsupported fields.')`.

---

## 4. End-to-End Pipeline Trace

```
1. Flutter UI (ProjectInputPage)
   └─ Constructs project context & preferences
2. GenerationRequest.fromInputs()
   └─ Stripped 'include_review_notes_appendix' (Contract defect #3)
3. GenerationApiClient.generate()
   └─ POST /api/v1/generations [HTTPS with Bearer JWT]
4. FastAPI Router (generations.py)
   └─ Validates GenerationRequest schema (HTTP 200)
5. Generation Coordinator (generation.py -> long_form_engine.py)
   └─ LLM generates sections, OMML equations, and references
   └─ Creates PaperDraft with document_template, authors, affiliations, figures
6. FastAPI Response Serialization
   └─ Pydantic dumps GenerationResponse (HTTP 200 OK)
   └─ Header: X-Request-ID: ce6e5924-597c-421c-9203-534697720e0f
7. Flutter API Client Response Handling
   └─ Receives HTTP 200 OK
   └─ GenerationResponse.fromJson(decoded)
   └─ PaperDraftPayload.fromJson(paperMap)
   └─ _requireKeys fails: 'document_template' is unsupported in APK v1.0.0
   └─ Throws FormatException('paper contains unsupported fields.')
8. Catch block (on Object)
   └─ Swallows FormatException
   └─ Throws GenerationApiFailure(invalidResponse, requestId: ce6e5924-...)
9. ProjectInputPage UI
   └─ Displays "The server response did not match the supported paper format."
```

---

## 5. Remediation Plan

1. **Unify Canonical Schema:**
   - Ensure all models on backend and Flutter recognize all supported fields: `document_template`, `authors`, `affiliations`, `figures`, `include_review_notes_appendix`, `citation_number`, `citation_locations`, `is_cited`, `review_warning`.
2. **Improve Error Distinctions:**
   - Update `GenerationFailureCode` to include:
     - `deserializationFailure`: for client-side JSON/model parsing errors.
     - `unsupportedPaperFormat`: for invalid or unrecognized paper format requests.
     - `localPersistenceFailure`: for SQLite save errors.
   - Update `GenerationApiFailure` to capture `detail` from server error payloads and client exceptions.
   - In `supportDetail`, render both the actionable message, the diagnostic detail, and the support request ID.
3. **Descriptive Unsupported Key Diagnostics:**
   - Update `_requireKeys` to output the exact missing or unsupported keys in its `FormatException`.
4. **Build & Sign Universal Release APK:**
   - Compile a fresh release APK containing the unified contract.
   - Verify signatures with `apksigner`.
   - Update `releases/android/Resbud-release.apk` and `checksums.txt`.
