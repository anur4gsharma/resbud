import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:resbud_mobile/data/local_project_repository.dart';
import 'package:resbud_mobile/features/docx_viewer/docx_document_canvas.dart';
import 'package:resbud_mobile/features/generation/generation_models.dart';
import 'package:resbud_mobile/features/project_input/author_affiliation_validator.dart';
import 'package:resbud_mobile/shared/widgets/resbud_author_card.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('1. IEEE Author Grid Calculation & Superscripts', () {
    test('calculates correct balanced grid partitions for 1, 2, 3, 5, 8, and 12 authors', () {
      expect(calculateIeeeAuthorGrid(1), [1]);
      expect(calculateIeeeAuthorGrid(2), [2]);
      expect(calculateIeeeAuthorGrid(3), [3]);
      expect(calculateIeeeAuthorGrid(4), [2, 2]);
      expect(calculateIeeeAuthorGrid(5), [3, 2]);
      expect(calculateIeeeAuthorGrid(6), [3, 3]);
      expect(calculateIeeeAuthorGrid(7), [4, 3]);
      expect(calculateIeeeAuthorGrid(8), [4, 4]);
      expect(calculateIeeeAuthorGrid(9), [3, 3, 3]);
      expect(calculateIeeeAuthorGrid(10), [4, 3, 3]);

      final grid12 = calculateIeeeAuthorGrid(12);
      expect(grid12.reduce((a, b) => a + b), 12);
      expect(grid12.every((cols) => cols <= 4), isTrue);
    });

    test('toSuperscriptDigits converts ASCII numbers and symbols into unicode superscripts', () {
      expect(toSuperscriptDigits('1'), '¹');
      expect(toSuperscriptDigits('2'), '²');
      expect(toSuperscriptDigits('3'), '³');
      expect(toSuperscriptDigits('1,2'), '¹,²');
      expect(toSuperscriptDigits('4,5*'), '⁴,⁵*');
      expect(toSuperscriptDigits('12'), '¹²');
    });
  });

  group('2. Author & Affiliation Validation Engine', () {
    const aff1 = AuthorAffiliationPayload(
      id: 'aff_1',
      institution: 'MIT',
      department: 'EECS',
      city: 'Cambridge',
      country: 'USA',
    );
    const aff2 = AuthorAffiliationPayload(
      id: 'aff_2',
      institution: 'Stanford University',
      department: 'CS',
      city: 'Stanford',
      country: 'USA',
    );

    test('validates correct multi-author configuration with no errors', () {
      final authors = [
        const AuthorMetadataPayload(
          id: 'auth_1',
          name: 'Alice Smith',
          order: 1,
          affiliationIds: ['aff_1'],
          email: 'alice@mit.edu',
          orcid: '0000-0002-1825-0097',
          isCorresponding: true,
        ),
        const AuthorMetadataPayload(
          id: 'auth_2',
          name: 'Bob Jones',
          order: 2,
          affiliationIds: ['aff_2'],
          email: 'bob@stanford.edu',
        ),
      ];

      final report = AuthorAffiliationValidator.validate(
        authors: authors,
        affiliations: [aff1, aff2],
      );

      expect(report.isValid, isTrue);
      expect(report.errors, isEmpty);
      expect(report.warnings, isEmpty);
    });

    test('detects empty author names and duplicate author IDs', () {
      final authors = [
        const AuthorMetadataPayload(
          id: 'auth_same',
          name: '',
          order: 1,
          affiliationIds: ['aff_1'],
        ),
        const AuthorMetadataPayload(
          id: 'auth_same',
          name: 'Bob Jones',
          order: 2,
          affiliationIds: ['aff_1'],
        ),
      ];

      final report = AuthorAffiliationValidator.validate(
        authors: authors,
        affiliations: [aff1],
      );

      expect(report.isValid, isFalse);
      expect(report.errorMessages, anyElement(contains('empty name')));
      expect(report.errorMessages, anyElement(contains('Duplicate author ID "auth_same"')));
    });

    test('detects unresolved affiliation references and empty institutions', () {
      final authors = [
        const AuthorMetadataPayload(
          name: 'Carol White',
          order: 1,
          affiliationIds: ['aff_nonexistent'],
        ),
      ];
      const invalidAff = AuthorAffiliationPayload(
        id: 'aff_bad',
        institution: '   ',
      );

      final report = AuthorAffiliationValidator.validate(
        authors: authors,
        affiliations: [invalidAff],
      );

      expect(report.isValid, isFalse);
      expect(report.errorMessages, anyElement(contains('references non-existent affiliation "aff_nonexistent"')));
      expect(report.errorMessages, anyElement(contains('missing required institution name')));
    });

    test('detects invalid email and ORCID syntax as non-blocking warnings', () {
      final authors = [
        const AuthorMetadataPayload(
          name: 'David Brown',
          order: 1,
          affiliationIds: ['aff_1'],
          email: 'not-an-email',
          orcid: '12345',
        ),
      ];

      final report = AuthorAffiliationValidator.validate(
        authors: authors,
        affiliations: [aff1],
      );

      expect(report.isValid, isTrue); // warnings do not make report invalid
      expect(report.warnings, hasLength(2));
      expect(report.warningMessages, anyElement(contains('invalid email format')));
      expect(report.warningMessages, anyElement(contains('invalid ORCID format')));
    });
  });

  group('3. ResbudAuthorSection Responsive UI Interaction', () {
    testWidgets('renders 1 author without superscripts when only 1 affiliation exists', (tester) async {
      final authors = [
        const AuthorMetadataPayload(
          name: 'Solo Author',
          order: 1,
          affiliationIds: ['aff_1'],
          email: 'solo@lab.org',
        ),
      ];
      const affiliations = [
        AuthorAffiliationPayload(
          id: 'aff_1',
          institution: 'CERN',
          department: 'Physics',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ResbudAuthorSection(
                authors: authors,
                affiliations: affiliations,
                onAddAuthor: () {},
                onAddAffiliation: () {},
                onRemoveAuthor: (_) {},
                onRemoveAffiliation: (_) {},
                onPrefillAuthors: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Solo Author'), findsOneWidget);
      expect(find.text('CERN'), findsOneWidget);
      expect(find.text('1 author'), findsOneWidget);
      // No superscript numbers shown when single affiliation
      expect(find.textContaining('¹'), findsNothing);
    });

    testWidgets('renders 2 authors with automatic superscripts when multiple affiliations exist', (tester) async {
      final authors = [
        const AuthorMetadataPayload(
          name: 'First Author',
          order: 1,
          affiliationIds: ['aff_1'],
        ),
        const AuthorMetadataPayload(
          name: 'Second Author',
          order: 2,
          affiliationIds: ['aff_2'],
          isCorresponding: true,
        ),
      ];
      const affiliations = [
        AuthorAffiliationPayload(id: 'aff_1', institution: 'MIT'),
        AuthorAffiliationPayload(id: 'aff_2', institution: 'Stanford'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ResbudAuthorSection(
                authors: authors,
                affiliations: affiliations,
                onAddAuthor: () {},
                onAddAffiliation: () {},
                onRemoveAuthor: (_) {},
                onRemoveAffiliation: (_) {},
                onPrefillAuthors: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 authors'), findsOneWidget);
      expect(find.textContaining('¹'), findsOneWidget);
      expect(find.textContaining('²*'), findsOneWidget);
      expect(find.text('* Corresponding'), findsOneWidget);
    });

    testWidgets('handles reordering and removal callbacks', (tester) async {
      var movedOld = -1;
      var movedDelta = 0;
      var removedAuthorIdx = -1;

      final authors = [
        const AuthorMetadataPayload(name: 'Author A', order: 1),
        const AuthorMetadataPayload(name: 'Author B', order: 2),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ResbudAuthorSection(
                authors: authors,
                affiliations: const [],
                onAddAuthor: () {},
                onAddAffiliation: () {},
                onRemoveAuthor: (idx) => removedAuthorIdx = idx,
                onRemoveAffiliation: (_) {},
                onMoveAuthor: (idx, delta) {
                  movedOld = idx;
                  movedDelta = delta;
                },
                onPrefillAuthors: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap move down on Author A
      final downButtons = find.byTooltip('Move author down');
      expect(downButtons, findsWidgets);
      await tester.tap(downButtons.first);
      expect(movedOld, 0);
      expect(movedDelta, 1);

      // Tap remove author on Author B
      final removeButtons = find.byTooltip('Remove author');
      expect(removeButtons, findsWidgets);
      await tester.tap(removeButtons.last);
      expect(removedAuthorIdx, 1);
    });
  });

  group('4. DocxDocumentCanvas Rendering Across Author Counts (1, 2, 3, 5, 8, 12)', () {
    PaperDraftPayload createPaperWithAuthors(int count) {
      final affiliations = [
        const AuthorAffiliationPayload(
          id: 'aff_1',
          institution: 'Institute of AI',
          department: 'Dept of CS',
          city: 'London',
          country: 'UK',
        ),
        const AuthorAffiliationPayload(
          id: 'aff_2',
          institution: 'BioTech Labs',
          department: 'Bioengineering',
          city: 'Boston',
          country: 'USA',
        ),
      ];

      final authors = List.generate(
        count,
        (i) => AuthorMetadataPayload(
          id: 'auth_${i + 1}',
          name: 'Researcher ${i + 1}',
          order: i + 1,
          affiliationIds: [i % 2 == 0 ? 'aff_1' : 'aff_2'],
          email: 'researcher${i + 1}@institute.edu',
          roleOrTitle: i == 0 ? 'Senior Member, IEEE' : 'Member, IEEE',
          isCorresponding: i == 0,
        ),
      );

      return PaperDraftPayload(
        schemaVersion: 1,
        title: 'Scalable Neural Architecture for Multimodal Reasoning',
        documentTemplate: 'ieee_conference',
        abstractText: 'This paper investigates scalable deep models for multimodal scientific literature.',
        keywords: const ['Deep Learning', 'IEEE', 'Multimodal'],
        sections: const [
          PaperSectionPayload(
            id: 'sec_intro',
            heading: 'Introduction',
            content: 'Scientific progress requires rigorous models.',
            state: 'final',
          ),
        ],
        references: const [],
        reviewWarnings: const [],
        authors: authors,
        affiliations: affiliations,
      );
    }

    for (final authorCount in [1, 2, 3, 5, 8, 12]) {
      testWidgets('renders $authorCount authors in DocxDocumentCanvas with zero errors', (tester) async {
        final paper = createPaperWithAuthors(authorCount);

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

        final r1Finder = find.byWidgetPredicate(
          (w) => w is Text && w.textSpan is TextSpan && (w.textSpan as TextSpan).text == 'Researcher 1',
        );
        final rLastFinder = find.byWidgetPredicate(
          (w) => w is Text && w.textSpan is TextSpan && (w.textSpan as TextSpan).text == 'Researcher $authorCount',
        );

        expect(r1Finder, findsOneWidget);
        expect(rLastFinder, findsOneWidget);
        expect(find.text('researcher1@institute.edu'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('5. SQLite Persistence Roundtrip for Dynamic Authors & Affiliations', () {
    test('persists 8 authors across 3 affiliations and restores metadata intact', () async {
      const dbPath = inMemoryDatabasePath;
      final repo = await LocalProjectRepository.open(
        path: dbPath,
        factory: databaseFactoryFfi,
      );

      const aff1 = AuthorAffiliationPayload(
        id: 'aff_oxford',
        institution: 'University of Oxford',
        department: 'Dept of Engineering Science',
        city: 'Oxford',
        country: 'United Kingdom',
      );
      const aff2 = AuthorAffiliationPayload(
        id: 'aff_cambridge',
        institution: 'University of Cambridge',
        department: 'Computer Laboratory',
        city: 'Cambridge',
        country: 'United Kingdom',
      );
      const aff3 = AuthorAffiliationPayload(
        id: 'aff_eth',
        institution: 'ETH Zurich',
        department: 'D-INFK',
        city: 'Zurich',
        country: 'Switzerland',
      );

      final authors = [
        const AuthorMetadataPayload(
          id: 'auth_1',
          name: 'Prof. Alan Turing',
          order: 1,
          affiliationIds: ['aff_cambridge'],
          email: 'turing@cam.ac.uk',
          orcid: '0000-0002-1825-0001',
          roleOrTitle: 'Fellow, Royal Society',
          isCorresponding: true,
        ),
        const AuthorMetadataPayload(
          id: 'auth_2',
          name: 'Ada Lovelace',
          order: 2,
          affiliationIds: ['aff_oxford'],
          email: 'ada@ox.ac.uk',
          orcid: '0000-0002-1825-0002',
          roleOrTitle: 'Senior Member, IEEE',
        ),
        const AuthorMetadataPayload(
          id: 'auth_3',
          name: 'Claude Shannon',
          order: 3,
          affiliationIds: ['aff_eth'],
          email: 'shannon@ethz.ch',
        ),
        const AuthorMetadataPayload(
          id: 'auth_4',
          name: 'John von Neumann',
          order: 4,
          affiliationIds: ['aff_eth', 'aff_cambridge'],
          email: 'vonneumann@ias.edu',
        ),
        const AuthorMetadataPayload(
          id: 'auth_5',
          name: 'Grace Hopper',
          order: 5,
          affiliationIds: ['aff_oxford'],
          email: 'hopper@navy.mil',
        ),
        const AuthorMetadataPayload(
          id: 'auth_6',
          name: 'Barbara Liskov',
          order: 6,
          affiliationIds: ['aff_cambridge'],
        ),
        const AuthorMetadataPayload(
          id: 'auth_7',
          name: 'Donald Knuth',
          order: 7,
          affiliationIds: ['aff_oxford'],
          email: 'knuth@cs.stanford.edu',
        ),
        const AuthorMetadataPayload(
          id: 'auth_8',
          name: 'Leslie Lamport',
          order: 8,
          affiliationIds: ['aff_eth'],
          email: 'lamport@microsoft.com',
        ),
      ];

      // Save project with authors and affiliations in projectContext
      final project = await repo.createProject(
        title: 'Foundations of Distributed Computing',
        projectContext: {
          'document_template': 'ieee_conference',
          'citation_style': 'ieee',
          'authors': authors.map((a) => a.toJson()).toList(),
          'affiliations': [aff1.toJson(), aff2.toJson(), aff3.toJson()],
        },
      );

      // Reload project from SQLite
      final loaded = await repo.getProject(project.id);
      expect(loaded, isNotNull);

      final loadedAuthors = (loaded!.projectContext['authors'] as List)
          .map((m) => AuthorMetadataPayload.fromJson(Map<String, Object?>.from(m as Map)))
          .toList();
      final loadedAffils = (loaded.projectContext['affiliations'] as List)
          .map((m) => AuthorAffiliationPayload.fromJson(Map<String, Object?>.from(m as Map)))
          .toList();

      expect(loadedAuthors, hasLength(8));
      expect(loadedAffils, hasLength(3));

      expect(loadedAuthors[0].name, 'Prof. Alan Turing');
      expect(loadedAuthors[0].isCorresponding, isTrue);
      expect(loadedAuthors[0].orcid, '0000-0002-1825-0001');
      expect(loadedAuthors[0].affiliationIds, ['aff_cambridge']);

      expect(loadedAuthors[3].name, 'John von Neumann');
      expect(loadedAuthors[3].affiliationIds, ['aff_eth', 'aff_cambridge']);

      expect(loadedAuthors[7].name, 'Leslie Lamport');
      expect(loadedAuthors[7].order, 8);

      expect(loadedAffils[0].institution, 'University of Oxford');
      expect(loadedAffils[2].institution, 'ETH Zurich');

      await repo.close();
    });
  });
}
