import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'local_project_repository.dart';

/// Parsed metadata from a JWT Bearer token without requiring the secret key.
class ParsedTokenInfo {
  const ParsedTokenInfo({
    required this.token,
    required this.subject,
    required this.issuer,
    required this.audience,
    required this.expiresAt,
    required this.isExpired,
  });

  final String token;
  final String? subject;
  final String? issuer;
  final String? audience;
  final DateTime? expiresAt;
  final bool isExpired;

  static ParsedTokenInfo? parse(String rawToken) {
    final trimmed = rawToken.trim();
    final parts = trimmed.split('.');
    if (parts.length != 3) return null;

    try {
      String payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final jsonMap = jsonDecode(utf8.decode(base64Decode(payload))) as Map<String, Object?>;

      final expNum = jsonMap['exp'];
      DateTime? exp;
      if (expNum is num) {
        exp = DateTime.fromMillisecondsSinceEpoch(
          (expNum * 1000).toInt(),
          isUtc: true,
        );
      }

      final now = DateTime.now().toUtc();
      final isExp = exp != null && now.isAfter(exp);

      return ParsedTokenInfo(
        token: trimmed,
        subject: jsonMap['sub'] as String?,
        issuer: jsonMap['iss'] as String?,
        audience: jsonMap['aud'] as String?,
        expiresAt: exp,
        isExpired: isExp,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Manages client-side JWT token storage, inspection, and lifecycle.
class AuthSessionManager extends ChangeNotifier {
  AuthSessionManager(this._repository);

  final LocalProjectRepository _repository;
  static const _settingKey = 'session_bearer_token';

  String? _token;
  ParsedTokenInfo? _tokenInfo;

  String? get token => _token;
  ParsedTokenInfo? get tokenInfo => _tokenInfo;
  bool get hasToken => _token != null && _token!.isNotEmpty;
  bool get isValid => hasToken && (_tokenInfo == null || !_tokenInfo!.isExpired);

  /// Load persisted session token on startup.
  Future<void> initialize() async {
    String? stored = await _repository.getSetting(_settingKey);
    if (stored == null || stored.trim().isEmpty) {
      const envToken = String.fromEnvironment('RESBUD_AUTH_TOKEN');
      if (envToken.trim().isNotEmpty) {
        stored = envToken.trim();
      }
    }

    if (stored != null && stored.trim().isNotEmpty) {
      _token = stored.trim();
      _tokenInfo = ParsedTokenInfo.parse(_token!);
      notifyListeners();
    }
  }

  /// Provider callback for GenerationApiClient and DocxExportApiClient.
  Future<String?> getToken() async => _token;

  /// Save and activate a new session token.
  Future<void> setToken(String newToken) async {
    final clean = newToken.trim();
    if (clean.isEmpty) {
      await clearToken();
      return;
    }
    _token = clean;
    _tokenInfo = ParsedTokenInfo.parse(clean);
    await _repository.setSetting(_settingKey, clean);
    notifyListeners();
  }

  /// Remove current session token.
  Future<void> clearToken() async {
    _token = null;
    _tokenInfo = null;
    await _repository.deleteSetting(_settingKey);
    notifyListeners();
  }
}
