import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:resbud_mobile/data/project_figure.dart';
import 'package:resbud_mobile/features/generation/generation_models.dart';

void main() {
  group('Semantic Figure Placement Mobile Tests', () {
    test('ProjectFigure holds semantic metadata and serializes to StructuredFigure wire contract', () {
      final dummyBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final figure = ProjectFigure(
        id: 'FIG-001',
        projectId: 'proj_123',
        figureNumber: 1,
        filename: 'methodology_flowchart.png',
        mimeType: 'image/png',
        fileSize: 1024,
        caption: 'Fig. 1. End-to-end landmark detection pipeline.',
        storageKey: 'proj_123/FIG-001.png',
        width: 1280,
        height: 720,
        altText: 'Detailed flowchart of preprocessing steps',
        placement: FigurePlacement.columnWidth,
        sectionId: 'methodology',
        category: 'flowchart',
        title: 'Methodology Flowchart',
        targetAnchor: 'Immediately after overview',
        placementRationale: 'Contextually mapped to methodology',
        preferredPlacement: 'after_paragraph',
        referencedInText: true,
        placementStatus: 'assigned',
        cachedBytes: dummyBytes,
      );

      final structuredMap = figure.toStructuredFigureMap();
      expect(structuredMap['id'], 'FIG-001');
      expect(structuredMap['filename'], 'methodology_flowchart.png');
      expect(structuredMap['caption'], 'Fig. 1. End-to-end landmark detection pipeline.');
      expect(structuredMap['category'], 'flowchart');
      expect(structuredMap['related_section'], 'methodology');
      expect(structuredMap['target_anchor'], 'Immediately after overview');
      expect(structuredMap['preferred_placement'], 'after_paragraph');
      expect(structuredMap['column_span'], 'column_width');
      expect(structuredMap['figure_order'], 1);
      expect(structuredMap['referenced_in_text'], true);
      expect(structuredMap['placement_status'], 'assigned');
      expect(structuredMap['data_uri'], startsWith('data:image/png;base64,'));
    });

    test('toDatabaseRow only outputs columns existing in SQLite schema', () {
      final figure = ProjectFigure(
        id: 'FIG-002',
        projectId: 'proj_456',
        figureNumber: 2,
        filename: 'architecture.png',
        mimeType: 'image/png',
        fileSize: 2048,
        caption: 'Figure 2: Architecture',
        storageKey: 'proj_456/FIG-002.png',
        category: 'architecture_diagram',
        placement: FigurePlacement.fullWidth,
        sectionId: 'methodology',
      );

      final dbRow = figure.toDatabaseRow();
      expect(dbRow.containsKey('id'), true);
      expect(dbRow.containsKey('project_id'), true);
      expect(dbRow.containsKey('figure_number'), true);
      expect(dbRow.containsKey('filename'), true);
      expect(dbRow.containsKey('mime_type'), true);
      expect(dbRow.containsKey('width'), true);
      expect(dbRow.containsKey('height'), true);
      expect(dbRow.containsKey('file_size'), true);
      expect(dbRow.containsKey('caption'), true);
      expect(dbRow.containsKey('alt_text'), true);
      expect(dbRow.containsKey('placement'), true);
      expect(dbRow.containsKey('section_id'), true);
      expect(dbRow.containsKey('storage_key'), true);
      expect(dbRow.containsKey('created_at'), true);

      // Invariant: Non-schema columns MUST NOT be in dbRow
      expect(dbRow.containsKey('category'), false);
      expect(dbRow.containsKey('title'), false);
      expect(dbRow.containsKey('target_anchor'), false);
    });

    test('StructuredFigurePayload deserializes and serializes cleanly', () {
      final json = <String, Object?>{
        'id': 'FIG-003',
        'filename': 'accuracy_chart.png',
        'caption': 'Fig. 3. Benchmark accuracy comparison.',
        'category': 'graph',
        'related_section': 'results',
        'column_span': 'column_width',
        'figure_order': 3,
        'referenced_in_text': true,
        'placement_status': 'assigned',
      };

      final payload = StructuredFigurePayload.fromJson(json);
      expect(payload.id, 'FIG-003');
      expect(payload.caption, 'Fig. 3. Benchmark accuracy comparison.');
      expect(payload.category, 'graph');
      expect(payload.relatedSection, 'results');
      expect(payload.figureOrder, 3);
      expect(payload.referencedInText, true);
      expect(payload.placementStatus, 'assigned');

      final serialized = payload.toJson();
      expect(serialized['id'], 'FIG-003');
      expect(serialized['category'], 'graph');
      expect(serialized['column_span'], 'column_width');
    });

    test('PaperPreferencesPayload and PaperDraftPayload accept figures array', () {
      final prefJson = <String, Object?>{
        'target_word_count': 3000,
        'desired_sections': ['introduction', 'methodology', 'results'],
        'citation_style': 'ieee',
        'figures': [
          {
            'id': 'FIG-001',
            'filename': 'flowchart.png',
            'caption': 'Fig. 1. Proposed methodology flowchart.',
            'category': 'flowchart',
          },
        ],
      };

      final prefs = PaperPreferencesPayload.fromJson(prefJson);
      expect(prefs.figures, isNotNull);
      expect(prefs.figures!.length, 1);
      expect(prefs.figures!.first.id, 'FIG-001');

      final paperJson = <String, Object?>{
        'schema_version': 1,
        'title': 'Posture Analysis',
        'abstract': 'Abstract text',
        'keywords': ['vision', 'posture'],
        'sections': [
          {'id': 'methodology', 'heading': 'Methodology', 'content': 'Section content', 'state': 'draft'},
        ],
        'references': [],
        'review_warnings': [],
        'figures': [
          {
            'id': 'FIG-001',
            'filename': 'flowchart.png',
            'caption': 'Fig. 1. Proposed methodology flowchart.',
            'category': 'flowchart',
          },
        ],
      };

      final draft = PaperDraftPayload.fromJson(paperJson);
      expect(draft.figures, isNotNull);
      expect(draft.figures!.length, 1);
      expect(draft.figures!.first.id, 'FIG-001');
      expect(draft.toJson()['figures'], isNotNull);
    });
  });
}
