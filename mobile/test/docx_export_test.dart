import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import 'package:resbud_mobile/features/export/docx_export_client.dart';
import 'package:resbud_mobile/features/export/docx_file_saver.dart';
import 'package:resbud_mobile/features/generation/generation_models.dart';

void main() {
  group('safeDocxFilename', () {
    test('creates human-readable ASCII slug with resbud prefix', () {
      expect(
        safeDocxFilename('Quantum Computing in 2026: A Review!'),
        'resbud-quantum-computing-in-2026-a-review.docx',
      );
      expect(
        safeDocxFilename('   '),
        'resbud-research-paper.docx',
      );
    });
  });

  group('DocxExportApiClient', () {
    final validDocxBytes = Uint8List.fromList([
      0x50, 0x4B, 0x03, 0x04, // PK\x03\x04
      0x14, 0x00, 0x06, 0x00,
      0x08, 0x00, 0x00, 0x00,
    ]);

    const samplePaper = PaperDraftPayload(
      schemaVersion: 1,
      title: 'Quantum Computing Overview',
      abstractText: 'This is a brief summary.',
      keywords: const ['quantum', 'algorithms'],
      sections: const [
        PaperSectionPayload(
          id: 'intro',
          heading: 'Introduction',
          content: 'Introductory content.',
          state: 'draft',
        ),
      ],
      references: const [
        ReferencePayload(id: 'ref1', text: 'Author (2025). Paper.'),
      ],
      reviewWarnings: const [],
    );

    test('successfully exports paper with disposition header and request id', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/v1/exports/docx');
        expect(request.method, 'POST');
        expect(
          request.headers['accept'],
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        );
        expect(request.headers['content-type'], 'application/json');

        final body = jsonDecode(request.body) as Map<String, Object?>;
        expect(body['title'], 'Quantum Computing Overview');

        return http.Response.bytes(
          validDocxBytes,
          200,
          headers: {
            'content-disposition': 'attachment; filename="quantum-overview.docx"',
            'x-request-id': 'req-export-123',
          },
        );
      });

      final client = DocxExportApiClient(
        baseUri: Uri.parse('https://api.example.com'),
        client: mockClient,
      );

      final result = await client.exportDocx(samplePaper);
      expect(result.bytes, validDocxBytes);
      expect(result.suggestedFilename, 'quantum-overview.docx');
      expect(result.requestId, 'req-export-123');
    });

    test('falls back to safe title slug if disposition header is missing', () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          validDocxBytes,
          200,
          headers: {},
        );
      });

      final client = DocxExportApiClient(
        baseUri: Uri.parse('https://api.example.com'),
        client: mockClient,
      );

      final result = await client.exportDocx(samplePaper);
      expect(result.suggestedFilename, 'resbud-quantum-computing-overview.docx');
      expect(result.requestId, isNull);
    });

    test('rejects response with invalid DOCX magic bytes', () async {
      final invalidBytes = Uint8List.fromList([0x12, 0x34, 0x56, 0x78]);
      final mockClient = MockClient((request) async {
        return http.Response.bytes(invalidBytes, 200);
      });

      final client = DocxExportApiClient(
        baseUri: Uri.parse('https://api.example.com'),
        client: mockClient,
      );

      expect(
        () => client.exportDocx(samplePaper),
        throwsA(isA<DocxExportFailure>().having(
          (e) => e.code,
          'code',
          DocxExportFailureCode.invalidResponse,
        )),
      );
    });

    test('maps 422 validation error with server error message', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {'code': 'VALIDATION_ERROR', 'message': 'Invalid paper title'},
          }),
          422,
          headers: {'x-request-id': 'req-err-422'},
        );
      });

      final client = DocxExportApiClient(
        baseUri: Uri.parse('https://api.example.com'),
        client: mockClient,
      );

      try {
        await client.exportDocx(samplePaper);
        fail('Expected DocxExportFailure');
      } on DocxExportFailure catch (failure) {
        expect(failure.code, DocxExportFailureCode.validationError);
        expect(failure.statusCode, 422);
        expect(failure.requestId, 'req-err-422');
        expect(failure.details, 'Invalid paper title');
        expect(failure.supportDetail, contains('Invalid paper title'));
        expect(failure.supportDetail, contains('req-err-422'));
      }
    });

    test('maps 413 payload too large error', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Payload Too Large', 413);
      });

      final client = DocxExportApiClient(
        baseUri: Uri.parse('https://api.example.com'),
        client: mockClient,
      );

      expect(
        () => client.exportDocx(samplePaper),
        throwsA(isA<DocxExportFailure>().having(
          (e) => e.code,
          'code',
          DocxExportFailureCode.inputTooLarge,
        )),
      );
    });

    test('maps network errors to networkUnavailable', () async {
      final mockClient = MockClient((request) async {
        throw const SocketException('Connection refused');
      });

      final client = DocxExportApiClient(
        baseUri: Uri.parse('https://api.example.com'),
        client: mockClient,
      );

      expect(
        () => client.exportDocx(samplePaper),
        throwsA(isA<DocxExportFailure>().having(
          (e) => e.code,
          'code',
          DocxExportFailureCode.networkUnavailable,
        )),
      );
    });

    test('sends bearer token if token provider is supplied', () async {
      String? sentAuth;
      final mockClient = MockClient((request) async {
        sentAuth = request.headers['authorization'];
        return http.Response.bytes(validDocxBytes, 200);
      });

      final client = DocxExportApiClient(
        baseUri: Uri.parse('https://api.example.com'),
        client: mockClient,
        tokenProvider: () async => 'test-bearer-secret',
      );

      await client.exportDocx(samplePaper);
      expect(sentAuth, 'Bearer test-bearer-secret');
    });
  });

  group('LocalDocxFileSaver', () {
    late Directory tempDir;
    late LocalDocxFileSaver saver;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('resbud-saver-test-');
      saver = LocalDocxFileSaver(targetDirectory: tempDir);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('saves bytes and returns correct path', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final path = await saver.saveDocx(
        bytes: bytes,
        suggestedFilename: 'paper.docx',
      );

      expect(path, p.join(tempDir.path, 'paper.docx'));
      final savedFile = File(path);
      expect(savedFile.existsSync(), isTrue);
      expect(savedFile.readAsBytesSync(), bytes);
    });

    test('disallows saving empty bytes', () async {
      expect(
        () => saver.saveDocx(
          bytes: Uint8List(0),
          suggestedFilename: 'empty.docx',
        ),
        throwsA(isA<DocxFileSaverException>()),
      );
    });

    test('sanitizes unsafe filenames with traversal and forbidden characters', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final path = await saver.saveDocx(
        bytes: bytes,
        suggestedFilename: '../../nested/evil:file?name*.docx',
      );

      // Traversal and forbidden chars replaced
      expect(p.dirname(path), tempDir.path);
      expect(p.basename(path), isNot(contains('/')));
      expect(p.basename(path), isNot(contains(':')));
      expect(p.basename(path), isNot(contains('?')));
      expect(p.basename(path), isNot(contains('*')));
      expect(p.extension(path), '.docx');
    });

    test('resolves duplicate filenames with monotonic counter', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);

      final path1 = await saver.saveDocx(
        bytes: bytes,
        suggestedFilename: 'summary.docx',
      );
      expect(p.basename(path1), 'summary.docx');

      final path2 = await saver.saveDocx(
        bytes: bytes,
        suggestedFilename: 'summary.docx',
      );
      expect(p.basename(path2), 'summary (1).docx');

      final path3 = await saver.saveDocx(
        bytes: bytes,
        suggestedFilename: 'summary.docx',
      );
      expect(p.basename(path3), 'summary (2).docx');

      // Also handles when suggested name already has (1)
      final path4 = await saver.saveDocx(
        bytes: bytes,
        suggestedFilename: 'summary (1).docx',
      );
      expect(p.basename(path4), 'summary (3).docx');
    });
  });
}
