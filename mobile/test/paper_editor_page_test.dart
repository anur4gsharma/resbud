import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:resbud_mobile/data/local_project_repository.dart';
import 'package:resbud_mobile/features/generation/generation_models.dart';
import 'package:resbud_mobile/features/paper_editor/paper_editor_page.dart';

import 'helpers/fake_generation_api.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory tempDirectory;
  late LocalProjectRepository repository;
  late LocalProject project;
  late PaperVersion version1;
  late FakeGenerationApi fakeApi;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('resbud-editor-test-');
    repository = await LocalProjectRepository.open(
      path: p.join(tempDirectory.path, 'projects.sqlite'),
      factory: databaseFactoryFfi,
    );
    project = await repository.createProject(
      title: 'A Test Project',
      projectContext: {
        'title': 'A Test Project',
        'research_field': 'Computer Science',
        'research_question': 'Does code generation increase review time?',
        'objectives': ['Quantify review speed'],
        'claimed_contribution': 'Empirical benchmark',
        'methodology_status': 'provided',
        'methodology': 'Survey with 50 developers.',
        'dataset_or_materials_status': 'not_available',
        'results_status': 'not_collected',
        'limitations_status': 'not_identified',
        'references': [
          {'id': 'ref_1', 'text': 'Knuth, D. (1984). Literate Programming.'},
        ],
        'preferences': {
          'target_word_count': 1500,
          'desired_sections': ['introduction', 'methodology', 'results'],
          'citation_style': 'user_supplied',
        },
      },
      sourceDraft: 'Original research author notes and draft material.',
    );

    final paperData = FakeGenerationApi.defaultResponseJson()['paper'] as Map<String, Object?>;
    version1 = await repository.savePaperVersion(
      projectId: project.id,
      schemaVersion: 1,
      paper: paperData,
      origin: PaperVersionOrigin.generation,
      metadata: {'generation_id': 'gen-123'},
    );

    fakeApi = FakeGenerationApi();
  });

  tearDown(() async {
    await repository.close();
    await tempDirectory.delete(recursive: true);
  });

  Future<void> pumpEditor(
    WidgetTester tester, {
    PaperVersion? version,
    Size? surfaceSize,
  }) async {
    if (surfaceSize != null) {
      tester.view.physicalSize = surfaceSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    }

    await tester.pumpWidget(
      MaterialApp(
        home: PaperEditorPage(
          repository: repository,
          generationApi: fakeApi,
          project: project,
          initialVersion: version ?? version1,
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    await tester.dragUntilVisible(
      target,
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders title, abstract, keywords, warnings, sections, and references', (
    tester,
  ) async {
    await pumpEditor(tester);

    expect(find.text('Paper draft'), findsOneWidget);
    expect(find.textContaining('v1 · Full Generation'), findsOneWidget);

    // Integrity notice
    expect(
      find.textContaining('does not perform automated citation verification'),
      findsOneWidget,
    );

    // Title and abstract inputs
    expect(find.byKey(const ValueKey('paper-title-input')), findsOneWidget);
    expect(find.byKey(const ValueKey('paper-abstract-input')), findsOneWidget);

    // Keywords chips
    expect(find.text('testing'), findsOneWidget);
    expect(find.text('validation'), findsOneWidget);

    // Warnings
    expect(find.text('Review warnings (1)'), findsOneWidget);
    expect(find.text('WARNING'), findsOneWidget);
    expect(find.textContaining('Results section needs user-supplied data.'), findsOneWidget);

    // Scroll to Sections header
    await scrollTo(tester, find.text('Paper sections (3)'));
    expect(find.text('Paper sections (3)'), findsOneWidget);
    expect(find.text('Introduction'), findsOneWidget);

    // Scroll to Methodology & Results
    await scrollTo(tester, find.text('Methodology'));
    expect(find.text('Methodology'), findsOneWidget);

    await scrollTo(tester, find.text('Results'));
    expect(find.text('Results'), findsOneWidget);
    expect(find.text('Needs input'), findsOneWidget);

    // Scroll to References
    await scrollTo(tester, find.text('References (1)'));
    expect(find.text('References (1)'), findsOneWidget);
    expect(find.textContaining('Smith, J. (2024). Test reference.'), findsOneWidget);
  });

  testWidgets('navigates to target section from warning card', (
    tester,
  ) async {
    await pumpEditor(tester);

    final jumpButton = find.byKey(const ValueKey('jump-results'));
    expect(jumpButton, findsOneWidget);

    await tester.tap(jumpButton);
    await tester.pumpAndSettle();

    // Verify Results section is on screen
    expect(find.text('Results'), findsOneWidget);
    expect(find.byKey(const ValueKey('section-content-results')), findsOneWidget);
  });

  testWidgets('manual editing persists as new PaperVersion with manualEdit origin', (
    tester,
  ) async {
    await pumpEditor(tester);

    // Scroll to and edit introduction section content
    final introContentFinder = find.byKey(const ValueKey('section-content-introduction'));
    await scrollTo(tester, introContentFinder);
    await tester.enterText(introContentFinder, 'Manually edited introduction content.');
    await tester.pumpAndSettle();

    // Scroll back to top or tap Save button in AppBar
    await tester.tap(find.byKey(const ValueKey('button-save-edits')));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Version 2 saved.'), findsOneWidget);
    expect(find.textContaining('v2 · Manual Edit'), findsOneWidget);

    final versions = await tester.runAsync(
      () => repository.listPaperVersions(project.id),
    );
    expect(versions, isNotNull);
    expect(versions!.length, 2);

    final latest = versions.last;
    expect(latest.versionNumber, 2);
    expect(latest.origin, PaperVersionOrigin.manualEdit);

    final parsedPaper = PaperDraftPayload.fromJson(latest.paper);
    expect(
      parsedPaper.sections.firstWhere((s) => s.id == 'introduction').content,
      'Manually edited introduction content.',
    );
    // Non-edited sections must be unchanged
    expect(
      parsedPaper.sections.firstWhere((s) => s.id == 'methodology').content,
      'The methodology used in this research.',
    );
    // References preserved
    expect(parsedPaper.references.length, 1);
  });

  testWidgets('save failure surfaces error and leaves user edits intact in editor', (
    tester,
  ) async {
    await pumpEditor(tester);

    // Make manual edit
    final introContentFinder = find.byKey(const ValueKey('section-content-introduction'));
    await scrollTo(tester, introContentFinder);
    await tester.enterText(introContentFinder, 'My precious unsaved edits.');
    await tester.pumpAndSettle();

    // Delete project inside runAsync to force StateError on save
    await tester.runAsync(() => repository.deleteProject(project.id));

    await tester.tap(find.byKey(const ValueKey('button-save-edits')));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Could not save your changes. Your unsaved edits are preserved in the editor.'),
      findsOneWidget,
    );

    // The text field must still have the user's edits!
    expect(find.text('My precious unsaved edits.'), findsOneWidget);
  });

  testWidgets('section regeneration rejection leaves target and non-target sections unchanged', (
    tester,
  ) async {
    await pumpEditor(tester);

    // Scroll to and tap regenerate on methodology section
    final regenBtn = find.byKey(const ValueKey('button-regen-methodology'));
    await scrollTo(tester, regenBtn);
    await tester.tap(regenBtn);
    await tester.pumpAndSettle();

    expect(find.text('Regenerate Methodology'), findsOneWidget);
    expect(find.text('Current section content:'), findsOneWidget);

    // Enter instruction
    await tester.enterText(
      find.byKey(const ValueKey('regeneration-instructions')),
      'Please focus on sample sizes.',
    );
    await tester.tap(find.text('Generate proposal'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(fakeApi.sectionCallCount, 1);
    expect(fakeApi.lastSectionRequest?.sectionId, 'methodology');
    expect(fakeApi.lastSectionRequest?.userInstruction, 'Please focus on sample sizes.');

    // Review proposal preview dialog
    expect(find.text('Review replacement for Methodology'), findsOneWidget);
    expect(
      find.text('Regenerated replacement content for methodology.'),
      findsOneWidget,
    );

    // Choose REJECT
    await tester.tap(find.text('Reject proposal'));
    await tester.pumpAndSettle();

    // Dialog is dismissed
    expect(find.text('Review replacement for Methodology'), findsNothing);

    // Section content is still original
    final methodContentFinder = find.byKey(const ValueKey('section-content-methodology'));
    expect(
      (tester.widget(methodContentFinder) as TextFormField).controller?.text,
      'The methodology used in this research.',
    );

    // Database still has only 1 version
    final versions = await tester.runAsync(
      () => repository.listPaperVersions(project.id),
    );
    expect(versions!.length, 1);
  });

  testWidgets('section regeneration acceptance updates only target section and saves version', (
    tester,
  ) async {
    await pumpEditor(tester);

    final regenBtn = find.byKey(const ValueKey('button-regen-methodology'));
    await scrollTo(tester, regenBtn);
    await tester.tap(regenBtn);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Generate proposal'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Review replacement for Methodology'), findsOneWidget);

    // Choose ACCEPT
    await tester.tap(find.text('Accept replacement'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Accepted replacement for Methodology.'), findsOneWidget);
    expect(find.textContaining('v2 · Section Regeneration'), findsOneWidget);

    // Check database state
    final versions = await tester.runAsync(
      () => repository.listPaperVersions(project.id),
    );
    expect(versions!.length, 2);

    final acceptedVersion = versions.last;
    expect(acceptedVersion.versionNumber, 2);
    expect(acceptedVersion.origin, PaperVersionOrigin.sectionAcceptance);
    expect(acceptedVersion.metadata?['regenerated_section_id'], 'methodology');

    final parsed = PaperDraftPayload.fromJson(acceptedVersion.paper);
    // Target section replaced
    expect(
      parsed.sections.firstWhere((s) => s.id == 'methodology').content,
      'Regenerated replacement content for methodology.',
    );
    // Non-target sections byte-for-byte identical to version 1
    expect(
      parsed.sections.firstWhere((s) => s.id == 'introduction').content,
      'This is the introduction section content for the test paper.',
    );
    expect(
      parsed.sections.firstWhere((s) => s.id == 'results').content,
      '',
    );
    // References byte-for-byte identical
    expect(parsed.references.length, 1);
    expect(parsed.references.first.id, 'ref_1');
    expect(parsed.references.first.text, 'Smith, J. (2024). Test reference.');
    // Title identical
    expect(parsed.title, 'Test Paper Title');
  });

  testWidgets('compare source draft displays original project source text', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.tap(find.byKey(const ValueKey('button-compare-source')));
    await tester.pumpAndSettle();

    expect(find.text('Original source material'), findsOneWidget);
    expect(
      find.text('Original research author notes and draft material.'),
      findsOneWidget,
    );
  });

  testWidgets('handles small screen layout and long text without overflow', (
    tester,
  ) async {
    // 360 x 640 small screen
    await pumpEditor(
      tester,
      surfaceSize: const Size(360, 640),
    );

    final error = tester.takeException();
    expect(error, isNull);
    expect(find.text('Paper draft'), findsOneWidget);
  });
}
