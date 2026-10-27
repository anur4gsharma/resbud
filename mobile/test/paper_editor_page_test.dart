import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:resbud_mobile/data/local_project_repository.dart';
import 'package:resbud_mobile/features/export/docx_export_client.dart';
import 'package:resbud_mobile/features/export/docx_file_saver.dart';
import 'package:resbud_mobile/features/generation/generation_models.dart';
import 'package:resbud_mobile/features/paper_editor/paper_editor_page.dart';

import 'helpers/fake_generation_api.dart';

class FakePaperExportApi implements PaperExportApi {
  int exportCallCount = 0;
  PaperDraftPayload? lastExportedPaper;
  DocxExportResult? resultToReturn;
  Object? errorToThrow;

  @override
  Future<DocxExportResult> exportDocx(PaperDraftPayload paper) async {
    exportCallCount++;
    lastExportedPaper = paper;
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return resultToReturn ??
        DocxExportResult(
          bytes: Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0x00, 0x00]),
          suggestedFilename: 'resbud-${paper.title.toLowerCase().replaceAll(' ', '-')}.docx',
          requestId: 'test-export-req-1',
        );
  }
}

class FakeDocxFileSaver implements DocxFileSaver {
  int saveCallCount = 0;
  Uint8List? lastSavedBytes;
  String? lastSuggestedFilename;
  String? pathToReturn;
  Object? errorToThrow;

