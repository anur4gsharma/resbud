import 'package:resbud_mobile/features/generation/generation_api_client.dart';
import 'package:resbud_mobile/features/generation/generation_models.dart';

/// Deterministic fake [PaperGenerationApi] for widget and unit tests.
///
/// By default returns a successful result built from [_defaultResponse].
/// Override [nextResult] to return a custom [GenerationResult], or set
/// [nextError] to make the next call throw.
class FakeGenerationApi implements PaperGenerationApi {
  GenerationResult? nextResult;
  Object? nextError;
  int callCount = 0;
  GenerationRequest? lastRequest;

  SectionRegenerationResult? nextSectionResult;
  Object? nextSectionError;
  int sectionCallCount = 0;
  SectionRegenerationRequest? lastSectionRequest;

  Duration latency;

  FakeGenerationApi({this.latency = Duration.zero});

  @override
  Future<GenerationResult> generate(GenerationRequest request) async {
    callCount++;
    lastRequest = request;
    if (latency > Duration.zero) {
      await Future<void>.delayed(latency);
    }
    if (nextError != null) {
      final error = nextError!;
      nextError = null;
      throw error;
    }
    return nextResult ?? _defaultResult();
  }

  @override
  Future<SectionRegenerationResult> regenerateSection(
    SectionRegenerationRequest request,
  ) async {
    sectionCallCount++;
    lastSectionRequest = request;
    if (latency > Duration.zero) {
      await Future<void>.delayed(latency);
    }
    if (nextSectionError != null) {
      final error = nextSectionError!;
      nextSectionError = null;
      throw error;
    }
    return nextSectionResult ?? _defaultSectionResult(request.sectionId);
  }

  void reset() {
    nextResult = null;
    nextError = null;
    callCount = 0;
    lastRequest = null;
    nextSectionResult = null;
    nextSectionError = null;
    sectionCallCount = 0;
    lastSectionRequest = null;
  }

  static SectionRegenerationResult _defaultSectionResult(String sectionId) =>
      SectionRegenerationResult(
        response: SectionRegenerationResponse(
          section: PaperSectionPayload(
            id: sectionId,
            heading: sectionId[0].toUpperCase() + sectionId.substring(1),
            content: 'Regenerated replacement content for $sectionId.',
            state: 'draft',
          ),
          reviewWarnings: const [],
        ),
        requestId: 'test-section-request-id-001',
      );

  static GenerationResult _defaultResult() => GenerationResult(
    response: _defaultResponse(),
    requestId: 'test-request-id-001',
  );

  static GenerationResponse _defaultResponse() => GenerationResponse.fromJson(
    defaultResponseJson(),
  );

  static Map<String, Object?> defaultResponseJson() => {
    'schema_version': 1,
    'generation_id': '550e8400-e29b-41d4-a716-446655440000',
    'paper': {
      'schema_version': 1,
      'title': 'Test Paper Title',
      'abstract': 'This is a test abstract describing the paper.',
      'keywords': ['testing', 'validation'],
      'sections': [
        {
          'id': 'introduction',
          'heading': 'Introduction',
          'content': 'This is the introduction section content for the test paper.',
          'state': 'draft',
        },
        {
          'id': 'methodology',
          'heading': 'Methodology',
          'content': 'The methodology used in this research.',
          'state': 'draft',
        },
        {
          'id': 'results',
          'heading': 'Results',
          'content': '',
          'state': 'needs_input',
        },
      ],
      'references': [
        {'id': 'ref_1', 'text': 'Smith, J. (2024). Test reference.'},
      ],
      'review_warnings': [
        {
          'code': 'MISSING_RESULTS',
          'severity': 'warning',
          'message': 'Results section needs user-supplied data.',
          'section_id': 'results',
        },
      ],
    },
    'review_warnings': [
      {
        'code': 'MISSING_RESULTS',
        'severity': 'warning',
        'message': 'Results section needs user-supplied data.',
        'section_id': 'results',
      },
    ],
    'meta': {
      'provider_name': 'fake',
      'model_name': 'fake-v1',
      'duration_ms': 1200,
      'input_tokens': 500,
      'output_tokens': 800,
    },
  };
}
