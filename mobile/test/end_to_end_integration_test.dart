import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:resbud_mobile/data/local_project_repository.dart';
import 'package:resbud_mobile/features/export/docx_export_client.dart';
import 'package:resbud_mobile/features/generation/generation_api_client.dart';
import 'package:resbud_mobile/features/generation/generation_models.dart';
import 'package:resbud_mobile/features/project_input/project_input_page.dart';
import 'package:resbud_mobile/import/source_document_importer.dart';
import 'package:resbud_mobile/main.dart';

import 'helpers/fake_export_api.dart';
import 'helpers/fake_generation_api.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory tempDirectory;
  late LocalProjectRepository repository;
  late FakeGenerationApi fakeApi;
  late FakePaperExportApi fakeExportApi;
  late FakeDocxFileSaver fakeSaver;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('resbud-e2e-test-');
    repository = await LocalProjectRepository.open(
      path: p.join(tempDirectory.path, 'projects.sqlite'),
      factory: databaseFactoryFfi,
    );
    fakeApi = FakeGenerationApi();
    fakeExportApi = FakePaperExportApi();
    fakeSaver = FakeDocxFileSaver();
  });

  tearDown(() async {
    await repository.close();
    await tempDirectory.delete(recursive: true);
  });

  Future<void> pumpResbud(
    WidgetTester tester, {
    SourcePicker? sourcePicker,
  }) async {
    await tester.pumpWidget(
      ResbudApp(
        repository: repository,
        generationApi: fakeApi,
        exportApi: fakeExportApi,
        fileSaver: fakeSaver,
        sourcePicker: sourcePicker,
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.pumpAndSettle();
  }

  Future<void> pumpUntilFound(
    WidgetTester tester,
    Finder finder, {
    int maxTries = 30,
  }) async {
    for (var i = 0; i < maxTries; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (finder.evaluate().isNotEmpty) {
        await tester.pumpAndSettle();
        return;
      }
    }
    await tester.pumpAndSettle();
  }

  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    FocusManager.instance.primaryFocus?.unfocus();
    var iterations = 0;
    while (target.evaluate().isEmpty && iterations < 30) {
      final topLeft = tester.getTopLeft(find.byType(ListView).first);
      await tester.dragFrom(
        topLeft + const Offset(15, 200),
        const Offset(0, -250),
      );
      await tester.pumpAndSettle();
      iterations++;
    }
    if (target.evaluate().isNotEmpty) {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
    }
  }

  Future<void> populateProjectInputs(
    WidgetTester tester, {
    required String title,
    required String fieldText,
    required String question,
    required String objectives,
    required String draft,
    String? references,
  }) async {
    final titleFinder = find.byKey(const ValueKey('input-title'));
    if (titleFinder.evaluate().isNotEmpty) {
      await tester.enterText(titleFinder, title);
    }
    final descFinder = find.byKey(const ValueKey('input-description'));
    if (descFinder.evaluate().isNotEmpty) {
      await tester.enterText(descFinder, objectives);
    }
    final fullDraft = StringBuffer(draft);
    if (references != null && references.isNotEmpty) {
      fullDraft.writeln('\n\nReferences:\n$references');
    }
    // Populate source draft field
    final draftFinder = find.byKey(const ValueKey('input-source_draft'));
    await scrollTo(tester, draftFinder);
    await tester.enterText(draftFinder, fullDraft.toString());
  }

  testWidgets('full end-to-end vertical user journey with versioning, regen, and docx export', (
    tester,
  ) async {
    // 1. Boot app and verify empty state
    await pumpResbud(tester);
    expect(find.text('Resbud'), findsOneWidget);
    expect(find.text('Your projects will appear here.'), findsOneWidget);
    expect(find.textContaining('There is no cloud backup'), findsOneWidget);

    // 2. Create a local project
    await tester.tap(find.text('New project'));
    await tester.pumpAndSettle();

    expect(find.text('Working title'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Deep Learning in Oncology');
    await tester.tap(find.text('Create'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    // Verify navigated to ProjectInputPage
    expect(find.text('Research inputs'), findsOneWidget);
    expect(find.text('Upload Research Material'), findsOneWidget);

    // 3. Enter structured research details and source draft
    await populateProjectInputs(
      tester,
      title: 'Deep Learning in Oncology',
      fieldText: 'Medical Oncology & AI',
      question: 'Can deep neural networks reliably detect malignant lesions in histology images?',
      objectives: 'Evaluate sensitivity and specificity across multicenter clinical datasets.',
      draft: 'Histopathology tissue slides were scanned at 40x magnification. We trained a residual network with attention gating. Results demonstrated high diagnostic concordance with human pathologists.',
      references: 'Esteva, A. et al. (2017). Dermatologist-level classification. Nature, 542, 115-118.',
    );

    final saveFinder = find.text('Save project');
    if (saveFinder.evaluate().isNotEmpty) {
      await tester.tap(saveFinder);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }

    // 4. Review missing information before generation
    final reviewBtn = find.text('Review before generation');
    await scrollTo(tester, reviewBtn);
    await tester.tap(reviewBtn);
    await tester.pumpAndSettle();

    expect(find.text('Before generation'), findsOneWidget);
    expect(find.textContaining('Supplied information'), findsOneWidget);
    // Dismiss dialog
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // 5. Submit to backend using fake provider
    await tester.tap(find.text('Generate'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(fakeApi.callCount, 1);
    expect(fakeApi.lastRequest?.project.title, 'Deep Learning in Oncology');

    // Preview dialog appears with warnings
    expect(find.text('Review generated draft'), findsOneWidget);
    expect(find.text('Test Paper Title'), findsOneWidget);
    expect(find.text('Save generated paper'), findsOneWidget);

    // Accept preview -> save Version 1
    await tester.tap(find.text('Save generated paper'));
    await tester.pump();
    await pumpUntilFound(tester, find.byKey(const ValueKey('version-1')));

    final projects = await tester.runAsync(() => repository.listProjects());
    expect(projects, isNotEmpty);
    final currentProject = projects!.first;
    final versions = await tester.runAsync(
      () => repository.listPaperVersions(currentProject.id),
    );
    expect(versions, isNotEmpty);
    expect(versions!.length, 1);

    // 6. Navigate to PaperEditorPage by tapping Version 1 in saved versions
    final v1Tile = find.byKey(const ValueKey('version-1'));
    await scrollTo(tester, v1Tile);
    await tester.tap(v1Tile);
    await tester.pump();
    await pumpUntilFound(tester, find.byKey(const ValueKey('paper-title-input')));

    // In editor
    expect(find.byKey(const ValueKey('paper-title-input')), findsOneWidget);
    expect(find.byKey(const ValueKey('save-status-badge')), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('v1 · Full Generation'), findsOneWidget);

    // Edit abstract and persist edit
    final abstractInput = find.byKey(const ValueKey('paper-abstract-input'));
    await tester.enterText(abstractInput, 'Updated abstract with refined oncological metrics.');
    await tester.pump();

    expect(find.text('Unsaved'), findsOneWidget);

    // Tap Save draft
    await tester.tap(find.byKey(const ValueKey('button-save-edits')));
    await tester.pump();
    await pumpUntilFound(tester, find.text('v2 · Manual Edit'));

    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('v2 · Manual Edit'), findsOneWidget);

    // 7. Request selected-section replacement, preview it, reject it
    final regenMethodology = find.byKey(const ValueKey('button-regen-methodology'));
    await scrollTo(tester, regenMethodology);
    await tester.tap(regenMethodology);
    await tester.pumpAndSettle();

    expect(find.text('Regenerate Methodology'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('regeneration-instructions')),
      'Detail the 5-fold cross-validation scheme.',
    );
    await tester.tap(find.text('Generate proposal'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(fakeApi.sectionCallCount, 1);
    expect(find.text('Review replacement for Methodology'), findsOneWidget);

    // Reject proposal
    await tester.tap(find.text('Reject proposal'));
    await tester.pumpAndSettle();

    // Verify methodology content remains original
    final methodContentFinder = find.byKey(const ValueKey('section-content-methodology'));
    expect(
      (tester.widget(methodContentFinder) as TextFormField).controller?.text,
      'The methodology used in this research.',
    );

    // Now request replacement again and ACCEPT it
    await scrollTo(tester, regenMethodology);
    await tester.tap(regenMethodology);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Generate proposal'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(fakeApi.sectionCallCount, 2);
    expect(find.text('Review replacement for Methodology'), findsOneWidget);

    await tester.tap(find.text('Accept replacement'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(find.text('v3 · Section Regeneration'), findsOneWidget);

    // Verify methodology updated and unrelated section (abstract) survived in Version 3!
    expect(
      (tester.widget(methodContentFinder) as TextFormField).controller?.text,
      'Regenerated replacement content for methodology.',
    );

    final allVersions = await tester.runAsync(
      () => repository.listPaperVersions(currentProject.id),
    );
    expect(allVersions, isNotNull);
    expect(allVersions!.length, 3);
    final v3Payload = PaperDraftPayload.fromJson(allVersions.last.paper);
    expect(v3Payload.abstractText, 'Updated abstract with refined oncological metrics.');
    expect(
      v3Payload.sections.firstWhere((s) => s.id == 'methodology').content,
      'Regenerated replacement content for methodology.',
    );

    // 8. Close and reopen project; verify saved content and version history
    // Pop editor back to input page
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    // Verify we are back on ProjectInputPage and saved versions show v1, v2, v3
    final v3Finder = find.byKey(const ValueKey('version-3'));
    await scrollTo(tester, v3Finder);
    expect(v3Finder, findsOneWidget);
    expect(find.byKey(const ValueKey('version-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('version-1')), findsOneWidget);

    // Pop input page back to project list
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    if (find.text('Unsaved project changes').evaluate().isNotEmpty) {
      await tester.tap(find.text('Save and leave'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Deep Learning in Oncology'), findsOneWidget);

    // Reopen project
    await tester.tap(find.text('Deep Learning in Oncology'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    // Reopen Version 3
    final v3Reopen = find.byKey(const ValueKey('version-3'));
    await scrollTo(tester, v3Reopen);
    await tester.tap(v3Reopen);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    // Verify Version 3 in editor
    expect(find.text('v3 · Section Regeneration'), findsOneWidget);
    expect(find.text('Updated abstract with refined oncological metrics.'), findsOneWidget);

    // 9. Export the current paper to DOCX and parse it to verify content
    await tester.tap(find.byKey(const ValueKey('button-export-docx')));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(fakeExportApi.exportCallCount, 1);
    expect(fakeSaver.saveCallCount, 1);
    expect(fakeSaver.lastSavedBytes, isNotNull);

    // Open/parse exported DOCX bytes using SourceDocumentImporter
    const importer = SourceDocumentImporter();
    final parsedDocx = importer.importBytes(
      fileName: 'exported.docx',
      bytes: fakeSaver.lastSavedBytes!,
    );
    expect(parsedDocx.format, 'docx');
    expect(parsedDocx.text, contains('Test Paper Title'));
    expect(
      parsedDocx.text,
      contains('Regenerated replacement content for methodology.'),
    );
  });

  testWidgets('error resilience: generation timeout preserves user input and permits retry', (
    tester,
  ) async {
    fakeApi.nextError = const GenerationApiFailure(
      code: GenerationFailureCode.providerTimeout,
      requestId: 'req-timeout-99',
      mayHaveCompleted: true,
    );

    await pumpResbud(tester);

    await tester.tap(find.text('New project'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Timeout Resilience Test');
    await tester.tap(find.text('Create'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    await populateProjectInputs(
      tester,
      title: 'Timeout Resilience Test',
      fieldText: 'Bioinformatics',
      question: 'Question with timeout?',
      objectives: 'Test timeout fault recovery without losing drafts.',
      draft: 'Precious draft that must never be lost during failure.',
    );

    await tester.tap(find.text('Generate'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    // Verify error surfaced and input draft preserved
    expect(find.textContaining('The generation service timed out.'), findsOneWidget);
    expect(find.textContaining('Support request ID: req-timeout-99'), findsOneWidget);
    expect(find.text('Retry generation'), findsOneWidget);
    expect(
      find.text('Precious draft that must never be lost during failure.'),
      findsOneWidget,
    );

    // Retry dialog warning and second call succeeds
    await tester.tap(find.text('Retry generation'));
    await tester.pumpAndSettle();
    expect(find.text('Send another generation request?'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(fakeApi.callCount, 2);
    expect(find.text('Review generated draft'), findsOneWidget);
  });

  testWidgets('error resilience: export failure preserves editor state and unsaved changes', (
    tester,
  ) async {
    fakeExportApi.errorToThrow = const DocxExportFailure(
      code: DocxExportFailureCode.internalError,
      details: 'Conversion engine crashed.',
      requestId: 'export-fail-err-1',
    );

    await pumpResbud(tester);

    await tester.tap(find.text('New project'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Export Failure Test');
    await tester.tap(find.text('Create'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    await populateProjectInputs(
      tester,
      title: 'Export Failure Test',
      fieldText: 'Physics',
      question: 'Quantum mechanics question?',
      objectives: 'Simulate export failure on valid paper draft.',
      draft: 'Source draft content for export failure test.',
    );

    await tester.tap(find.text('Generate'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    // Review dialog -> save paper
    expect(find.text('Review generated draft'), findsOneWidget);
    await tester.tap(find.text('Save generated paper'));
    await tester.pump();
    await pumpUntilFound(tester, find.byKey(const ValueKey('version-1')));

    // Open version 1 in editor
    final v1Tile = find.byKey(const ValueKey('version-1'));
    await scrollTo(tester, v1Tile);
    await tester.tap(v1Tile);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    // In editor, add unsaved changes
    final abstractInput = find.byKey(const ValueKey('paper-abstract-input'));
    await tester.enterText(abstractInput, 'Modified abstract that must not be lost.');
    await tester.pump();

    // Trigger export
    await tester.tap(find.byKey(const ValueKey('button-export-docx')));
    await tester.pumpAndSettle();

    // Dialog asks whether to export saved or save-and-export
    expect(find.text('Unsaved edits'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('export-saved-button')));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(fakeExportApi.exportCallCount, 1);
    // Error is surfaced in snackbar / support detail
    expect(
      find.textContaining('The server encountered an error generating the DOCX document.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Support request ID: export-fail-err-1'),
      findsOneWidget,
    );

    // Editor content is still intact
    expect(
      (tester.widget(abstractInput) as TextFormField).controller?.text,
      'Modified abstract that must not be lost.',
    );
    expect(find.text('Unsaved'), findsOneWidget);
    expect(find.text('Unsaved'), findsOneWidget);
  });
}
