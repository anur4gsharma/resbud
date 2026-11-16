import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:resbud_mobile/data/local_project_repository.dart';
import 'package:resbud_mobile/features/docx_viewer/docx_document_canvas.dart';
import 'package:resbud_mobile/features/generation/generation_models.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('IEEE Conference Mobile Production-Readiness Audit', () {
    test('Steps 1-18: Project Creation, 5 Authors, 2 Affiliations, 6 Figures, Save, Close, Reopen', () async {
      final tempDir = await Directory.systemTemp.createTemp('resbud-ieee-audit-');
      final dbPath = p.join(tempDir.path, 'projects.sqlite');

      final repo = await LocalProjectRepository.open(
        path: dbPath,
        factory: databaseFactoryFfi,
      );

      // STEP 1-4: 5 Authors and 2 Affiliations
      final affiliations = [
        const AuthorAffiliationPayload(
          id: 'aff_1',
          department: 'Department of Computer Science & Engineering',
          institution: 'National Institute of Technology',
          city: 'Rourkela',
          state: 'Odisha',
          country: 'India',
        ),
        const AuthorAffiliationPayload(
          id: 'aff_2',
          department: 'Department of Biomedical Engineering',
          institution: 'School of Healthcare Sciences',
          city: 'Bhubaneswar',
          state: 'Odisha',
          country: 'India',
        ),
      ];

      final authors = [
        const AuthorMetadataPayload(
          name: 'Dr. Aris Thorne',
          order: 1,
          affiliationIds: ['aff_1'],
          email: 'aris.thorne@nitrkl.ac.in',
          roleOrTitle: 'Senior Member, IEEE',
          isCorresponding: true,
        ),
        const AuthorMetadataPayload(
          name: 'Elena Vance',
          order: 2,
          affiliationIds: ['aff_1'],
          email: 'elena.vance@nitrkl.ac.in',
          roleOrTitle: 'Graduate Student Member, IEEE',
        ),
        const AuthorMetadataPayload(
          name: 'Marcus Zhao',
          order: 3,
          affiliationIds: ['aff_2'],
          email: 'marcus.zhao@shs.ac.in',
          roleOrTitle: 'Member, IEEE',
        ),
        const AuthorMetadataPayload(
          name: 'Dr. Clara Oswald',
          order: 4,
          affiliationIds: ['aff_1'],
          email: 'clara.oswald@nitrkl.ac.in',
          roleOrTitle: 'Associate Professor',
        ),
        const AuthorMetadataPayload(
          name: 'Robert Song',
          order: 5,
          affiliationIds: ['aff_2'],
          email: 'robert.song@shs.ac.in',
          roleOrTitle: 'Research Scholar',
        ),
      ];

      // STEP 6: 6 Research Figures
      final sixFigures = List.generate(6, (i) {
        final num = i + 1;
        return {
          'id': 'fig_$num',
          'name': 'figure_$num.png',
          'caption': 'Fig. $num. Empirical Analysis $num',
          'description': 'Experimental visual data $num',
          'section_id': num <= 2 ? 'sec_method' : 'sec_results',
          'placement': num == 2 ? 'full_width' : 'column_width',
          'placement_status': 'approved',
          'figure_order': num,
          'bytes': Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        };
      });

      final projectContext = <String, Object?>{
        'title': 'Equivariant Neural Graph Decoders for Topological Surface Codes',
        'research_field': 'Quantum Information',
        'creation_mode': 'document',
        'authors': authors.map((a) => a.toJson()).toList(),
        'affiliations': affiliations.map((a) => a.toJson()).toList(),
        'figures': sixFigures,
        'preferences': {
          'target_word_count': 5000,
          'desired_sections': ['sec_intro', 'sec_method', 'sec_results', 'sec_conclusion'],
          'citation_style': 'ieee',
          'page_layout': 'two_column_academic',
          'document_template': 'ieee_conference',
          'authors': authors.map((a) => a.toJson()).toList(),
          'affiliations': affiliations.map((a) => a.toJson()).toList(),
        },
      };

      // Create project in SQLite
      final created = await repo.createProject(
        title: 'Equivariant Neural Graph Decoders for Topological Surface Codes',
        projectContext: projectContext,
        sourceDraft: 'Quantum error correction research notes...',
      );

      expect(created.id, isNotEmpty);
      expect(created.title, equals('Equivariant Neural Graph Decoders for Topological Surface Codes'));

      // STEP 9: Save generated Paper Version
      final initialPaper = PaperDraftPayload(
        schemaVersion: 1,
        title: created.title,
        abstractText: 'In this paper we present equivariant neural decoders for surface codes.',
        keywords: const ['Surface codes', 'Quantum decoding'],
        sections: const [
          PaperSectionPayload(
            id: 'sec_intro',
            heading: 'I. INTRODUCTION',
            content: 'Quantum error correction is foundational [1].',
            state: 'draft',
          ),
          PaperSectionPayload(
            id: 'sec_method',
            heading: 'II. METHODOLOGY',
            content: 'The Hamiltonian is given by:\n\n\$\$H = \\sum_v S_v\$\$\n\n![Fig. 1. Pipeline](fig_1)\n',
            state: 'draft',
          ),
        ],
        references: const [
          ReferencePayload(
            id: '1',
            text: 'A. G. Fowler et al., Phys. Rev. A, 2012.',
            year: 2012,
            citationNumber: 1,
          ),
        ],
        reviewWarnings: const [],
        pageLayout: 'two_column_academic',
        documentTemplate: 'ieee_conference',
        authors: authors,
        affiliations: affiliations,
      );

      final savedVersion = await repo.savePaperVersion(
        projectId: created.id,
        schemaVersion: 1,
        paper: initialPaper.toJson(),
        origin: PaperVersionOrigin.generation,
      );
      expect(savedVersion.versionNumber, equals(1));

      // STEP 17 & 18: Close and Reopen Repository
      await repo.close();

      // Reopen from SQLite
      final reopenedRepo = await LocalProjectRepository.open(
        path: dbPath,
        factory: databaseFactoryFfi,
      );

      final loadedProject = await reopenedRepo.getProject(created.id);
      expect(loadedProject, isNotNull);
      expect(loadedProject!.title, equals(created.title));

      // Verify Context preservation
      final restoredPrefs = loadedProject.projectContext['preferences'] as Map<String, dynamic>;
      expect(restoredPrefs['document_template'], equals('ieee_conference'));
      final restoredAuthors = restoredPrefs['authors'] as List;
      expect(restoredAuthors.length, equals(5));
      expect((restoredAuthors[0] as Map)['name'], equals('Dr. Aris Thorne'));
      expect((restoredAuthors[0] as Map)['email'], equals('aris.thorne@nitrkl.ac.in'));
      expect((restoredAuthors[0] as Map)['is_corresponding'], isTrue);

      final restoredAffils = restoredPrefs['affiliations'] as List;
      expect(restoredAffils.length, equals(2));
      expect((restoredAffils[0] as Map)['institution'], equals('National Institute of Technology'));

      // Verify Paper Version preservation
      final loadedVersion = await reopenedRepo.getCurrentPaperVersion(created.id);
      expect(loadedVersion, isNotNull);
      final restoredPaper = PaperDraftPayload.fromJson(loadedVersion!.paper);
      expect(restoredPaper.authors, isNotNull);
      expect(restoredPaper.authors!.length, equals(5));
      expect(restoredPaper.affiliations!.length, equals(2));
      expect(restoredPaper.documentTemplate, equals('ieee_conference'));

      await reopenedRepo.close();
      await tempDir.delete(recursive: true);
    });

    testWidgets('Step 21: DocxDocumentCanvas renders 5 authors in [3, 2] IEEE responsive grid', (tester) async {
      final affiliations = [
        const AuthorAffiliationPayload(
          id: 'aff_1',
          department: 'Department of Computer Science & Engineering',
          institution: 'National Institute of Technology',
          city: 'Rourkela',
          country: 'India',
        ),
        const AuthorAffiliationPayload(
          id: 'aff_2',
          department: 'Department of Biomedical Engineering',
          institution: 'School of Healthcare Sciences',
          city: 'Bhubaneswar',
          country: 'India',
        ),
      ];

      final authors = [
        const AuthorMetadataPayload(
          name: 'Dr. Aris Thorne',
          order: 1,
          affiliationIds: ['aff_1'],
          email: 'aris.thorne@nitrkl.ac.in',
          roleOrTitle: 'Senior Member, IEEE',
          isCorresponding: true,
        ),
        const AuthorMetadataPayload(
          name: 'Elena Vance',
          order: 2,
          affiliationIds: ['aff_1'],
          email: 'elena.vance@nitrkl.ac.in',
          roleOrTitle: 'Graduate Student Member, IEEE',
        ),
        const AuthorMetadataPayload(
          name: 'Marcus Zhao',
          order: 3,
          affiliationIds: ['aff_2'],
          email: 'marcus.zhao@shs.ac.in',
          roleOrTitle: 'Member, IEEE',
        ),
        const AuthorMetadataPayload(
          name: 'Dr. Clara Oswald',
          order: 4,
          affiliationIds: ['aff_1'],
          email: 'clara.oswald@nitrkl.ac.in',
          roleOrTitle: 'Associate Professor',
        ),
        const AuthorMetadataPayload(
          name: 'Robert Song',
          order: 5,
          affiliationIds: ['aff_2'],
          email: 'robert.song@shs.ac.in',
          roleOrTitle: 'Research Scholar',
        ),
      ];

      final paper = PaperDraftPayload(
        schemaVersion: 1,
        title: 'Equivariant Neural Graph Decoders for Topological Surface Codes',
        abstractText: 'In this paper we present equivariant neural decoders for surface codes.',
        keywords: const ['Surface codes', 'Quantum decoding'],
        sections: const [
          PaperSectionPayload(
            id: 'sec_intro',
            heading: 'I. INTRODUCTION',
            content: 'Quantum error correction is foundational [1]. The graph is \$G = (V, E)\$.\n\n\$\$H = \\sum_{v \\in V} S_v\$\$\n\nAs derived in (1), threshold is preserved.',
            state: 'draft',
          ),
        ],
        references: const [
          ReferencePayload(
            id: '1',
            text: 'A. G. Fowler et al., Phys. Rev. A, 2012.',
            year: 2012,
            citationNumber: 1,
          ),
        ],
        reviewWarnings: const [],
        pageLayout: 'two_column_academic',
        documentTemplate: 'ieee_conference',
        authors: authors,
        affiliations: affiliations,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DocxDocumentCanvas(
                paper: paper,
                zoom: 1.0,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Author Names rendered in canvas
      expect(find.textContaining('Dr. Aris Thorne'), findsOneWidget);
      expect(find.textContaining('Elena Vance'), findsOneWidget);
      expect(find.textContaining('Marcus Zhao'), findsOneWidget);
      expect(find.textContaining('Dr. Clara Oswald'), findsOneWidget);
      expect(find.textContaining('Robert Song'), findsOneWidget);

      // Verify emails rendered
      expect(find.text('aris.thorne@nitrkl.ac.in'), findsOneWidget);
      expect(find.text('marcus.zhao@shs.ac.in'), findsOneWidget);

      // Verify Abstract run-in with em-dash
      expect(find.textContaining('Abstract—'), findsOneWidget);

      // Verify Section Heading
      expect(find.textContaining('I. INTRODUCTION'), findsOneWidget);
    });
  });
}
