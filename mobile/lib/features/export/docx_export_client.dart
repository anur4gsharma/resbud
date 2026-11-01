import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../generation/generation_api_client.dart';
import '../generation/generation_models.dart';

enum DocxExportFailureCode {
  invalidRequest,
  unauthenticated,
  forbidden,
  inputTooLarge,
  unsupportedMediaType,
  validationError,
  rateLimited,
  internalError,
  invalidResponse,
  networkTimeout,
  networkUnavailable,
  unknown,
}

class DocxExportFailure implements Exception {
  const DocxExportFailure({
    required this.code,
    this.statusCode,
    this.requestId,
    this.details,
  });

  final DocxExportFailureCode code;
  final int? statusCode;
  final String? requestId;
  final String? details;

  String get userMessage => switch (code) {
    DocxExportFailureCode.invalidRequest => 'The server could not process the export request.',
    DocxExportFailureCode.unauthenticated => 'Authentication is required before exporting.',
    DocxExportFailureCode.forbidden => 'This account is not authorized to export papers.',
    DocxExportFailureCode.inputTooLarge => 'The paper exceeds the server export size limit (8 MB).',
    DocxExportFailureCode.unsupportedMediaType => 'The server rejected the export request format.',
    DocxExportFailureCode.validationError => 'The paper content failed server validation. Please check required fields.',
    DocxExportFailureCode.rateLimited => 'Export rate limit reached. Please wait a moment and try again.',
    DocxExportFailureCode.internalError => 'The server encountered an error generating the DOCX document.',
    DocxExportFailureCode.invalidResponse => 'The server returned an invalid or corrupted DOCX document.',
    DocxExportFailureCode.networkTimeout => 'The export request timed out. Please check your connection and retry.',
    DocxExportFailureCode.networkUnavailable => 'Could not connect to the export service. Check network connection.',
    DocxExportFailureCode.unknown => 'DOCX export failed due to an unexpected error.',
  };

  String get supportDetail {
    final buffer = StringBuffer(userMessage);
    if (details != null && details!.trim().isNotEmpty) {
      buffer.write('\n$details');
    }
    if (requestId != null) {
      buffer.write('\nSupport request ID: $requestId');
    }
    return buffer.toString();
  }

  @override
  String toString() => 'DocxExportFailure($code, statusCode: $statusCode, requestId: $requestId)';
}

class DocxExportResult {
  const DocxExportResult({
    required this.bytes,
    required this.suggestedFilename,
    this.requestId,
  });

  final Uint8List bytes;
  final String suggestedFilename;
  final String? requestId;
}

abstract interface class PaperExportApi {
  Future<DocxExportResult> exportDocx(PaperDraftPayload paper);
}

class DocxExportApiClient implements PaperExportApi {
  DocxExportApiClient({
    required this.baseUri,
    http.Client? client,
    this.tokenProvider,
    this.timeout = const Duration(seconds: 180),
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

  factory DocxExportApiClient.fromEnvironment({
    http.Client? client,
    BearerTokenProvider? tokenProvider,
    Duration timeout = const Duration(seconds: 180),
  }) => DocxExportApiClient(
    baseUri: Uri.parse(GenerationApiClient.defaultBaseUrl),
    client: client,
    tokenProvider: tokenProvider,
    timeout: timeout,
  );

  final Uri baseUri;
  final http.Client _client;
  final bool _ownsClient;
  final BearerTokenProvider? tokenProvider;
  final Duration timeout;

  Uri get _exportUri => baseUri.resolve('/api/v1/exports/docx');

  Future<void> close() async {
    if (_ownsClient) _client.close();
  }

  @override
  Future<DocxExportResult> exportDocx(PaperDraftPayload paper) async {
    final token = await tokenProvider?.call();
    final headers = <String, String>{
      'content-type': 'application/json',
      'accept': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    };
    if (token != null && token.trim().isNotEmpty) {
      headers['authorization'] = 'Bearer ${token.trim()}';
    }

    final payloadJson = jsonEncode(paper.toJson());

    late final http.Response response;
    try {
      response = await _client
          .post(
            _exportUri,
            headers: headers,
            body: payloadJson,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const DocxExportFailure(
        code: DocxExportFailureCode.networkTimeout,
      );
    } on SocketException {
      throw const DocxExportFailure(
        code: DocxExportFailureCode.networkUnavailable,
      );
    } on http.ClientException {
      throw const DocxExportFailure(
        code: DocxExportFailureCode.networkUnavailable,
      );
    }

    final requestId = _requestIdFromHeaders(response.headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _errorFromResponse(response, requestId);
    }

    final bytes = response.bodyBytes;
    if (!_isValidDocxBytes(bytes)) {
      throw DocxExportFailure(
        code: DocxExportFailureCode.invalidResponse,
        statusCode: response.statusCode,
        requestId: requestId,
        details: 'The server returned data that is not a valid DOCX document.',
      );
    }

    final suggestedFilename = _extractFilename(
      response.headers['content-disposition'],
      defaultName: safeDocxFilename(paper.title),
    );

    return DocxExportResult(
      bytes: bytes,
      suggestedFilename: suggestedFilename,
      requestId: requestId,
    );
  }

  static bool _isValidDocxBytes(Uint8List bytes) {
    // DOCX files are standard ZIP archives starting with PK\x03\x04 (0x50, 0x4B, 0x03, 0x04)
    // and must not exceed 8 MB.
    if (bytes.length < 4 || bytes.length > 8 * 1024 * 1024) return false;
    return bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
  }

  static String _extractFilename(String? disposition, {required String defaultName}) {
    if (disposition == null || disposition.trim().isEmpty) return defaultName;
    final match = RegExp(r"""filename\*?=(?:UTF-8'')?"?([^";\r\n]+)"?""", caseSensitive: false)
        .firstMatch(disposition);
    if (match != null) {
      final name = match.group(1)?.trim();
      if (name != null && name.isNotEmpty) return name;
    }
    return defaultName;
  }

  static String? _requestIdFromHeaders(Map<String, String> headers) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'x-request-id') {
        final value = entry.value.trim();
        return value.isEmpty ? null : value;
      }
    }
    return null;
  }

  static DocxExportFailure _errorFromResponse(http.Response response, String? requestId) {
    String? details;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] is String) {
          details = error['message'] as String;
        } else if (decoded['detail'] is String) {
          details = decoded['detail'] as String;
        }
      }
    } catch (_) {
      // Body may be plain text or unparseable.
      if (response.body.isNotEmpty && response.body.length < 500) {
        details = response.body;
      }
    }

    final code = switch (response.statusCode) {
      400 => DocxExportFailureCode.invalidRequest,
      401 => DocxExportFailureCode.unauthenticated,
      403 => DocxExportFailureCode.forbidden,
      413 => DocxExportFailureCode.inputTooLarge,
      415 => DocxExportFailureCode.unsupportedMediaType,
      422 => DocxExportFailureCode.validationError,
      429 => DocxExportFailureCode.rateLimited,
      500 => DocxExportFailureCode.internalError,
      _ => DocxExportFailureCode.unknown,
    };

    return DocxExportFailure(
      code: code,
      statusCode: response.statusCode,
      requestId: requestId,
      details: details,
    );
  }
}

String safeDocxFilename(String title) {
  final slug = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final clamped = slug.length > 64 ? slug.substring(0, 64).replaceAll(RegExp(r'^-+|-+$'), '') : slug;
  return 'resbud-${clamped.isEmpty ? 'research-paper' : clamped}.docx';
}
