import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:resbud_mobile/features/docx_viewer/docx_document_canvas.dart';
import 'package:resbud_mobile/features/generation/generation_models.dart';

void main() {
  group('IEEE Conference Paper Model Tests', () {
    test('serializes and deserializes structured authors and affiliations', () {
      const aff1 = AuthorAffiliationPayload(
        id: 'aff1',
        department: 'Dept. of Information Technology',
        institution: 'B.K. Birla Institute of Engineering & Technology',
        city: 'Pilani',
        country: 'India',
      );

      const aff2 = AuthorAffiliationPayload(
        id: 'aff2',
        department: 'Dept. of Computer Science & Engineering',
        institution: 'B.K. Birla Institute of Engineering & Technology',
        city: 'Pilani',
        country: 'India',
      );

      const author1 = AuthorMetadataPayload(
        name: 'Author One',
        order: 1,
        affiliationIds: ['aff1'],
        roleOrTitle: 'UG Student',
        email: 'author1@example.com',
      );

      const author5 = AuthorMetadataPayload(
        name: 'Author Five',
        order: 5,
        affiliationIds: ['aff2'],
        roleOrTitle: 'Assistant Professor',
        email: 'author5@example.com',
        isCorresponding: true,
      );

      const prefs = PaperPreferencesPayload(
        targetWordCount: 5000,
        desiredSections: ['intro', 'methods'],
        citationStyle: 'ieee',
        pageLayout: 'two_column_academic',
        documentTemplate: 'ieee_conference',
        authors: [author1, author5],
        affiliations: [aff1, aff2],
      );

      final jsonPrefs = prefs.toJson();
      expect(jsonPrefs['document_template'], 'ieee_conference');
      expect(jsonPrefs['page_layout'], 'two_column_academic');
      expect(jsonPrefs['citation_style'], 'ieee');
      expect((jsonPrefs['authors'] as List).length, 2);
      expect((jsonPrefs['affiliations'] as List).length, 2);

      final parsedPrefs = PaperPreferencesPayload.fromJson(jsonPrefs);
      expect(parsedPrefs.documentTemplate, 'ieee_conference');
      expect(parsedPrefs.authors?.length, 2);
      expect(parsedPrefs.authors?[0].name, 'Author One');
      expect(parsedPrefs.authors?[1].isCorresponding, true);
    });

    test('PaperDraftPayload preserves template, authors, and affiliations across json roundtrip', () {
      const draft = PaperDraftPayload(
        schemaVersion: 1,
        title: 'Automated Posture Analysis and Ergonomic Risk Assessment',
        abstractText: 'Musculoskeletal disorders represent a major ergonomic risk.',
        keywords: ['pose estimation', 'ergonomics'],
        sections: [
          PaperSectionPayload(
            id: 'intro',
            heading: 'Introduction',
            content: 'Postural symmetry is critical.',
            state: 'draft',
          ),
          PaperSectionPayload(
            id: 'methods',
            heading: 'Methodology',
            content: 'Feature extraction is formulated below.',
            state: 'draft',
          ),
        ],
        references: [
          ReferencePayload(
            id: 'ref1',
            text: 'A. Smith, "Posture estimation algorithms," IEEE Trans. PAMI, 2024.',
          ),
        ],
        reviewWarnings: [],
        pageLayout: 'two_column_academic',
        documentTemplate: 'ieee_conference',
        authors: [
          AuthorMetadataPayload(
            name: 'Jane Doe',
            order: 1,
            affiliationIds: ['aff1'],
            roleOrTitle: 'Lead Researcher',
            email: 'jane@example.com',
          ),
        ],
        affiliations: [
          AuthorAffiliationPayload(
            id: 'aff1',
            institution: 'Stanford University',
            city: 'Stanford',
            country: 'USA',
          ),
        ],
      );

      final json = draft.toJson();
      expect(json['document_template'], 'ieee_conference');
      expect(json['page_layout'], 'two_column_academic');

      final parsed = PaperDraftPayload.fromJson(json);
      expect(parsed.documentTemplate, 'ieee_conference');
      expect(parsed.authors?.first.name, 'Jane Doe');
      expect(parsed.affiliations?.first.institution, 'Stanford University');
    });
  });

  group('IEEE Conference DocxDocumentCanvas Rendering Tests', () {
    testWidgets('renders IEEE 5-author grid, run-in abstract, and Roman numeral headings', (tester) async {
      const paper = PaperDraftPayload(
        schemaVersion: 1,
        title: 'Automated Posture Analysis and Ergonomic Risk Assessment',
        abstractText: 'Musculoskeletal disorders represent a major ergonomic risk in sedentary environments.',
        keywords: ['pose estimation', 'ergonomics', 'computer vision'],
        sections: [
          PaperSectionPayload(
            id: 'intro',
            heading: 'Introduction',
            content: 'Human posture analysis is an active field in computer vision.',
            state: 'draft',
          ),
          PaperSectionPayload(
            id: 'methods',
            heading: 'Methodology',
            content: 'The keypoint coordinates are normalized using scale factor.',
            state: 'draft',
          ),
        ],
        references: [
          ReferencePayload(
            id: 'ref1',
            text: 'A. Smith, "Posture estimation algorithms," IEEE Trans. PAMI, 2024.',
          ),
        ],
        reviewWarnings: [],
        pageLayout: 'two_column_academic',
        documentTemplate: 'ieee_conference',
        affiliations: [
          AuthorAffiliationPayload(
            id: 'aff1',
            department: 'Dept. of Information Technology',
            institution: 'B.K. Birla Institute of Engineering & Technology',
            city: 'Pilani',
            country: 'India',
          ),
          AuthorAffiliationPayload(
            id: 'aff2',
            department: 'Dept. of Computer Science & Engineering',
            institution: 'B.K. Birla Institute of Engineering & Technology',
            city: 'Pilani',
            country: 'India',
          ),
        ],
        authors: [
          AuthorMetadataPayload(
            name: 'Author One',
            order: 1,
            affiliationIds: ['aff1'],
            roleOrTitle: 'UG Student',
            email: 'author1@example.com',
          ),
          AuthorMetadataPayload(
            name: 'Author Two',
            order: 2,
            affiliationIds: ['aff1'],
            roleOrTitle: 'UG Student',
            email: 'author2@example.com',
          ),
          AuthorMetadataPayload(
            name: 'Author Three',
            order: 3,
            affiliationIds: ['aff1'],
            roleOrTitle: 'UG Student',
            email: 'author3@example.com',
          ),
          AuthorMetadataPayload(
            name: 'Author Four',
            order: 4,
            affiliationIds: ['aff1'],
            roleOrTitle: 'UG Student',
            email: 'author4@example.com',
          ),
          AuthorMetadataPayload(
            name: 'Author Five',
            order: 5,
            affiliationIds: ['aff2'],
            roleOrTitle: 'Assistant Professor',
            email: 'author5@example.com',
            isCorresponding: true,
          ),
        ],
      );

      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DocxDocumentCanvas(
              paper: paper,
              zoom: 1.0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Title is rendered
      expect(find.text('Automated Posture Analysis and Ergonomic Risk Assessment'), findsOneWidget);

      // 2. Structured authors are rendered (matching ASEP 2 RP.docx 5 authors)
      expect(find.textContaining('Author One'), findsOneWidget);
      expect(find.textContaining('Author Two'), findsOneWidget);
      expect(find.textContaining('Author Three'), findsOneWidget);
      expect(find.textContaining('Author Four'), findsOneWidget);
      expect(find.textContaining('Author Five'), findsOneWidget);
      expect(find.text('UG Student'), findsWidgets);
      expect(find.text('Assistant Professor'), findsOneWidget);
      expect(find.text('Dept. of Information Technology'), findsWidgets);
      expect(find.text('Dept. of Computer Science & Engineering'), findsOneWidget);
      expect(find.text('author5@example.com'), findsOneWidget);

      // 3. IEEE Run-in Abstract & Index Terms
      expect(find.textContaining('Abstract—'), findsOneWidget);
      expect(find.textContaining('Index Terms—'), findsOneWidget);

      // 4. Roman numeral headings for IEEE
      expect(find.text('I. INTRODUCTION'), findsOneWidget);
      expect(find.text('II. METHODOLOGY'), findsOneWidget);

      // 5. Two-column body is rendered
      expect(find.byType(Divider), findsWidgets);
    });
  });
}