  @override
  Future<String> saveDocx({
    required Uint8List bytes,
    required String suggestedFilename,
  }) async {
    saveCallCount++;
    lastSavedBytes = bytes;
    lastSuggestedFilename = suggestedFilename;
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return pathToReturn ?? '/simulated/documents/$suggestedFilename';
  }
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory tempDirectory;
  late LocalProjectRepository repository;
  late LocalProject project;
  late PaperVersion version1;
  late FakeGenerationApi fakeApi;
  late FakePaperExportApi fakeExportApi;
  late FakeDocxFileSaver fakeFileSaver;

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
    fakeExportApi = FakePaperExportApi();
    fakeFileSaver = FakeDocxFileSaver();
  });

  tearDown(() async {
    await repository.close();
    await tempDirectory.delete(recursive: true);
  });

  Future<void> pumpEditor(
    WidgetTester tester, {
    PaperVersion? version,
    Size? surfaceSize,
    PaperExportApi? exportApi,
    DocxFileSaver? fileSaver,
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
          exportApi: exportApi ?? fakeExportApi,
          fileSaver: fileSaver ?? fakeFileSaver,
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

  testWidgets('saved and unsaved status badge accurately reflects editor dirty state', (
    tester,
  ) async {
    await pumpEditor(tester);

    // Initial state is Saved
    expect(find.byKey(const ValueKey('save-status-badge')), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);

    // Make an edit to title
    final titleFinder = find.byKey(const ValueKey('paper-title-input'));
    await tester.enterText(titleFinder, 'Newly Updated Paper Title');
    await tester.pumpAndSettle();

    // Status transitions to Unsaved
    expect(find.text('Unsaved'), findsOneWidget);

    // Tap save button
    await tester.tap(find.byKey(const ValueKey('button-save-edits')));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    // Status transitions back to Saved
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Version 2 saved.'), findsOneWidget);
  });

  testWidgets('version history lists all versions and allows restoring prior snapshot with explicit confirmation', (
    tester,
  ) async {
    // Create Version 2 in database with distinct title
    final v2Paper = Map<String, Object?>.from(version1.paper)
      ..['title'] = 'Version 2 Distinct Title';
    final version2 = await tester.runAsync(
      () => repository.savePaperVersion(
        projectId: project.id,
        schemaVersion: 1,
        paper: v2Paper,
        origin: PaperVersionOrigin.manualEdit,
      ),
    );

    await pumpEditor(tester, version: version2);

    expect(find.textContaining('v2 · Manual Edit'), findsOneWidget);

    // Open version history sheet
    await tester.tap(find.byKey(const ValueKey('button-version-history')));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Version history'), findsOneWidget);
    expect(find.text('2 immutable snapshots recorded'), findsOneWidget);
    expect(find.text('Version 2'), findsOneWidget);
    expect(find.text('Active in editor'), findsOneWidget);
    expect(find.text('Version 1'), findsOneWidget);

    // Tap restore button on Version 1
    final restoreV1Btn = find.byKey(const ValueKey('button-restore-v1'));
    expect(restoreV1Btn, findsOneWidget);
    await tester.tap(restoreV1Btn);
    await tester.pumpAndSettle();

    // Confirmation dialog appears
    expect(find.text('Restore Version 1?'), findsOneWidget);
    expect(
      find.textContaining('Restoring Version 1 will create a new version containing its content.'),
      findsOneWidget,
    );

    // Confirm restore
    await tester.tap(find.byKey(const ValueKey('confirm-restore-button')));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    // Bottom sheet is dismissed and success snackbar appears
    expect(find.text('Version history'), findsNothing);
    expect(find.text('Restored Version 1 as Version 3.'), findsOneWidget);

    // Header now reflects v3 restored from v1
    expect(find.textContaining('v3 · Manual Edit (restored from v1)'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);

    // Repository has 3 versions and older versions are preserved
    final versions = await tester.runAsync(
      () => repository.listPaperVersions(project.id),
    );
    expect(versions!.length, 3);
    expect(versions[0].versionNumber, 1);
    expect(versions[0].paper['title'], 'Test Paper Title');
    expect(versions[1].versionNumber, 2);
    expect(versions[1].paper['title'], 'Version 2 Distinct Title');
    expect(versions[2].versionNumber, 3);
    expect(versions[2].paper['title'], 'Test Paper Title');
    expect(versions[2].metadata?['restored_from_version_number'], 1);
  });

  testWidgets('export DOCX exports current saved paper and invokes file saver without unsaved prompt', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.tap(find.byKey(const ValueKey('button-export-docx')));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(fakeExportApi.exportCallCount, 1);
    expect(fakeExportApi.lastExportedPaper?.title, 'Test Paper Title');
    expect(fakeFileSaver.saveCallCount, 1);
    expect(
      find.textContaining('Exported DOCX: /simulated/documents/resbud-test-paper-title.docx'),
      findsOneWidget,
    );
  });

  testWidgets('export DOCX with unsaved edits prompts choice and allows exporting saved snapshot without widget edits', (
    tester,
  ) async {
    await pumpEditor(tester);

    // Make unsaved edit in introduction section
    final introContentFinder = find.byKey(const ValueKey('section-content-introduction'));
    await scrollTo(tester, introContentFinder);
    await tester.enterText(introContentFinder, 'Unsaved in-progress introduction draft.');
    await tester.pumpAndSettle();

    // Tap export
    await tester.tap(find.byKey(const ValueKey('button-export-docx')));
    await tester.pumpAndSettle();

    // Unsaved edits dialog appears
    expect(find.text('Unsaved edits'), findsOneWidget);
    expect(
      find.textContaining('You have unsaved changes in the editor.'),
      findsOneWidget,
    );

    // Choose "Export saved (v1)"
    final exportSavedBtn = find.byKey(const ValueKey('export-saved-button'));
    expect(exportSavedBtn, findsOneWidget);
    await tester.tap(exportSavedBtn);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    // The exported paper content must match the SAVED version 1 content, NOT the unsaved widget content!
    expect(fakeExportApi.exportCallCount, 1);
    final exportedIntro = fakeExportApi.lastExportedPaper!.sections
        .firstWhere((s) => s.id == 'introduction')
        .content;
    expect(exportedIntro, 'This is the introduction section content for the test paper.');
    expect(exportedIntro, isNot('Unsaved in-progress introduction draft.'));

    // Editor still preserves the user's unsaved edits and status is still Unsaved
    expect(find.text('Unsaved in-progress introduction draft.'), findsOneWidget);
    expect(find.text('Unsaved'), findsOneWidget);
  });

  testWidgets('export DOCX with unsaved edits allows save-and-export option', (
    tester,
  ) async {
    await pumpEditor(tester);

    // Make unsaved edit in introduction section
    final introContentFinder = find.byKey(const ValueKey('section-content-introduction'));
    await scrollTo(tester, introContentFinder);
    await tester.enterText(introContentFinder, 'Brand new saved intro content.');
    await tester.pumpAndSettle();

    // Tap export
    await tester.tap(find.byKey(const ValueKey('button-export-docx')));
    await tester.pumpAndSettle();

    // Choose "Save & export"
    final saveAndExportBtn = find.byKey(const ValueKey('save-and-export-button'));
    expect(saveAndExportBtn, findsOneWidget);
    await tester.tap(saveAndExportBtn);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    // Repository now has Version 2
    final versions = await tester.runAsync(
      () => repository.listPaperVersions(project.id),
    );
    expect(versions!.length, 2);

    // Exported paper has the newly saved content
    expect(fakeExportApi.exportCallCount, 1);
    final exportedIntro = fakeExportApi.lastExportedPaper!.sections
        .firstWhere((s) => s.id == 'introduction')
        .content;
    expect(exportedIntro, 'Brand new saved intro content.');
    expect(find.text('Saved'), findsOneWidget);
    expect(find.textContaining('v2 · Manual Edit'), findsOneWidget);
  });

  testWidgets('export failure surfaces error and leaves saved content and editor edits intact', (
    tester,
  ) async {
    fakeExportApi.errorToThrow = const DocxExportFailure(
      code: DocxExportFailureCode.internalError,
      requestId: 'req-err-export-999',
    );

    await pumpEditor(tester);

    // Make an edit
    final introContentFinder = find.byKey(const ValueKey('section-content-introduction'));
    await scrollTo(tester, introContentFinder);
    await tester.enterText(introContentFinder, 'Important unsaved thoughts.');
    await tester.pumpAndSettle();

    // Tap export and choose export saved
    await tester.tap(find.byKey(const ValueKey('button-export-docx')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('export-saved-button')));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    // Error message surfaces
    expect(find.textContaining('The server encountered an error generating the DOCX document.'), findsOneWidget);
    expect(find.textContaining('req-err-export-999'), findsOneWidget);

    // Database still has only 1 version
    final versions = await tester.runAsync(
      () => repository.listPaperVersions(project.id),
    );
    expect(versions!.length, 1);

    // Editor still has the unsaved edits
    expect(find.text('Important unsaved thoughts.'), findsOneWidget);
    expect(find.text('Unsaved'), findsOneWidget);
  });
}
