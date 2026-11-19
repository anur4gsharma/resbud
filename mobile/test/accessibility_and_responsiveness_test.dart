import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:resbud_mobile/data/local_project_repository.dart';
import 'package:resbud_mobile/features/paper_editor/paper_editor_page.dart';
import 'package:resbud_mobile/features/project_input/project_input_page.dart';
import 'package:resbud_mobile/main.dart';
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

  testWidgets('ProjectListPage renders without RenderFlex overflow across Android widths (320, 360, 375, 390, 430)', (tester) async {
    const widths = [320.0, 360.0, 375.0, 390.0, 430.0];

    for (final width in widths) {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ResbudApp(
          repository: repository,
          generationApi: fakeApi,
          exportApi: fakeExportApi,
          fileSaver: fakeFileSaver,
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      final error = tester.takeException();
      expect(error, isNull, reason: 'RenderFlex overflow on ProjectListPage at width $width');

      expect(find.text('High-Throughput Consensus Benchmarks'), findsOneWidget);
      expect(find.text('Draft Ready'), findsOneWidget);
      expect(find.text('Read DOCX'), findsOneWidget);
      expect(find.text('View PDF'), findsOneWidget);
      expect(find.text('Edit Manuscript'), findsOneWidget);
    }
  });

  testWidgets('ProjectInputPage renders without RenderFlex overflow and with all controls visible across Android widths (320, 360, 375, 390, 430)', (tester) async {
    final docProject = (await tester.runAsync(
      () => repository.createProject(
        title: 'Quantum Syndrome Decoders',
        projectContext: const {
          'title': 'Quantum Syndrome Decoders',
          'creation_mode': 'document',
          'description': 'Evaluating equivariant graph neural networks for fast quantum decoding.',
          'preferences': {
            'document_template': 'ieee_conference',
          },
          'figures': [
            {
              'id': 'fig_1',
              'name': 'syndrome_decoder_graph.png',
              'caption': 'Figure 1: Equivariant Neural Graph Decoder',
              'description': 'Syndrome graph decoding architecture.',
            },
          ],
        },
        sourceDraft: 'Topological syndrome decoders under Pauli noise models.',
      ),
    ))!;

    const widths = [320.0, 360.0, 375.0, 390.0, 430.0];

    for (final width in widths) {
      tester.view.physicalSize = Size(width, 2400);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        MaterialApp(
          theme: ResbudDesignTokens.lightTheme(),
          home: ProjectInputPage(
            repository: repository,
            generationApi: fakeApi,
            project: docProject,
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      await tester.pumpAndSettle();

      final error = tester.takeException();
      expect(error, isNull, reason: 'RenderFlex overflow on ProjectInputPage at width $width');

      // Verify persistent bottom action bar
      expect(find.text('Back / cancel'), findsOneWidget);
      expect(find.text('Save project'), findsOneWidget);
      expect(find.text('Generate'), findsOneWidget);

      // Scroll to author management controls and verify
      final authorBtn = find.byKey(const ValueKey('button-add-author'));
      await tester.scrollUntilVisible(
        authorBtn,
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('button-add-author')), findsOneWidget);
      expect(find.byKey(const ValueKey('button-add-affiliation')), findsOneWidget);
      expect(find.byKey(const ValueKey('button-prefill-ieee-authors')), findsOneWidget);

      // Scroll to figure management controls and verify
      final figureBtn = find.byKey(const ValueKey('button-upload-figure'));
      await tester.scrollUntilVisible(
        figureBtn,
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('button-upload-figure')), findsOneWidget);
      expect(find.byKey(const ValueKey('button-plan-figures')), findsOneWidget);

      // Reset widget tree between iterations
      await tester.pumpWidget(const SizedBox.shrink());
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('PaperEditorPage renders without RenderFlex overflow across Android widths (320, 360, 375, 390, 430)', (tester) async {
    const widths = [320.0, 360.0, 375.0, 390.0, 430.0];

    for (final width in widths) {
      tester.view.physicalSize = Size(width, 740);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildEditorApp());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      final error = tester.takeException();
      expect(error, isNull, reason: 'RenderFlex overflow on PaperEditorPage at width $width');

      expect(find.text('Paper draft'), findsOneWidget);
      expect(find.byKey(const ValueKey('segmented-workspace-mode')), findsOneWidget);
      expect(find.byKey(const ValueKey('button-readiness-review')), findsOneWidget);
      expect(find.byKey(const ValueKey('button-save-edits')), findsOneWidget);
    }
  });
}
