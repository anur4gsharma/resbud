import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:resbud_mobile/data/local_project_repository.dart';
import 'package:resbud_mobile/data/project_figure.dart';
import 'package:resbud_mobile/features/paper_editor/paper_editor_page.dart';
import 'package:resbud_mobile/features/paper_editor/manuscript_outline_view.dart';
import 'package:resbud_mobile/features/paper_editor/manuscript_review_panel.dart';
import 'package:resbud_mobile/features/paper_editor/section_formatting_toolbar.dart';

import 'helpers/fake_export_api.dart';
import 'helpers/fake_generation_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tempDirectory;
  late LocalProjectRepository repository;
  late LocalProject project;
  late PaperVersion initialVersion;
  late FakeGenerationApi fakeApi;
  late FakePaperExportApi fakeExportApi;
  late FakeDocxFileSaver fakeFileSaver;

  setUpAll(() {
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('resbud_workspace_test_');
    repository = await LocalProjectRepository.open(
      path: p.join(tempDirectory.path, 'projects.sqlite'),
      factory: databaseFactoryFfi,
    );

    project = await repository.createProject(
      title: 'Neural Architecture Search for Edge Devices',
      projectContext: {
        'title': 'Neural Architecture Search for Edge Devices',
        'research_field': 'Computer Systems',
        'research_question': 'Can micro-NAS reduce edge latency without sacrificing accuracy?',
        'objectives': ['Evaluate latency', 'Optimize energy usage'],
        'claimed_contribution': 'Lightweight hardware-aware search algorithm',
        'methodology_status': 'provided',
        'methodology': 'Pareto-optimal genetic search tested on 5 microcontroller families.',
        'dataset_or_materials_status': 'provided',
        'results_status': 'collected',
        'limitations_status': 'identified',
        'references': [
          {'id': 'ref_1', 'text': 'LeCun, Y. et al. (1998). Gradient-based learning.'},
          {'id': 'ref_2', 'text': 'He, K. et al. (2016). Deep Residual Learning for Image Recognition.'},
        ],
        'preferences': {
          'target_word_count': 2500,
          'desired_sections': ['introduction', 'methodology', 'results', 'discussion'],
          'citation_style': 'user_supplied',
        },
      },
      sourceDraft: 'Initial empirical benchmarks showed a 2.4x latency reduction.',
    );

    // Attach sample figures to repository
    final validPngBytes = Uint8List.fromList([
      137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
      0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196,
      137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 218, 99, 100, 248, 207,
      80, 15, 0, 3, 134, 1, 128, 90, 52, 125, 107, 0, 0, 0, 0,
      73, 69, 78, 68, 174, 66, 96, 130
    ]);
    final fig1 = ProjectFigure(
      id: 'fig_pareto',
      projectId: project.id,
      figureNumber: 1,
      filename: 'pareto_frontier.png',
      mimeType: 'image/png',
      fileSize: 67,
      caption: 'Pareto frontier of latency vs. top-1 accuracy on Cortex-M4.',
      altText: 'Scatter plot illustrating latency trade-offs.',
      storageKey: 'pareto_frontier.png',
      cachedBytes: validPngBytes,
      sectionId: 'results',
      placement: FigurePlacement.columnWidth,
    );
    final fig2 = ProjectFigure(
      id: 'fig_hardware',
      projectId: project.id,
      figureNumber: 2,
      filename: 'hardware_schematic.png',
      mimeType: 'image/png',
      fileSize: 67,
      caption: 'Hardware testbed configuration across target devices.',
      altText: 'Block diagram of experimental setup.',
      storageKey: 'hardware_schematic.png',
      cachedBytes: validPngBytes,
      sectionId: 'methodology',
      placement: FigurePlacement.fullWidth,
    );
    await repository.saveProjectFigures(project.id, [fig1, fig2]);

    final samplePaper = {
      'schema_version': 1,
      'title': 'Neural Architecture Search for Edge Devices',
      'abstract': 'We propose an ultra-compact NAS framework specifically tailored for edge devices.',
      'keywords': ['Edge AI', 'Neural Architecture Search', 'Microcontrollers'],
      'page_layout': 'two_column_academic',
      'sections': [
        {
          'id': 'introduction',
          'heading': 'Introduction',
          'content': 'Edge computing requires strict energy constraints [ref_1].\n\n### Motivation\nPrior methods overlook memory limits.',
          'state': 'draft',
        },
        {
          'id': 'methodology',
          'heading': 'Methodology',
          'content': 'Our algorithm constructs candidates via Pareto search.\n\n| Param | Value |\n| --- | --- |\n| Epochs | 100 |\n\n\$\$\n\\min_a \\mathcal{L}(a) + \\beta \\cdot \\text{Latency}(a)\n\$\$',
          'state': 'draft',
        },
        {
          'id': 'results',
          'heading': 'Results',
          'content': 'Latency was reduced by 2.4x with less than 0.5% accuracy drop [ref_2].',
          'state': 'draft',
        },
        {
          'id': 'discussion',
          'heading': 'Discussion',
          'content': 'Future investigations should extend to neuromorphic chips.',
          'state': 'draft',
        },
      ],
      'references': [
        {
          'id': 'ref_1',
          'text': 'LeCun, Y. et al. (1998). Gradient-based learning.',
          'citation_number': 1,
          'is_cited': true,
        },
        {
          'id': 'ref_2',
          'text': 'He, K. et al. (2016). Deep Residual Learning for Image Recognition.',
          'citation_number': 2,
          'is_cited': true,
        },
      ],
      'review_warnings': [
        {
          'code': 'MISSING_RESULTS',
          'severity': 'warning',
          'message': 'Consider verifying accuracy with 5-fold cross-validation.',
          'section_id': 'results',
        },
      ],
    };

    initialVersion = await repository.savePaperVersion(
      projectId: project.id,
      schemaVersion: 1,
      paper: samplePaper,
      origin: PaperVersionOrigin.generation,
      metadata: {'generated_words': 1200, 'requested_words': 2500},
    );

    fakeApi = FakeGenerationApi();
    fakeExportApi = FakePaperExportApi();
    fakeFileSaver = FakeDocxFileSaver();
  });

  tearDown(() async {
    await repository.close();
    if (tempDirectory.existsSync()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    await tester.dragUntilVisible(
      target,
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 100));
    await tester.pumpAndSettle();
  }

  Future<void> pumpWorkspace(
    WidgetTester tester, {
    Size surfaceSize = const Size(400, 800),
    PaperWorkspaceMode initialMode = PaperWorkspaceMode.editor,
  }) async {
    tester.view.physicalSize = surfaceSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(useMaterial3: true),
        home: PaperEditorPage(
          repository: repository,
          generationApi: fakeApi,
          project: project,
          initialVersion: initialVersion,
          initialMode: initialMode,
          exportApi: fakeExportApi,
          fileSaver: fakeFileSaver,
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  group('RESBUD Manuscript Workspace Redesign Test Suite', () {
    testWidgets('1. Workspace initializes with clear save status and section content', (tester) async {
      await pumpWorkspace(tester);

      expect(find.text('Paper draft'), findsOneWidget);
      expect(find.byKey(const ValueKey('save-status-badge')), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
      expect(find.byKey(const ValueKey('button-manage-figures')), findsOneWidget);
      expect(find.byKey(const ValueKey('segmented-editor-subarea')), findsOneWidget);

      await scrollTo(tester, find.byKey(const ValueKey('paper-title-input')));
      expect(find.byKey(const ValueKey('paper-title-input')), findsOneWidget);
      expect(find.byKey(const ValueKey('paper-abstract-input')), findsOneWidget);
    });

    testWidgets('2. Responsive layout: wide viewport displays split outline rail', (tester) async {
      await pumpWorkspace(tester, surfaceSize: const Size(1200, 900));

      expect(find.text('Manuscript Outline'), findsOneWidget);
      expect(find.text('Title & Abstract'), findsOneWidget);
      expect(find.text('References (2)'), findsAtLeastNWidgets(1));
      expect(find.byKey(const ValueKey('button-readiness-rail')), findsOneWidget);
      // Editing surface remains available simultaneously on wide screen
      expect(find.byKey(const ValueKey('paper-title-input')), findsOneWidget);
    });

    testWidgets('3. Mobile sub-area switcher toggles between Outline, Editor, and Review panels', (tester) async {
      await pumpWorkspace(tester, surfaceSize: const Size(390, 844));

      // Defaults to Editor view (subarea 1)
      await scrollTo(tester, find.byKey(const ValueKey('paper-title-input')));
      expect(find.byKey(const ValueKey('paper-title-input')), findsOneWidget);

      // Switch to Outline (subarea 0)
      await tester.tap(find.text('Outline'));
      await tester.pumpAndSettle();

      expect(find.byType(ManuscriptOutlineView), findsOneWidget);
      expect(find.text('Title & Abstract'), findsOneWidget);
      expect(find.byKey(const ValueKey('outline-section-introduction')), findsOneWidget);
      expect(find.byKey(const ValueKey('outline-section-methodology')), findsOneWidget);

      // Switch to Review (subarea 2)
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();

      expect(find.byType(ManuscriptReviewPanel), findsOneWidget);
      expect(find.text('Review Findings & Academic Guidance'), findsOneWidget);

      // Switch back to Editor (subarea 1)
      await tester.tap(find.text('Editor'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('paper-title-input')), findsOneWidget);
    });

    testWidgets('4. Section jump from Outline switches subarea to Editor and scrolls to target', (tester) async {
      await pumpWorkspace(tester, surfaceSize: const Size(390, 844));

      // Open Outline subarea
      await tester.tap(find.text('Outline'));
      await tester.pumpAndSettle();

      // Tap Methodology in outline
      await tester.tap(find.widgetWithText(ListTile, 'Methodology'));
      await tester.pumpAndSettle();

      // Switched automatically to Editor and Methodology is visible
      expect(find.byKey(const ValueKey('section-content-methodology')), findsOneWidget);
    });

    testWidgets('5. Formatting toolbar inserts bold, italics, tables, and equations into section', (tester) async {
      await pumpWorkspace(tester, surfaceSize: const Size(430, 932));

      final introContentFinder = find.byKey(const ValueKey('section-content-introduction'));
      await scrollTo(tester, introContentFinder);
      expect(introContentFinder, findsOneWidget);

      // Verify Formatting Toolbar exists for the section
      expect(find.byType(SectionFormattingToolbar), findsWidgets);

      // Tap Bold button
      await tester.tap(find.byTooltip('Bold (**text**)').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('**bold text**'), findsOneWidget);
      expect(find.text('Unsaved'), findsOneWidget);

      // Tap Table button
      await tester.tap(find.byTooltip('Insert Markdown Table').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('| Column 1 | Column 2 | Column 3 |'), findsOneWidget);

      // Tap Math button
      await tester.tap(find.byTooltip(r'Inline Math ($x^2$)').first);
      await tester.pumpAndSettle();

      expect(find.textContaining(r'$x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$'), findsOneWidget);
    });

    testWidgets('6. Citation picker modal inserts formatted citation reference tag', (tester) async {
      await pumpWorkspace(tester, surfaceSize: const Size(430, 932));

      final introContentFinder = find.byKey(const ValueKey('section-content-introduction'));
      await scrollTo(tester, introContentFinder);

      // Scroll formatting toolbar horizontally and tap Insert Citation button
      final citeBtn = find.byTooltip('Insert Citation [N]').first;
      await tester.ensureVisible(citeBtn);
      await tester.pumpAndSettle();
      await tester.tap(citeBtn);
      await tester.pumpAndSettle();

      // Citation picker sheet opens with bibliographic items
      expect(find.text('Insert In-Text Citation'), findsOneWidget);
      expect(find.textContaining('LeCun, Y. et al.'), findsOneWidget);

      // Select reference 1
      await tester.tap(find.byKey(const ValueKey('cite-ref-ref_1')));
      await tester.pumpAndSettle();

      // Sheet closes and citation tag [1] is inserted in text field
      expect(find.text('Insert In-Text Citation'), findsNothing);
      expect(find.textContaining('[1]'), findsWidgets);
    });

    testWidgets('7. Equation rendering preview toggles native DocxDocumentCanvas for section', (tester) async {
      await pumpWorkspace(tester, surfaceSize: const Size(430, 932));

      final previewMathBtn = find.byKey(const ValueKey('button-preview-math-methodology'));
      await scrollTo(tester, previewMathBtn);

      // Preview is initially hidden
      expect(find.byKey(const ValueKey('section-preview-methodology')), findsNothing);

      // Toggle preview on
      await tester.tap(previewMathBtn);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('section-preview-methodology')), findsOneWidget);
      expect(find.text('Rendered Mathematics & Formatting Preview'), findsOneWidget);

      // Toggle preview off
      await scrollTo(tester, previewMathBtn);
      await tester.tap(previewMathBtn);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('section-preview-methodology')), findsNothing);
    });

    testWidgets('8. Figure manager allows inspecting figures and inserting markdown reference', (tester) async {
      await pumpWorkspace(tester);

      // Open Figure Manager from AppBar
      final figManagerBtn = find.byKey(const ValueKey('button-manage-figures'));
      await tester.tap(figManagerBtn);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();

      expect(find.text('Manuscript Figures & Media'), findsOneWidget);
      expect(find.text('pareto_frontier.png'), findsOneWidget);
      expect(find.text('hardware_schematic.png'), findsOneWidget);

      // Tap Insert on the first figure
      await tester.tap(find.text('Insert').first);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pumpAndSettle();

      // Sheet closes and markdown figure tag is inserted into associated section (results)
      expect(find.text('Manuscript Figures & Media'), findsNothing);
      await scrollTo(tester, find.byKey(const ValueKey('section-content-results')));
      expect(find.textContaining('![Pareto frontier'), findsWidgets);
    });

    testWidgets('9. Adding a new section via outline modal updates manuscript structure', (tester) async {
      await pumpWorkspace(tester);

      // Switch to Outline subarea
      await tester.tap(find.text('Outline'));
      await tester.pumpAndSettle();

      // Tap + Add Section button
      final addSectionBtn = find.byKey(const ValueKey('button-add-section'));
      await tester.tap(addSectionBtn);
      await tester.pumpAndSettle();

      expect(find.text('Add Manuscript Section'), findsOneWidget);

      // Enter heading
      await tester.enterText(find.byType(TextField).first, 'Broader Impact');
      await tester.tap(find.byKey(const ValueKey('confirm-add-section-button')));
      await tester.pumpAndSettle();

      // New section appears in Outline
      expect(find.text('Broader Impact'), findsOneWidget);
      expect(find.text('SECTIONS (5)'), findsOneWidget);

      // Switch to Editor and verify new section card exists
      await tester.tap(find.text('Editor'));
      await tester.pumpAndSettle();

      await scrollTo(tester, find.text('Paper sections (5)'));
      expect(find.text('Paper sections (5)'), findsOneWidget);
    });

    testWidgets('10. Reordering sections updates manuscript order', (tester) async {
      await pumpWorkspace(tester);

      // Switch to Outline
      await tester.tap(find.text('Outline'));
      await tester.pumpAndSettle();

      // Open menu for Methodology (second section)
      final menuBtn = find.byKey(const ValueKey('outline-menu-methodology'));
      await tester.tap(menuBtn);
      await tester.pumpAndSettle();

      // Tap Move up
      await tester.tap(find.text('Move up'));
      await tester.pumpAndSettle();

      // Methodology is now first section
      expect(find.text('Unsaved'), findsOneWidget);
    });

    testWidgets('11. Document layout toggle switches between Single and Two-Column IEEE Academic', (tester) async {
      await pumpWorkspace(tester, surfaceSize: const Size(600, 900));

      final layoutToggle = find.byKey(const ValueKey('button-layout-toggle'));
      expect(layoutToggle, findsOneWidget);

      // Initially two-column
      await tester.tap(layoutToggle);
      await tester.pumpAndSettle();

      expect(find.text('Switched layout to Standard Single-Column.'), findsOneWidget);
      expect(find.text('Unsaved'), findsOneWidget);

      // Switch back
      await tester.tap(layoutToggle);
      await tester.pumpAndSettle();

      expect(find.text('Switched layout to Two-Column Academic (IEEE format).'), findsOneWidget);
    });

    testWidgets('12. Readiness review panel navigation jumps to warning section in editor', (tester) async {
      await pumpWorkspace(tester);

      // Switch to Review subarea
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();

      expect(find.text('Review Findings & Academic Guidance'), findsOneWidget);
      expect(find.textContaining('Consider verifying accuracy with 5-fold cross-validation.'), findsOneWidget);

      // Scroll to and tap "Jump to <section>" button
      final jumpBtn = find.textContaining('Jump to').first;
      await tester.ensureVisible(jumpBtn);
      await tester.pumpAndSettle();
      await tester.tap(jumpBtn);
      await tester.pumpAndSettle();

      // Switched to Editor and Results section is visible
      expect(find.byKey(const ValueKey('section-content-results')), findsOneWidget);
    });
  });
}
