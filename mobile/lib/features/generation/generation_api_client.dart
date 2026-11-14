import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'generation_models.dart';

enum GenerationFailureCode {
  invalidRequest,
  unauthenticated,
  forbidden,
  inputTooLarge,
  unsupportedMediaType,
  validationError,
  rateLimited,
  internalError,
  providerInvalidResponse,
  providerUnavailable,
  providerTimeout,
  invalidResponse,
  networkUnavailable,
  unknown,
}

class GenerationApiFailure implements Exception {
  const GenerationApiFailure({
    required this.code,
    this.statusCode,
    this.requestId,
    this.mayHaveCompleted = false,
  });

  final GenerationFailureCode code;
  final int? statusCode;
  final String? requestId;
  final bool mayHaveCompleted;

  String get userMessage => switch (code) {
    GenerationFailureCode.invalidRequest => 'The server could not process this request.',
    GenerationFailureCode.unauthenticated => 'Authentication is required before generating.',
    GenerationFailureCode.forbidden => 'This account cannot use the generation service.',
    GenerationFailureCode.inputTooLarge => 'The submitted research exceeds the server limit.',
    GenerationFailureCode.unsupportedMediaType => 'The server rejected the request format.',
    GenerationFailureCode.validationError => 'The server rejected one or more input fields. Review them and try again.',
    GenerationFailureCode.rateLimited => 'The service is receiving too many requests. Wait before trying again.',
    GenerationFailureCode.internalError => 'The service encountered an unexpected error.',
    GenerationFailureCode.providerInvalidResponse => 'The generation service returned an unusable response.',
    GenerationFailureCode.providerUnavailable => 'The generation service is temporarily unavailable.',
    GenerationFailureCode.providerTimeout => 'The generation service timed out.',
    GenerationFailureCode.invalidResponse => 'The server response did not match the supported paper format.',
    GenerationFailureCode.networkUnavailable => 'Could not reach the generation service. Check the connection and service address.',
    GenerationFailureCode.unknown => 'The generation request failed for an unsupported reason.',
  };

  String get supportDetail => requestId == null
      ? userMessage
      : '$userMessage\nSupport request ID: $requestId';

  String get retryNotice => mayHaveCompleted
      ? 'Retrying sends a new generation request. The first request may still have completed, so this retry may trigger another model call.'
      : 'Retrying sends a new generation request.';

  @override
  String toString() => 'GenerationApiFailure($code, requestId: $requestId)';
}

class GenerationResult {
  const GenerationResult({required this.response, required this.requestId});

  final GenerationResponse response;
  final String? requestId;
}

class SectionRegenerationResult {
  const SectionRegenerationResult({required this.response, required this.requestId});

  final SectionRegenerationResponse response;
  final String? requestId;
}

abstract interface class PaperGenerationApi {
  Future<GenerationResult> generate(GenerationRequest request);
  Future<SectionRegenerationResult> regenerateSection(SectionRegenerationRequest request);
  Future<ResearchAnalysisResponsePayload> analyzeResearch(ResearchAnalysisRequestPayload request);
}

typedef BearerTokenProvider = Future<String?> Function();

