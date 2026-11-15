import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:resbud_mobile/data/auth_session_manager.dart';
import 'package:resbud_mobile/data/local_project_repository.dart';
import 'package:resbud_mobile/features/auth/auth_session_dialog.dart';

String _createTestJwt({
  String? sub = 'test-researcher',
  String? iss = 'https://resbud-api.onrender.com/auth',
  String? aud = 'resbud-production',
  int? exp,
}) {
  final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'}))).replaceAll('=', '');
  final payload = base64Url.encode(
    utf8.encode(
      jsonEncode({
        if (sub != null) 'sub': sub,
        if (iss != null) 'iss': iss,
        if (aud != null) 'aud': aud,
        if (exp != null) 'exp': exp,
      }),
    ),
  ).replaceAll('=', '');
  const sig = 'fake-sig-for-testing';
  return '$header.$payload.$sig';
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('ParsedTokenInfo Tests', () {
    test('parses claims correctly from standard JWT format', () {
      final nowSec = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final jwt = _createTestJwt(
        sub: 'researcher-42',
        iss: 'https://resbud-api.onrender.com/auth',
        aud: 'resbud-production',
        exp: nowSec + 3600,
      );

      final info = ParsedTokenInfo.parse(jwt);
      expect(info, isNotNull);
      expect(info!.subject, 'researcher-42');
      expect(info.issuer, 'https://resbud-api.onrender.com/auth');
      expect(info.audience, 'resbud-production');
      expect(info.isExpired, isFalse);
    });

    test('detects expired tokens', () {
      final nowSec = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final jwt = _createTestJwt(exp: nowSec - 100);

      final info = ParsedTokenInfo.parse(jwt);
      expect(info, isNotNull);
      expect(info!.isExpired, isTrue);
    });

    test('returns null for malformed tokens', () {
      expect(ParsedTokenInfo.parse('not.a.valid.jwt.four'), isNull);
      expect(ParsedTokenInfo.parse('only-one-part'), isNull);
      expect(ParsedTokenInfo.parse('bad.base64!!.sig'), isNull);
    });
  });

  group('AuthSessionManager Persistence & Lifecycle', () {
    late LocalProjectRepository repository;

    setUp(() async {
      repository = await LocalProjectRepository.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
    });

    tearDown(() async {
      await repository.close();
    });

    test('saves and loads token across manager instances', () async {
      final manager1 = AuthSessionManager(repository);
      await manager1.initialize();
      expect(manager1.hasToken, isFalse);

      final token = _createTestJwt(sub: 'persisted-user');
      await manager1.setToken(token);
      expect(manager1.hasToken, isTrue);
      expect(manager1.token, token);
      expect(manager1.tokenInfo?.subject, 'persisted-user');

      // Create new manager instance to verify SQLite persistence
      final manager2 = AuthSessionManager(repository);
      await manager2.initialize();
      expect(manager2.hasToken, isTrue);
      expect(manager2.token, token);
      expect(manager2.tokenInfo?.subject, 'persisted-user');

      // Clear token
      await manager2.clearToken();
      expect(manager2.hasToken, isFalse);

      // Verify cleared in third instance
      final manager3 = AuthSessionManager(repository);
      await manager3.initialize();
      expect(manager3.hasToken, isFalse);
    });
  });

  group('AuthSessionDialog Widget Tests', () {
    late LocalProjectRepository repository;
    late AuthSessionManager authManager;

    setUp(() async {
      repository = await LocalProjectRepository.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      authManager = AuthSessionManager(repository);
      await authManager.initialize();
    });

    tearDown(() async {
      await repository.close();
    });

    testWidgets('renders dialog and allows entering session token', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => AuthSessionDialog.show(context, authManager),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Backend & Session Authorization'), findsOneWidget);
      expect(find.text('Paste Bearer JWT Token'), findsOneWidget);

      final token = _createTestJwt(sub: 'ui-test-user');
      await tester.enterText(find.byType(TextField), token);
      await tester.runAsync(() async {
        await tester.tap(find.text('Save Token'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(authManager.hasToken, isTrue);
      expect(authManager.token, token);
      expect(authManager.tokenInfo?.subject, 'ui-test-user');
    });
  });
}
