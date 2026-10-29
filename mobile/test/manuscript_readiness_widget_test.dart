import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:resbud_mobile/data/local_project_repository.dart';
import 'package:resbud_mobile/features/paper_editor/paper_editor_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'helpers/fake_export_api.dart';
import 'helpers/fake_generation_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tempDirectory;
  late LocalProjectRepository repository;
  late LocalProject project;
  late PaperVersion version1;
  late FakeGenerationApi fakeApi;
  late FakePaperExportApi fakeExportApi;
  late FakeDocxFileSaver fakeFileSaver;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('resbud-readiness-test-');
    repository = await LocalProjectRepository.open(
      path: p.join(tempDirectory.path, 'projects.sqlite'),
      factory: databaseFactoryFfi,
    );
    project = await repository.createProject(
      title: 'Distributed Consensus Benchmark',
      projectContext: {
        'title': 'Distributed Consensus Benchmark',
        'research_field': 'Computer Science',
        'research_question': 'How does network partition affect BFT commit latency?',
        'objectives': ['Measure latency bounds'],
        'claimed_contribution': 'Empirical validation',
        'methodology_status': 'provided',
        'methodology': 'Simulated cluster experiment.',
        'dataset_or_materials_status': 'not_available',
        'results_status': 'not_collected',
        'limitations_status': 'not_identified',
        'references': [
          {'id': 'castro1999', 'text': 'Castro, M., & Liskov, B. (1999). Practical Byzantine Fault Tolerance.'},
        ],
        'preferences': {
          'target_word_count': 1500,
          'desired_sections': ['introduction', 'methodology', 'results'],
          'citation_style': 'user_supplied',
        },
      },
      sourceDraft: 'Author experiment logs and source notes.',
    );

    final paperData = {
      'schema_version': 1,
      'title': 'Distributed Consensus Benchmark',
      'abstract': 'We empirically investigate Byzantine fault tolerance latency under adversarial network partitions.',
      'keywords': ['BFT', 'consensus'],
      'sections': [
        {
          'id': 'intro',
          'heading': 'Introduction',
          'content': 'Consensus is vital in distributed computing [citation needed].',
          'state': 'draft',
        },
        {
          'id': 'method',
          'heading': 'Methodology',
          'content': 'We deploy a cluster across multiple regions. [TODO: add latency table].',
          'state': 'draft',
        },
        {
          'id': 'results',
          'heading': 'Results',
          'content': '', // Intentionally blank section to test critical finding
          'state': 'needs_input',
        },
      ],
      'references': [
        {'id': 'castro1999', 'text': 'Castro, M., & Liskov, B. (1999). Practical Byzantine Fault Tolerance.'},
      ],
      'review_warnings': [
        {
          'code': 'MISSING_RESULTS',
          'severity': 'warning',
          'message': 'Results were not collected in the supplied research notes.',
          'section_id': 'results',
        },
      ],
    };

    version1 = await repository.savePaperVersion(
      projectId: project.id,
      schemaVersion: 1,
      paper: paperData,
      origin: PaperVersionOrigin.generation,
      metadata: {'generation_id': 'gen-readiness-1'},
    );

    fakeApi = FakeGenerationApi();
    fakeExportApi = FakePaperExportApi();
    fakeFileSaver = FakeDocxFileSaver();
  });

  tearDown(() async {
    await repository.close();
    await tempDirectory.delete(recursive: true);
  });

  Future<void> pumpEditor(
    WidgetTester tester, {
    Size surfaceSize = const Size(1200, 1200),
  }) async {
    tester.view.physicalSize = surfaceSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PaperEditorPage(
          repository: repository,
          generationApi: fakeApi,
          project: project,
          initialVersion: version1,
          exportApi: fakeExportApi,
          fileSaver: fakeFileSaver,
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
  }

  testWidgets('opens readiness review from AppBar and renders disclaimer and findings', (tester) async {
    await pumpEditor(tester);

    final reviewButton = find.byKey(const ValueKey('button-readiness-review'));
    expect(reviewButton, findsOneWidget);

    await tester.tap(reviewButton);
    await tester.pumpAndSettle();

    // Verify header and integrity disclaimer
    expect(find.text('Manuscript Readiness Review'), findsOneWidget);
    expect(find.textContaining('Deterministic structural review'), findsOneWidget);
    expect(find.textContaining('Structural Checklist:'), findsOneWidget);

    // Filter by Critical category
    final criticalChip = find.byKey(const ValueKey('chip-category-critical'));
    expect(criticalChip, findsOneWidget);
    await tester.tap(criticalChip);
    await tester.pumpAndSettle();
    expect(find.text('Section "Results" is blank'), findsOneWidget);
    expect(find.text('Placeholder text in "Methodology"'), findsNothing);

    // Filter by Editorial category
    final editorialChip = find.byKey(const ValueKey('chip-category-editorial'));
    expect(editorialChip, findsOneWidget);
    await tester.tap(editorialChip);
    await tester.pumpAndSettle();
    expect(find.text('Placeholder text in "Methodology"'), findsOneWidget);
    expect(find.text('Section "Results" is blank'), findsNothing);

    // Filter by Citations category
    final citationsChip = find.byKey(const ValueKey('chip-category-citations'));
    expect(citationsChip, findsOneWidget);
    await tester.tap(citationsChip);
    await tester.pumpAndSettle();
    expect(find.text('Citation placeholder in "Introduction"'), findsOneWidget);
    expect(find.text('Placeholder text in "Methodology"'), findsNothing);

    // Close sheet
    final closeButton = find.byKey(const ValueKey('button-close-readiness-sheet'));
    await tester.tap(closeButton);
    await tester.pumpAndSettle();

    expect(find.text('Manuscript Readiness Review'), findsNothing);
  });

  testWidgets('jump to section from readiness finding navigates directly to editor section', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byKey(const ValueKey('button-readiness-review')));
    await tester.pumpAndSettle();

    // Jump button for blank results section
    final jumpBtn = find.textContaining('Jump to "Results"').first;
    expect(jumpBtn, findsOneWidget);

    await tester.tap(jumpBtn);
    await tester.pumpAndSettle();

    // Sheet should close and editor should display the Results section card
    expect(find.text('Manuscript Readiness Review'), findsNothing);
    expect(find.text('Results'), findsWidgets);
  });

  testWidgets('outline rail exposes readiness review shortcut on wide viewports', (tester) async {
    await pumpEditor(tester, surfaceSize: const Size(1280, 900));

    final railButton = find.byKey(const ValueKey('button-readiness-rail'));
    expect(railButton, findsOneWidget);

    await tester.tap(railButton);
    await tester.pumpAndSettle();

    expect(find.text('Manuscript Readiness Review'), findsOneWidget);
  });
}