class GenerationApiClient implements PaperGenerationApi {
  GenerationApiClient({
    required this.baseUri,
    http.Client? client,
    this.tokenProvider,
    this.timeout = const Duration(seconds: 300),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null {
    if (baseUri.scheme != 'http' && baseUri.scheme != 'https') {
      throw ArgumentError.value(baseUri, 'baseUri', 'must use HTTP or HTTPS');
    }
    if (baseUri.host.isEmpty) {
      throw ArgumentError.value(baseUri, 'baseUri', 'must include a host');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
  }

  static String get defaultBaseUrl {
    const configured = String.fromEnvironment('RESBUD_API_BASE_URL');
    if (configured.isNotEmpty) return configured;
    if (kIsWeb) {
      try {
        final host = Uri.base.host;
        if (host.isNotEmpty) {
          final scheme = Uri.base.scheme.isEmpty ? 'http' : Uri.base.scheme;
          return '$scheme://$host:8000';
        }
      } catch (e) {
        debugPrint('Unable to inspect Uri.base for web URL: $e');
      }
      return 'http://localhost:8000';
    }
    if (!kIsWeb) {
      try {
        if (Platform.isAndroid) return 'http://10.0.2.2:8000';
      } catch (e) {
        debugPrint('Unable to inspect Platform for platform-specific URL: $e');
      }
    }
    return 'http://127.0.0.1:8000';
  }

  factory GenerationApiClient.fromEnvironment({
    http.Client? client,
    BearerTokenProvider? tokenProvider,
    Duration timeout = const Duration(seconds: 300),
  }) => GenerationApiClient(
    baseUri: Uri.parse(defaultBaseUrl),
    client: client,
    tokenProvider: tokenProvider,
    timeout: timeout,
  );

  final Uri baseUri;
  final http.Client _client;
  final bool _ownsClient;
  final BearerTokenProvider? tokenProvider;
  final Duration timeout;

  Uri get _generationUri => baseUri.resolve('/api/v1/generations');
  Uri get _sectionRegenerationUri => baseUri.resolve('/api/v1/generations/sections');

  Future<void> close() async {
    if (_ownsClient) _client.close();
  }

  @override
  Future<GenerationResult> generate(GenerationRequest request) async {
    final token = await tokenProvider?.call();
    final headers = <String, String>{
      'content-type': 'application/json',
      'accept': 'application/json',
    };
    if (token != null && token.trim().isNotEmpty) {
      headers['authorization'] = 'Bearer ${token.trim()}';
    }

    late final http.Response response;
    try {
      response = await _client
          .post(
            _generationUri,
            headers: headers,
            body: request.encode(),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const GenerationApiFailure(
        code: GenerationFailureCode.providerTimeout,
        mayHaveCompleted: true,
      );
    } on SocketException {
      throw const GenerationApiFailure(
        code: GenerationFailureCode.networkUnavailable,
      );
    } on http.ClientException {
      throw const GenerationApiFailure(
        code: GenerationFailureCode.networkUnavailable,
      );
    }

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
  }

  @override
  Future<SectionRegenerationResult> regenerateSection(
    SectionRegenerationRequest request,
  ) async {
    final token = await tokenProvider?.call();
    final headers = <String, String>{
      'content-type': 'application/json',
      'accept': 'application/json',
    };
    if (token != null && token.trim().isNotEmpty) {
      headers['authorization'] = 'Bearer ${token.trim()}';
    }

    late final http.Response response;
    try {
      response = await _client
          .post(
            _sectionRegenerationUri,
            headers: headers,
            body: request.encode(),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const GenerationApiFailure(
        code: GenerationFailureCode.providerTimeout,
        mayHaveCompleted: true,
      );
    } on SocketException {
      throw const GenerationApiFailure(
        code: GenerationFailureCode.networkUnavailable,
      );
    } on http.ClientException {
      throw const GenerationApiFailure(
        code: GenerationFailureCode.networkUnavailable,
      );
    }

    final requestId = _requestIdFromHeaders(response.headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _errorFromResponse(response, requestId);
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException('Expected an object response.');
      final parsed = SectionRegenerationResponse.fromJson(
        Map<String, Object?>.from(decoded),
      );
      if (parsed.section.id != request.sectionId) {
        throw const FormatException('Replacement section ID does not match request.');
      }
      return SectionRegenerationResult(response: parsed, requestId: requestId);
    } on Object {
      throw GenerationApiFailure(
        code: GenerationFailureCode.invalidResponse,
        requestId: requestId,
        statusCode: response.statusCode,
      );
    }
  }

  @override
  Future<ResearchAnalysisResponsePayload> analyzeResearch(
    ResearchAnalysisRequestPayload request,
  ) async {
    final uri = baseUri.replace(path: '/api/v1/analyze');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (tokenProvider != null) {
      final token = await tokenProvider!();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    final http.Response response;
    try {
      response = await _client
          .post(uri, headers: headers, body: jsonEncode(request.toJson()))
          .timeout(timeout);
    } on TimeoutException {
      throw const GenerationApiFailure(
        code: GenerationFailureCode.providerTimeout,
        mayHaveCompleted: true,
      );
    } on SocketException {
      throw const GenerationApiFailure(
        code: GenerationFailureCode.networkUnavailable,
      );
    } on http.ClientException {
      throw const GenerationApiFailure(
        code: GenerationFailureCode.networkUnavailable,
      );
    }

    final requestId = _requestIdFromHeaders(response.headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _errorFromResponse(response, requestId);
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException('Expected an object response.');
      return ResearchAnalysisResponsePayload.fromJson(
        Map<String, Object?>.from(decoded),
      );
    } on Object {
      throw GenerationApiFailure(
        code: GenerationFailureCode.invalidResponse,
        requestId: requestId,
        statusCode: response.statusCode,
      );
    }
  }

  GenerationApiFailure _errorFromResponse(
    http.Response response,
    String? headerRequestId,
  ) {
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      decoded = null;
    }
    if (decoded is Map) {
      final body = Map<String, Object?>.from(decoded);
      final code = body['code'];
      final requestId = body['request_id'] is String
          ? body['request_id'] as String
          : headerRequestId;
      if (code is String) {
        return GenerationApiFailure(
          code: _failureCodeFromStableCode(code),
          statusCode: response.statusCode,
          requestId: requestId,
          mayHaveCompleted: code == 'PROVIDER_TIMEOUT' || response.statusCode == 504,
        );
      }
    }
    return GenerationApiFailure(
      code: _failureCodeFromStatus(response.statusCode),
      statusCode: response.statusCode,
      requestId: headerRequestId,
      mayHaveCompleted: response.statusCode == 504,
    );
  }

  String? _requestIdFromHeaders(Map<String, String> headers) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'x-request-id' && entry.value.isNotEmpty) {
        return entry.value;
      }
    }
    return null;
  }
}

GenerationFailureCode _failureCodeFromStableCode(String code) => switch (code) {
  'INVALID_REQUEST' => GenerationFailureCode.invalidRequest,
  'UNAUTHENTICATED' => GenerationFailureCode.unauthenticated,
  'FORBIDDEN' => GenerationFailureCode.forbidden,
  'INPUT_TOO_LARGE' => GenerationFailureCode.inputTooLarge,
  'UNSUPPORTED_MEDIA_TYPE' => GenerationFailureCode.unsupportedMediaType,
  'VALIDATION_ERROR' => GenerationFailureCode.validationError,
  'RATE_LIMITED' => GenerationFailureCode.rateLimited,
  'INTERNAL_ERROR' => GenerationFailureCode.internalError,
  'PROVIDER_INVALID_RESPONSE' => GenerationFailureCode.providerInvalidResponse,
  'PROVIDER_UNAVAILABLE' => GenerationFailureCode.providerUnavailable,
  'PROVIDER_TIMEOUT' => GenerationFailureCode.providerTimeout,
  _ => GenerationFailureCode.unknown,
};

GenerationFailureCode _failureCodeFromStatus(int status) => switch (status) {
  400 || 404 || 405 => GenerationFailureCode.invalidRequest,
  401 => GenerationFailureCode.unauthenticated,
  403 => GenerationFailureCode.forbidden,
  413 => GenerationFailureCode.inputTooLarge,
  415 => GenerationFailureCode.unsupportedMediaType,
  422 => GenerationFailureCode.validationError,
  429 => GenerationFailureCode.rateLimited,
  502 => GenerationFailureCode.providerInvalidResponse,
  503 => GenerationFailureCode.providerUnavailable,
  504 => GenerationFailureCode.providerTimeout,
  >= 500 => GenerationFailureCode.internalError,
  _ => GenerationFailureCode.unknown,
};
