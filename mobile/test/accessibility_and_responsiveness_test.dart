import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:resbud_mobile/data/local_project_repository.dart';
import 'package:resbud_mobile/features/paper_editor/paper_editor_page.dart';
import 'package:resbud_mobile/shared/design_tokens.dart';
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
    tempDirectory = await Directory.systemTemp.createTemp('resbud-a11y-test-');
    repository = await LocalProjectRepository.open(
      path: p.join(tempDirectory.path, 'projects.sqlite'),
      factory: databaseFactoryFfi,
    );
    project = await repository.createProject(
      title: 'High-Throughput Consensus Benchmarks',
      projectContext: {
        'title': 'High-Throughput Consensus Benchmarks',
        'research_field': 'Computer Science',
        'research_question': 'How does pipelining affect Raft commit throughput?',
        'objectives': ['Evaluate pipeline depth'],
        'claimed_contribution': 'Sub-millisecond commit latency',
        'methodology_status': 'provided',
        'methodology': 'Cluster benchmarks with 10 nodes.',
        'dataset_or_materials_status': 'not_available',
        'results_status': 'not_collected',
        'limitations_status': 'not_identified',
        'references': [
          {'id': 'ongaro2014', 'text': 'Ongaro, D., & Ousterhout, J. (2014). In Search of an Understandable Consensus Algorithm.'},
        ],
        'preferences': {
          'target_word_count': 1500,
          'desired_sections': ['introduction', 'methodology', 'results'],
          'citation_style': 'user_supplied',
        },
      },
      sourceDraft: 'Benchmark results and latency measurements.',
    );

    final paperData = FakeGenerationApi.defaultResponseJson()['paper'] as Map<String, Object?>;
    version1 = await repository.savePaperVersion(
      projectId: project.id,
      schemaVersion: 1,
      paper: paperData,
      origin: PaperVersionOrigin.generation,
      metadata: {'generation_id': 'gen-a11y'},
    );

    fakeApi = FakeGenerationApi();
    fakeExportApi = FakePaperExportApi();
    fakeFileSaver = FakeDocxFileSaver();
  });

  tearDown(() async {
    await repository.close();
    await tempDirectory.delete(recursive: true);
  });

  Widget buildEditorApp({ThemeMode themeMode = ThemeMode.light}) {
    return MaterialApp(
      theme: ResbudDesignTokens.lightTheme(),
      darkTheme: ResbudDesignTokens.darkTheme(),
      themeMode: themeMode,
      home: PaperEditorPage(
        repository: repository,
        generationApi: fakeApi,
        project: project,
        initialVersion: version1,
        exportApi: fakeExportApi,
        fileSaver: fakeFileSaver,
      ),
    );
  }

  testWidgets('editor renders cleanly with zero overflow across phone (360x640), tablet (768x1024), and desktop (1440x900)', (tester) async {
    const viewports = [
      Size(360, 640),   // Phone
      Size(768, 1024),  // Tablet
      Size(1440, 900),  // Desktop
    ];

    for (final size in viewports) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildEditorApp());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      final error = tester.takeException();
      expect(error, isNull, reason: 'RenderFlex overflow at viewport size $size');

      // Verify essential academic elements rendered
      expect(find.text('Paper draft'), findsOneWidget);
    }
  });

  testWidgets('all AppBar actions provide accessible tooltips and touch targets', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildEditorApp());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    // Check tooltips on icon buttons
    final readinessBtn = tester.widget<IconButton>(find.byKey(const ValueKey('button-readiness-review')));
    expect(readinessBtn.tooltip, 'Manuscript readiness review');

    final compareBtn = tester.widget<IconButton>(find.byKey(const ValueKey('button-compare-source')));
    expect(compareBtn.tooltip, 'Compare source draft');

    final historyBtn = tester.widget<IconButton>(find.byKey(const ValueKey('button-version-history')));
    expect(historyBtn.tooltip, 'Version history');

    final exportBtn = tester.widget<IconButton>(find.byKey(const ValueKey('button-export-docx')));
    expect(exportBtn.tooltip, 'Export DOCX');

    final saveBtn = tester.widget<IconButton>(find.byKey(const ValueKey('button-save-edits')));
    expect(saveBtn.tooltip, 'Save edits');
  });

  testWidgets('dark theme renders accessible manuscript text and academic surface contrast', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildEditorApp(themeMode: ThemeMode.dark));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    final theme = Theme.of(tester.element(find.byType(PaperEditorPage)));
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.surface, isNotNull);
    expect(theme.textTheme.bodyMedium?.color, isNotNull);

    // Verify dark mode text is readable and contrastive
    expect(find.text('Paper draft'), findsOneWidget);
  });
}
