import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:resbud_mobile/features/generation/generation_api_client.dart';
import 'package:resbud_mobile/features/generation/generation_models.dart';

import 'helpers/fake_generation_api.dart';

void main() {
  group('GenerationRequest serialization', () {
    Map<String, Object?> validProject() => {
      'title': 'Test Paper',
      'research_field': 'Computer Science',
      'research_question': 'Does unit testing improve code quality?',
      'objectives': ['Measure defect rates'],
      'claimed_contribution': 'A new framework',
      'methodology_status': 'provided',
      'methodology': 'Controlled experiment with 100 participants.',
      'dataset_or_materials_status': 'not_available',
      'results_status': 'not_collected',
      'limitations_status': 'not_identified',
      'references': [
        {'id': 'ref_1', 'text': 'Smith (2024). Testing matters.'},
      ],
      'preferences': {
        'target_word_count': 2000,
        'desired_sections': ['introduction', 'methodology', 'results'],
        'citation_style': 'apa_7',
      },
    };

    test('round-trips through JSON encoding', () {
      final request = GenerationRequest.fromInputs(
        project: validProject(),
        sourceDraft: 'A study on testing.',
      );
      final json = jsonDecode(request.encode()) as Map<String, Object?>;
      expect(json['schema_version'], 1);
      expect(json['source_draft'], 'A study on testing.');
      final project = json['project'] as Map<String, Object?>;
      expect(project['title'], 'Test Paper');
      expect(project['research_field'], 'Computer Science');
    });

    test('accepts project containing figures and transient fields without throwing unsupported fields error', () {
      final proj = validProject();
      proj['figures'] = [
        {'id': 'fig_1', 'caption': 'Pipeline diagram', 'description': 'Overview'}
      ];
      proj['description'] = 'Some description';
      proj['creation_mode'] = 'document';

      final request = GenerationRequest.fromInputs(
        project: proj,
        sourceDraft: 'Source draft with attached figure.',
      );
      expect(request.project.title, 'Test Paper');
    });

    test('rejects empty source draft', () {
      expect(
        () => GenerationRequest.fromInputs(
          project: validProject(),
          sourceDraft: '   ',
        ),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('1–50,000'),
        )),
      );
    });

    test('rejects source draft exceeding 50000 characters', () {
      expect(
        () => GenerationRequest.fromInputs(
          project: validProject(),
          sourceDraft: 'x' * 50001,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects more than 50 references', () {
      final project = validProject();
      project['references'] = List.generate(
        51,
        (i) => {'id': 'ref_$i', 'text': 'Reference $i'},
      );
      expect(
        () => GenerationRequest.fromInputs(
          project: project,
          sourceDraft: 'A study.',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects empty objectives', () {
      final project = validProject();
      project['objectives'] = <String>[];
      expect(
        () => GenerationRequest.fromInputs(
          project: project,
          sourceDraft: 'A study.',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects missing methodology details when status is provided', () {
      final project = validProject();
      project['methodology_status'] = 'provided';
      project['methodology'] = null;
      expect(
        () => GenerationRequest.fromInputs(
          project: project,
          sourceDraft: 'A study.',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('accepts valid word count boundaries', () {
      final project = validProject();
      (project['preferences'] as Map<String, Object?>)['target_word_count'] =
          500;
      expect(
        () => GenerationRequest.fromInputs(
          project: project,
          sourceDraft: 'A study.',
        ),
        returnsNormally,
      );

      (project['preferences'] as Map<String, Object?>)['target_word_count'] =
          8000;
      expect(
        () => GenerationRequest.fromInputs(
          project: project,
          sourceDraft: 'A study.',
        ),
        returnsNormally,
      );
    });

    test('rejects out-of-range word count', () {
      final project = validProject();
      (project['preferences'] as Map<String, Object?>)['target_word_count'] =
          499;
      expect(
        () => GenerationRequest.fromInputs(
          project: project,
          sourceDraft: 'A study.',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('GenerationResponse parsing', () {
    test('parses a valid response', () {
      final json = FakeGenerationApi.defaultResponseJson();
      final response = GenerationResponse.fromJson(json);
      expect(response.generationId, '550e8400-e29b-41d4-a716-446655440000');
      expect(response.paper.title, 'Test Paper Title');
      expect(response.paper.sections.length, 3);
      expect(response.reviewWarnings.length, 1);
      expect(response.meta.providerName, 'fake');
    });

    test('rejects unsupported schema version', () {
      final json = FakeGenerationApi.defaultResponseJson();
      json['schema_version'] = 2;
      expect(
        () => GenerationResponse.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-UUID generation_id', () {
      final json = FakeGenerationApi.defaultResponseJson();
      json['generation_id'] = 'not-a-uuid';
      expect(
        () => GenerationResponse.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects mismatched warnings between response and paper', () {
      final json = FakeGenerationApi.defaultResponseJson();
      (json['paper'] as Map<String, Object?>)['review_warnings'] = <Object>[];
      expect(
        () => GenerationResponse.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects duplicate section IDs', () {
      final json = FakeGenerationApi.defaultResponseJson();
      final paper = json['paper'] as Map<String, Object?>;
      paper['sections'] = [
        {'id': 'introduction', 'heading': 'Intro', 'content': 'X', 'state': 'draft'},
        {'id': 'introduction', 'heading': 'Intro Again', 'content': 'Y', 'state': 'draft'},
      ];
      expect(
        () => GenerationResponse.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('GenerationApiFailure error code mapping', () {
    test('maps each stable code to the correct failure code', () {
      const mapping = {
        'INVALID_REQUEST': GenerationFailureCode.invalidRequest,
        'UNAUTHENTICATED': GenerationFailureCode.unauthenticated,
        'FORBIDDEN': GenerationFailureCode.forbidden,
        'INPUT_TOO_LARGE': GenerationFailureCode.inputTooLarge,
        'UNSUPPORTED_MEDIA_TYPE': GenerationFailureCode.unsupportedMediaType,
        'VALIDATION_ERROR': GenerationFailureCode.validationError,
        'RATE_LIMITED': GenerationFailureCode.rateLimited,
        'INTERNAL_ERROR': GenerationFailureCode.internalError,
        'PROVIDER_INVALID_RESPONSE': GenerationFailureCode.providerInvalidResponse,
        'PROVIDER_UNAVAILABLE': GenerationFailureCode.providerUnavailable,
        'PROVIDER_TIMEOUT': GenerationFailureCode.providerTimeout,
      };
      for (final entry in mapping.entries) {
        final failure = GenerationApiFailure(code: entry.value);
        expect(failure.code, entry.value);
        expect(failure.userMessage, isNotEmpty);
      }
    });

    test('unknown code produces a user-visible message', () {
      const failure = GenerationApiFailure(code: GenerationFailureCode.unknown);
      expect(failure.userMessage, isNotEmpty);
      expect(failure.userMessage, isNot(contains('null')));
    });

    test('retryNotice warns about potential duplicate when mayHaveCompleted', () {
      const failure = GenerationApiFailure(
        code: GenerationFailureCode.providerTimeout,
        mayHaveCompleted: true,
      );
      expect(failure.retryNotice, contains('may still have completed'));
    });

    test('retryNotice is simpler when mayHaveCompleted is false', () {
      const failure = GenerationApiFailure(
        code: GenerationFailureCode.internalError,
      );
      expect(failure.retryNotice, isNot(contains('may still have completed')));
    });

    test('supportDetail includes request ID when present', () {
      const failure = GenerationApiFailure(
        code: GenerationFailureCode.internalError,
        requestId: 'abc-123',
      );
      expect(failure.supportDetail, contains('abc-123'));
    });
  });

  group('GenerationApiClient HTTP Client', () {
    final validRequest = GenerationRequest.fromInputs(
      project: _minimalProject(),
      sourceDraft: 'Some research text.',
    );

    test('successful POST returns GenerationResult with request ID from header', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/generations');
        expect(request.headers['content-type'], 'application/json');
        expect(request.headers['accept'], 'application/json');
        return http.Response(
          jsonEncode(FakeGenerationApi.defaultResponseJson()),
          200,
          headers: {'x-request-id': 'req-header-123'},
        );
      });

      final client = GenerationApiClient(
        baseUri: Uri.parse('http://127.0.0.1:8000'),
        client: mock,
      );
      final result = await client.generate(validRequest);
      expect(result.requestId, 'req-header-123');
      expect(result.response.paper.title, 'Test Paper Title');
    });

    test('passes bearer token when tokenProvider is configured', () async {
      final mock = MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer test-token-secret');
        return http.Response(
          jsonEncode(FakeGenerationApi.defaultResponseJson()),
          200,
        );
      });

      final client = GenerationApiClient(
        baseUri: Uri.parse('http://127.0.0.1:8000'),
        client: mock,
        tokenProvider: () async => 'test-token-secret',
      );
      final result = await client.generate(validRequest);
      expect(result.response.paper.title, isNotEmpty);
    });

    test('parses stable error codes and request_id from error JSON', () async {
      for (final code in [
        'INVALID_REQUEST',
        'UNAUTHENTICATED',
        'FORBIDDEN',
        'INPUT_TOO_LARGE',
        'UNSUPPORTED_MEDIA_TYPE',
        'VALIDATION_ERROR',
        'RATE_LIMITED',
        'INTERNAL_ERROR',
        'PROVIDER_INVALID_RESPONSE',
        'PROVIDER_UNAVAILABLE',
        'PROVIDER_TIMEOUT',
      ]) {
        final mock = MockClient((request) async => http.Response(
          jsonEncode({'code': code, 'request_id': 'req-$code'}),
          400,
        ));
        final client = GenerationApiClient(
          baseUri: Uri.parse('http://127.0.0.1:8000'),
          client: mock,
        );
        expect(
          () => client.generate(validRequest),
          throwsA(
            isA<GenerationApiFailure>()
                .having((f) => f.requestId, 'requestId', 'req-$code')
                .having(
                  (f) => f.code,
                  'code',
                  switch (code) {
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
                  },
                ),
          ),
        );
      }
    });

    test('maps HTTP status codes when body is not structured JSON', () async {
      final statuses = {
        400: GenerationFailureCode.invalidRequest,
        401: GenerationFailureCode.unauthenticated,
        403: GenerationFailureCode.forbidden,
        413: GenerationFailureCode.inputTooLarge,
        415: GenerationFailureCode.unsupportedMediaType,
        422: GenerationFailureCode.validationError,
        429: GenerationFailureCode.rateLimited,
        500: GenerationFailureCode.internalError,
        502: GenerationFailureCode.providerInvalidResponse,
        503: GenerationFailureCode.providerUnavailable,
        504: GenerationFailureCode.providerTimeout,
      };

      for (final entry in statuses.entries) {
        final mock = MockClient(
          (request) async => http.Response('plain text error', entry.key),
        );
        final client = GenerationApiClient(
          baseUri: Uri.parse('http://127.0.0.1:8000'),
          client: mock,
        );
        expect(
          () => client.generate(validRequest),
          throwsA(
            isA<GenerationApiFailure>().having((f) => f.code, 'code', entry.value),
          ),
        );
      }
    });

    test('handles TimeoutException and marks mayHaveCompleted = true', () async {
      final mock = MockClient((request) async {
        throw TimeoutException('Timed out');
      });
      final client = GenerationApiClient(
        baseUri: Uri.parse('http://127.0.0.1:8000'),
        client: mock,
      );
      expect(
        () => client.generate(validRequest),
        throwsA(
          isA<GenerationApiFailure>()
              .having((f) => f.code, 'code', GenerationFailureCode.providerTimeout)
              .having((f) => f.mayHaveCompleted, 'mayHaveCompleted', isTrue),
        ),
      );
    });

    test('handles SocketException as networkUnavailable', () async {
      final mock = MockClient((request) async {
        throw const SocketException('Connection refused');
      });
      final client = GenerationApiClient(
        baseUri: Uri.parse('http://127.0.0.1:8000'),
        client: mock,
      );
      expect(
        () => client.generate(validRequest),
        throwsA(
          isA<GenerationApiFailure>().having(
            (f) => f.code,
            'code',
            GenerationFailureCode.networkUnavailable,
          ),
        ),
      );
    });

    test('handles ClientException as networkUnavailable', () async {
      final mock = MockClient((request) async {
        throw http.ClientException('Network drop');
      });
      final client = GenerationApiClient(
        baseUri: Uri.parse('http://127.0.0.1:8000'),
        client: mock,
      );
      expect(
        () => client.generate(validRequest),
        throwsA(
          isA<GenerationApiFailure>().having(
            (f) => f.code,
            'code',
            GenerationFailureCode.networkUnavailable,
          ),
        ),
      );
    });

    test('handles malformed 200 response body as invalidResponse', () async {
      final mock = MockClient((request) async => http.Response('not json', 200));
      final client = GenerationApiClient(
        baseUri: Uri.parse('http://127.0.0.1:8000'),
        client: mock,
      );
      expect(
        () => client.generate(validRequest),
        throwsA(
          isA<GenerationApiFailure>().having(
            (f) => f.code,
            'code',
            GenerationFailureCode.invalidResponse,
          ),
        ),
      );
    });

    test('validates baseUri configuration', () {
      expect(
        () => GenerationApiClient(baseUri: Uri.parse('ftp://example.com')),
        throwsArgumentError,
      );
      expect(
        () => GenerationApiClient(baseUri: Uri.parse('http:///path')),
        throwsArgumentError,
      );
      expect(
        () => GenerationApiClient(
          baseUri: Uri.parse('http://example.com'),
          timeout: Duration.zero,
        ),
        throwsArgumentError,
      );
    });
  });

  group('SectionRegenerationRequest serialization', () {
    final validProjectReq = GenerationRequest.fromInputs(
      project: _minimalProject(),
      sourceDraft: 'Some research draft text.',
    );
    final validPaper =
        FakeGenerationApi.defaultResponseJson()['paper'] as Map<String, Object?>;
    final paperDraft = PaperDraftPayload.fromJson(validPaper);

    test('creates and serializes valid SectionRegenerationRequest', () {
      final req = SectionRegenerationRequest.create(
        generationRequest: validProjectReq,
        currentPaper: paperDraft,
        sectionId: 'methodology',
        userInstruction: 'Please add details on the test setup.',
      );
      final json = jsonDecode(req.encode()) as Map<String, Object?>;
      expect(json['schema_version'], 1);
      expect(json['section_id'], 'methodology');
      expect(json['user_instruction'], 'Please add details on the test setup.');
      expect(json['generation_request'], isA<Map<String, Object?>>());
      expect(json['current_paper'], isA<Map<String, Object?>>());
    });

    test('rejects target section that does not exist in current paper', () {
      expect(
        () => SectionRegenerationRequest.create(
          generationRequest: validProjectReq,
          currentPaper: paperDraft,
          sectionId: 'non_existent_section',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects not_applicable section regeneration', () {
      final naPaper = paperDraft.copyWith(
        sections: [
          ...paperDraft.sections,
          const PaperSectionPayload(
            id: 'extra_na',
            heading: 'Extra',
            content: 'Not applicable',
            state: 'not_applicable',
          ),
        ],
      );
      expect(
        () => SectionRegenerationRequest.create(
          generationRequest: validProjectReq,
          currentPaper: naPaper,
          sectionId: 'extra_na',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects user_instruction exceeding 2000 chars', () {
      expect(
        () => SectionRegenerationRequest.create(
          generationRequest: validProjectReq,
          currentPaper: paperDraft,
          sectionId: 'methodology',
          userInstruction: 'x' * 2001,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('SectionRegenerationResponse parsing', () {
    test('parses valid section regeneration response', () {
      final json = {
        'schema_version': 1,
        'section': {
          'id': 'methodology',
          'heading': 'Methodology',
          'content': 'Updated methodology content.',
          'state': 'draft',
        },
        'review_warnings': [
          {
            'code': 'GENERAL_REVIEW',
            'severity': 'info',
            'message': 'Review updated methodology.',
            'section_id': 'methodology',
          },
        ],
      };
      final resp = SectionRegenerationResponse.fromJson(json);
      expect(resp.section.id, 'methodology');
      expect(resp.section.content, 'Updated methodology content.');
      expect(resp.reviewWarnings.length, 1);
    });

    test('rejects empty replacement section content', () {
      final json = {
        'schema_version': 1,
        'section': {
          'id': 'methodology',
          'heading': 'Methodology',
          'content': '   ',
          'state': 'draft',
        },
        'review_warnings': <Object>[],
      };
      expect(
        () => SectionRegenerationResponse.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects not_applicable replacement section', () {
      final json = {
        'schema_version': 1,
        'section': {
          'id': 'methodology',
          'heading': 'Methodology',
          'content': 'Some content',
          'state': 'not_applicable',
        },
        'review_warnings': <Object>[],
      };
      expect(
        () => SectionRegenerationResponse.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('GenerationApiClient.regenerateSection', () {
    final validProjectReq = GenerationRequest.fromInputs(
      project: _minimalProject(),
      sourceDraft: 'Some research draft text.',
    );
    final validPaper =
        FakeGenerationApi.defaultResponseJson()['paper'] as Map<String, Object?>;
    final paperDraft = PaperDraftPayload.fromJson(validPaper);
    final regenRequest = SectionRegenerationRequest.create(
      generationRequest: validProjectReq,
      currentPaper: paperDraft,
      sectionId: 'methodology',
    );

    test('successful POST returns SectionRegenerationResult with header request ID', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/generations/sections');
        return http.Response(
          jsonEncode({
            'schema_version': 1,
            'section': {
              'id': 'methodology',
              'heading': 'Methodology',
              'content': 'Brand new methodology text.',
              'state': 'draft',
            },
            'review_warnings': <Object>[],
          }),
          200,
          headers: {'x-request-id': 'sec-req-999'},
        );
      });
      final client = GenerationApiClient(
        baseUri: Uri.parse('http://127.0.0.1:8000'),
        client: mock,
      );
      final result = await client.regenerateSection(regenRequest);
      expect(result.requestId, 'sec-req-999');
      expect(result.response.section.id, 'methodology');
      expect(result.response.section.content, 'Brand new methodology text.');
    });

    test('throws invalidResponse if response section ID does not match request', () async {
      final mock = MockClient((request) async => http.Response(
        jsonEncode({
          'schema_version': 1,
          'section': {
            'id': 'introduction',
            'heading': 'Intro',
            'content': 'Wrong section content.',
            'state': 'draft',
          },
          'review_warnings': <Object>[],
        }),
        200,
      ));
      final client = GenerationApiClient(
        baseUri: Uri.parse('http://127.0.0.1:8000'),
        client: mock,
      );
      expect(
        () => client.regenerateSection(regenRequest),
        throwsA(
          isA<GenerationApiFailure>().having(
            (f) => f.code,
            'code',
            GenerationFailureCode.invalidResponse,
          ),
        ),
      );
    });
  });

  group('FakeGenerationApi', () {
    late FakeGenerationApi fakeApi;

    setUp(() => fakeApi = FakeGenerationApi());

    test('returns a valid default result', () async {
      final request = GenerationRequest.fromInputs(
        project: _minimalProject(),
        sourceDraft: 'Some research text.',
      );
      final result = await fakeApi.generate(request);
      expect(result.response.paper.title, isNotEmpty);
      expect(result.requestId, 'test-request-id-001');
      expect(fakeApi.callCount, 1);
      expect(fakeApi.lastRequest, same(request));
    });

    test('throws the configured error', () async {
      fakeApi.nextError = const GenerationApiFailure(
        code: GenerationFailureCode.providerTimeout,
        mayHaveCompleted: true,
      );
      final request = GenerationRequest.fromInputs(
        project: _minimalProject(),
        sourceDraft: 'Some research text.',
      );
      expect(
        () => fakeApi.generate(request),
        throwsA(isA<GenerationApiFailure>()),
      );
    });

    test('clears the error after throwing it once', () async {
      fakeApi.nextError = const GenerationApiFailure(
        code: GenerationFailureCode.rateLimited,
      );
      final request = GenerationRequest.fromInputs(
        project: _minimalProject(),
        sourceDraft: 'Some research text.',
      );
      try {
        await fakeApi.generate(request);
      } on GenerationApiFailure {
        // expected
      }
      final result = await fakeApi.generate(request);
      expect(result.response.paper.title, isNotEmpty);
      expect(fakeApi.callCount, 2);
    });

    test('returns a custom result when configured', () async {
      final customJson = FakeGenerationApi.defaultResponseJson();
      (customJson['paper'] as Map<String, Object?>)['title'] = 'Custom title';
      fakeApi.nextResult = GenerationResult(
        response: GenerationResponse.fromJson(customJson),
        requestId: 'custom-id',
      );
      final request = GenerationRequest.fromInputs(
        project: _minimalProject(),
        sourceDraft: 'Some research text.',
      );
      final result = await fakeApi.generate(request);
      expect(result.response.paper.title, 'Custom title');
      expect(result.requestId, 'custom-id');
    });
  });

  group('PaperSectionPayload', () {
    test('rejects invalid section state', () {
      expect(
        () => PaperSectionPayload.fromJson({
          'id': 'introduction',
          'heading': 'Intro',
          'content': 'Content',
          'state': 'invalid_state',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('accepts all valid section states', () {
      for (final state in ['draft', 'needs_input', 'not_applicable']) {
        final section = PaperSectionPayload.fromJson({
          'id': 'test_section',
          'heading': 'Test',
          'content': 'Content',
          'state': state,
        });
        expect(section.state, state);
      }
    });
  });

  group('ReviewWarningPayload', () {
    test('accepts all valid warning codes', () {
      for (final code in [
        'MISSING_METHOD',
        'MISSING_DATASET_DETAILS',
        'MISSING_RESULTS',
        'MISSING_LIMITATIONS',
        'CITATION_NEEDED',
        'REFERENCE_INCOMPLETE',
        'CLAIM_NEEDS_REVIEW',
        'INPUT_CONFLICT',
        'SECTION_NOT_APPLICABLE',
        'GENERAL_REVIEW',
      ]) {
        final warning = ReviewWarningPayload.fromJson({
          'code': code,
          'severity': 'info',
          'message': 'test message',
          'section_id': null,
        });
        expect(warning.code, code);
      }
    });

    test('round-trips through JSON', () {
      final warning = ReviewWarningPayload.fromJson({
        'code': 'MISSING_RESULTS',
        'severity': 'warning',
        'message': 'Results needed.',
        'section_id': 'results',
      });
      final json = warning.toJson();
      expect(json['code'], 'MISSING_RESULTS');
      expect(json['section_id'], 'results');
      final reparsed = ReviewWarningPayload.fromJson(
        Map<String, Object?>.from(json),
      );
      expect(reparsed.signature(), warning.signature());
    });
  });
}

Map<String, Object?> _minimalProject() => {
  'title': 'Test Paper',
  'research_field': 'CS',
  'research_question': 'Does testing help?',
  'objectives': ['Measure quality'],
  'claimed_contribution': '',
  'methodology_status': 'unknown',
  'dataset_or_materials_status': 'unknown',
  'results_status': 'unknown',
  'limitations_status': 'unknown',
  'references': <Object>[],
  'preferences': {
    'target_word_count': 1500,
    'desired_sections': ['introduction', 'methodology'],
    'citation_style': 'user_supplied',
  },
};
