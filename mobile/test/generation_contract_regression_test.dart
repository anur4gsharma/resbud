import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:resbud_mobile/features/generation/generation_api_client.dart';
import 'package:resbud_mobile/features/generation/generation_models.dart';

void main() {
  group('Generation Contract & Error Recovery Regression Suite (Tests A through J)', () {
    final validProjectInputs = {
      'title': 'Contract Verification in Academic AI Systems',
      'research_field': 'Computer Science',
      'research_question': 'How can strict schemas eliminate mobile deserialization crashes?',
      'objectives': ['Quantify failure modes', 'Unify wire contracts'],
      'claimed_contribution': 'Fault-tolerant generation contract architecture.',
      'methodology_status': 'provided',
      'methodology': 'Static analysis and continuous regression verification.',
      'dataset_or_materials_status': 'provided',
      'dataset_or_materials': 'Production telemetry and synthetic stress payloads.',
      'results_status': 'provided',
      'results': 'Zero uncaught FormatExceptions across all tested scenarios.',
      'limitations_status': 'provided',
      'limitations': 'Requires JSON-compatible runtime.',
      'preferences': {
        'target_word_count': 2500,
        'desired_sections': ['introduction', 'methodology', 'results'],
        'citation_style': 'ieee',
        'page_layout': 'single_column',
        'document_template': 'default',
        'include_review_notes_appendix': false,
      },
      'references': [
        {
          'id': 'ref_1',
          'text': 'A. Sharma, Contract Integrity, IEEE Trans. Softw. Eng., 2026.',
        }
      ],
    };

    final standardPaperJson = {
      'schema_version': 1,
      'title': 'Contract Verification in Academic AI Systems',
      'abstract': 'A complete audit of generation contracts.',
      'keywords': ['Contracts', 'Flutter', 'FastAPI'],
      'sections': [
        {
          'id': 'introduction',
          'heading': 'Introduction',
          'content': 'Mathematical guarantees such as \$E = mc^2\$ are maintained.',
          'state': 'draft',
        },
        {
          'id': 'methodology',
          'heading': 'Methodology',
          'content': 'Equations: \n\n\$\$\\nabla \\times \\mathbf{B} = \\mu_0 \\mathbf{J}\$\$\n\nDetailed analysis.',
          'state': 'draft',
        },
        {
          'id': 'results',
          'heading': 'Results',
          'content': 'Measured 100% compliance across all tested boundaries.',
          'state': 'draft',
        },
      ],
      'references': [
        {
          'id': 'ref_1',
          'text': 'A. Sharma, Contract Integrity, IEEE Trans. Softw. Eng., 2026.',
        }
      ],
      'review_warnings': [
        {
          'code': 'GENERAL_REVIEW',
          'severity': 'info',
          'message': 'Manuscript successfully generated.',
          'section_id': null,
        }
      ],
      'page_layout': 'single_column',
      'document_template': 'default',
      'authors': null,
      'affiliations': null,
      'figures': null,
    };

    final standardResponseJson = {
      'schema_version': 1,
      'generation_id': '87654321-4321-4321-8765-123456789abc',
      'paper': standardPaperJson,
      'review_warnings': [
        {
          'code': 'GENERAL_REVIEW',
          'severity': 'info',
          'message': 'Manuscript successfully generated.',
          'section_id': null,
        }
      ],
      'meta': {
        'provider_name': 'gemini',
        'model_name': 'gemini-3.5-flash',
        'duration_ms': 1850,
        'input_tokens': 450,
        'output_tokens': 1200,
        'requested_words': 2500,
        'generated_words': 2400,
        'completion_status': 'completed',
      },
    };

    // --- Test A: Standard Academic Paper Generation ---
    test('Test A: Standard single-column academic paper generation parses and validates cleanly', () {
      final req = GenerationRequest.fromInputs(
        project: validProjectInputs,
        sourceDraft: 'Source draft exploring academic manuscript generation.',
      );
      expect(req.preferences.pageLayout, 'single_column');
      expect(req.preferences.documentTemplate, 'default');
      expect(req.preferences.includeReviewNotesAppendix, isFalse);

      final resp = GenerationResponse.fromJson(standardResponseJson);
      expect(resp.paper.pageLayout, 'single_column');
      expect(resp.paper.documentTemplate, 'default');
      expect(resp.paper.sections.length, 3);
      expect(resp.meta.durationMs, 1850);
      expect(resp.meta.completionStatus, 'completed');
    });

    // --- Test B: Two-Column Academic Paper Generation ---
    test('Test B: Two-column academic paper generation contract adherence', () {
      final twoColProject = Map<String, Object?>.from(validProjectInputs);
      final twoColPrefs = Map<String, Object?>.from(twoColProject['preferences'] as Map);
      twoColPrefs['page_layout'] = 'two_column_academic';
      twoColProject['preferences'] = twoColPrefs;

      final req = GenerationRequest.fromInputs(
        project: twoColProject,
        sourceDraft: 'Source draft for two-column academic paper.',
      );
      expect(req.preferences.pageLayout, 'two_column_academic');

      final twoColPaperJson = Map<String, Object?>.from(standardPaperJson);
      twoColPaperJson['page_layout'] = 'two_column_academic';
      final parsed = PaperDraftPayload.fromJson(twoColPaperJson);
      expect(parsed.pageLayout, 'two_column_academic');
      expect(parsed.toJson()['page_layout'], 'two_column_academic');
    });

    // --- Test C: IEEE Conference Paper Generation ---
    test('Test C: IEEE Conference paper generation with 5 authors, 2 affiliations, 3 figures, and 15 references', () {
      final authors = List.generate(
        5,
        (i) => {
          'name': 'Author ${i + 1}',
          'order': i + 1,
          'affiliation_ids': [i < 3 ? 'aff_1' : 'aff_2'],
          'email': 'author${i + 1}@university.edu',
          'is_corresponding': i == 0,
        },
      );
      final affiliations = [
        {'id': 'aff_1', 'institution': 'MIT', 'city': 'Cambridge', 'country': 'USA'},
        {'id': 'aff_2', 'institution': 'Oxford', 'city': 'Oxford', 'country': 'UK'},
      ];
      final figures = List.generate(
        3,
        (i) => {
          'id': 'fig_${i + 1}',
          'filename': 'figure_${i + 1}.png',
          'caption': 'Fig. ${i + 1}. System Architecture Phase ${i + 1}.',
          'category': 'architecture_diagram',
          'placement_status': 'assigned',
        },
      );
      final references = List.generate(
        15,
        (i) => {
          'id': 'ref_${i + 1}',
          'text': 'Author ${i + 1}, Title ${i + 1}, IEEE Trans. Inf. Theory, 202${i % 6}.',
          'citation_number': i + 1,
          'is_cited': true,
        },
      );

      final ieeePaperJson = Map<String, Object?>.from(standardPaperJson);
      ieeePaperJson['document_template'] = 'ieee_conference';
      ieeePaperJson['page_layout'] = 'two_column_academic';
      ieeePaperJson['authors'] = authors;
      ieeePaperJson['affiliations'] = affiliations;
      ieeePaperJson['figures'] = figures;
      ieeePaperJson['references'] = references;

      final parsed = PaperDraftPayload.fromJson(ieeePaperJson);
      expect(parsed.documentTemplate, 'ieee_conference');
      expect(parsed.pageLayout, 'two_column_academic');
      expect(parsed.authors?.length, 5);
      expect(parsed.affiliations?.length, 2);
      expect(parsed.figures?.length, 3);
      expect(parsed.references.length, 15);

      final dumped = parsed.toJson();
      expect(dumped['document_template'], 'ieee_conference');
      expect((dumped['authors'] as List).length, 5);
      expect((dumped['figures'] as List).length, 3);
    });

    // --- Test D: Missing Information Handling ---
    test('Test D: Missing info handling preserves integrity warnings and section states', () {
      final missingProject = Map<String, Object?>.from(validProjectInputs);
      missingProject['methodology_status'] = 'not_available';
      missingProject.remove('methodology');
      missingProject['results_status'] = 'not_collected';
      missingProject.remove('results');

      final req = GenerationRequest.fromInputs(
        project: missingProject,
        sourceDraft: 'Draft without collected results.',
      );
      expect(req.project.methodologyStatus, 'not_available');
      expect(req.project.resultsStatus, 'not_collected');

      final warningsJson = [
        {
          'code': 'MISSING_METHOD',
          'severity': 'warning',
          'message': 'Methodology is not available.',
          'section_id': null,
        },
        {
          'code': 'MISSING_RESULTS',
          'severity': 'warning',
          'message': 'Results have not been collected.',
          'section_id': 'results',
        },
      ];
      final paperWithWarnings = Map<String, Object?>.from(standardPaperJson);
      paperWithWarnings['review_warnings'] = warningsJson;
      final parsed = PaperDraftPayload.fromJson(paperWithWarnings);

      expect(parsed.reviewWarnings.length, 2);
      expect(parsed.reviewWarnings[0].code, 'MISSING_METHOD');
      expect(parsed.reviewWarnings[1].code, 'MISSING_RESULTS');
      expect(parsed.reviewWarnings[1].sectionId, 'results');
    });

    // --- Test E: Provider Timeout Handling ---
    test('Test E: Provider timeout sets mayHaveCompleted to true', () async {
      final mock = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'code': 'PROVIDER_TIMEOUT',
            'detail': 'Upstream LLM timed out after 300 seconds.',
            'request_id': 'timeout-req-999',
          }),
          504,
        );
      });

      final client = GenerationApiClient(
        baseUri: Uri.parse('http://127.0.0.1:8000'),
        client: mock,
      );

      final req = GenerationRequest.fromInputs(
        project: validProjectInputs,
        sourceDraft: 'Some draft.',
      );

      expect(
        () => client.generate(req),
        throwsA(
          isA<GenerationApiFailure>()
              .having((f) => f.code, 'code', GenerationFailureCode.providerTimeout)
              .having((f) => f.mayHaveCompleted, 'mayHaveCompleted', isTrue)
              .having((f) => f.requestId, 'requestId', 'timeout-req-999')
              .having((f) => f.detail, 'detail', contains('timed out')),
        ),
      );
    });

    // --- Test F: Invalid Format Rejection ---
    test('Test F: Invalid format rejection produces descriptive FormatException', () {
      final invalidProject = Map<String, Object?>.from(validProjectInputs);
      final prefs = Map<String, Object?>.from(invalidProject['preferences'] as Map);
      prefs['target_word_count'] = 200; // < 500
      invalidProject['preferences'] = prefs;

      expect(
        () => GenerationRequest.fromInputs(
          project: invalidProject,
          sourceDraft: 'Some draft.',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Target word count must be between 500 and 8,000.'),
          ),
        ),
      );
    });

    // --- Test G: Response Contract Adherence & Descriptive Parser Diagnostics ---
    test('Test G: Response contract adherence throws deserializationFailure with offending key names', () {
      final responseWithOffendingKey = Map<String, Object?>.from(standardResponseJson);
      final paperWithOffendingKey = Map<String, Object?>.from(standardPaperJson);
      paperWithOffendingKey['unrecognized_alien_field'] = 'boom';
      responseWithOffendingKey['paper'] = paperWithOffendingKey;

      expect(
        () => GenerationResponse.fromJson(responseWithOffendingKey),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('paper contains unsupported fields: unrecognized_alien_field'),
          ),
        ),
      );
    });

    // --- Test H: Database Persistence Roundtrip ---
    test('Test H: Database persistence roundtrip preserves all schema properties', () {
      final original = PaperDraftPayload.fromJson(standardPaperJson);
      final jsonString = jsonEncode(original.toJson());
      final reloaded = PaperDraftPayload.fromJson(jsonDecode(jsonString) as Map<String, Object?>);

      expect(reloaded.title, original.title);
      expect(reloaded.documentTemplate, original.documentTemplate);
      expect(reloaded.pageLayout, original.pageLayout);
      expect(reloaded.sections.length, original.sections.length);
      expect(reloaded.references.length, original.references.length);
      expect(reloaded.reviewWarnings.length, original.reviewWarnings.length);
    });

    // --- Test I: Export Contract Generation with and without Review Notes Appendix ---
    test('Test I: Export contract generation preserves review notes appendix flag', () {
      final prefsWithout = PaperPreferencesPayload.fromJson({
        'target_word_count': 2000,
        'desired_sections': ['introduction', 'methodology'],
        'citation_style': 'ieee',
        'include_review_notes_appendix': false,
      });
      expect(prefsWithout.includeReviewNotesAppendix, isFalse);
      expect(prefsWithout.toJson().containsKey('include_review_notes_appendix'), isFalse);

      final prefsWith = PaperPreferencesPayload.fromJson({
        'target_word_count': 2000,
        'desired_sections': ['introduction', 'methodology'],
        'citation_style': 'ieee',
        'include_review_notes_appendix': true,
      });
      expect(prefsWith.includeReviewNotesAppendix, isTrue);
      expect(prefsWith.toJson()['include_review_notes_appendix'], isTrue);
    });

    // --- Test J: Backward Compatibility with Older Paper Versions ---
    test('Test J: Backward compatibility parses v1.0.0 payloads without template or figures gracefully', () {
      final legacyPaper = {
        'schema_version': 1,
        'title': 'Legacy Pre-Template Paper',
        'abstract': 'Written in early Resbud release.',
        'keywords': ['Legacy'],
        'sections': [
          {
            'id': 'introduction',
            'heading': 'Introduction',
            'content': 'Historical content without authors block.',
            'state': 'draft',
          }
        ],
        'references': [
          {
            'id': 'ref_1',
            'text': 'Old reference.',
          }
        ],
        'review_warnings': <Object>[],
        'page_layout': 'single_column',
      };

      final parsed = PaperDraftPayload.fromJson(legacyPaper);
      expect(parsed.documentTemplate, 'default');
      expect(parsed.authors, isNull);
      expect(parsed.affiliations, isNull);
      expect(parsed.figures, isNull);
      expect(parsed.pageLayout, 'single_column');
      expect(parsed.includeReviewNotesAppendix, isFalse);
    });

    // --- Reproduction and Resolution: Support Request ID ce6e5924-597c-421c-9203-534697720e0f ---
    test('Reproduction and Resolution: Incident ce6e5924-597c-421c-9203-534697720e0f payload deserializes cleanly', () async {
      final incidentPayload = {
        'schema_version': 1,
        'generation_id': 'ce6e5924-597c-421c-9203-534697720e0f',
        'paper': {
          'schema_version': 1,
          'title': 'An Empirical Study of Posture Analysis',
          'abstract': 'Automated classification using deep neural networks.',
          'keywords': ['Posture', 'Ergonomics'],
          'sections': [
            {
              'id': 'introduction',
              'heading': 'Introduction',
              'content': 'Posture evaluation is essential in workplace health.',
              'state': 'draft',
            },
          ],
          'references': [
            {
              'id': 'ref_1',
              'text': 'A. Ergonomist, Posture Assessment, 2024.',
            },
          ],
          'review_warnings': <Object>[],
          'page_layout': 'single_column',
          'document_template': 'default',
          'authors': null,
          'affiliations': null,
          'figures': null,
        },
        'review_warnings': <Object>[],
        'meta': {
          'provider_name': 'gemini',
          'model_name': 'gemini-3.5-flash',
          'duration_ms': 2340,
        },
      };

      final mock = MockClient((request) async {
        return http.Response(
          jsonEncode(incidentPayload),
          200,
          headers: {'x-request-id': 'ce6e5924-597c-421c-9203-534697720e0f'},
        );
      });

      final client = GenerationApiClient(
        baseUri: Uri.parse('https://resbud-api.onrender.com'),
        client: mock,
      );

      final req = GenerationRequest.fromInputs(
        project: validProjectInputs,
        sourceDraft: 'Some research material.',
      );

      final result = await client.generate(req);
      expect(result.requestId, 'ce6e5924-597c-421c-9203-534697720e0f');
      expect(result.response.generationId, 'ce6e5924-597c-421c-9203-534697720e0f');
      expect(result.response.paper.documentTemplate, 'default');
      expect(result.response.paper.authors, isNull);
    });
  });
}
