import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:resbud_mobile/data/local_project_repository.dart';
import 'package:resbud_mobile/features/generation/generation_api_client.dart';
import 'package:resbud_mobile/features/project_input/project_input_page.dart';

import 'helpers/fake_generation_api.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory tempDirectory;
  late LocalProjectRepository repository;
  late LocalProject project;
  late FakeGenerationApi fakeApi;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('resbud-input-test-');
    repository = await LocalProjectRepository.open(
      path: p.join(tempDirectory.path, 'projects.sqlite'),
      factory: databaseFactoryFfi,
    );
    project = await repository.createProject(
      title: 'A working title',
      projectContext: const {},
    );
    fakeApi = FakeGenerationApi();
  });

  tearDown(() async {
    await repository.close();
    await tempDirectory.delete(recursive: true);
  });

  Future<void> pumpInput(
    WidgetTester tester, {
    SourcePicker? sourcePicker,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectInputPage(
          repository: repository,
          generationApi: fakeApi,
          project: project,
          sourcePicker: sourcePicker,
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.pumpAndSettle();
  }

  Finder field(String key) => find.byKey(ValueKey('input-$key'));

  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(target);
  }

  testWidgets('required fields show field-level validation errors', (
    tester,
  ) async {
    await pumpInput(tester);
    expect(find.text('Research inputs'), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('Research question'), findsOneWidget);
    expect(find.byType(TextFormField), findsAtLeastNWidgets(3));
    await tester.tap(find.text('Save project'));
    await tester.pumpAndSettle();
    expect(find.text('Complete the highlighted fields.'), findsOneWidget);
    expect(find.text('Research question is required.'), findsOneWidget);
  });

  testWidgets('status selectors expose the exact contract variants', (
    tester,
  ) async {
    await pumpInput(tester);
    final expectedOptions = <List<String>>[
      [
        'Provided',
        'Not available',
        'Not applicable',
        'Unknown / not supplied yet',
      ],
      [
        'Provided',
        'Not available',
        'Not applicable',
        'Unknown / not supplied yet',
      ],
      [
        'Provided',
        'Not collected',
        'Not available',
        'Not applicable',
        'Unknown / not supplied yet',
      ],
      [
        'Provided',
        'Not identified',
        'Not available',
        'Not applicable',
        'Unknown / not supplied yet',
      ],
    ];
    final statusKeys = [
      'methodology_status',
      'dataset_or_materials_status',
      'results_status',
      'limitations_status',
    ];
    for (var index = 0; index < 4; index++) {
      final dropdownFinder = find.byKey(ValueKey('status-${statusKeys[index]}'));
      await scrollTo(tester, dropdownFinder);
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();
      for (final option in expectedOptions[index]) {
        expect(find.text(option), findsWidgets);
      }
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
    'imports text through the validated importer and reports errors',
    (tester) async {
      await pumpInput(
        tester,
        sourcePicker: () async => (
          name: 'notes.txt',
          bytes: Uint8List.fromList('Imported draft'.codeUnits),
        ),
      );
      await scrollTo(tester, find.text('Import .txt or .docx'));
      await tester.tap(find.text('Import .txt or .docx'));
      await tester.pumpAndSettle();
      expect(
        find.text('Imported notes.txt. Save the project to keep this draft.'),
        findsOneWidget,
      );
      expect(find.text('Imported draft'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpInput(
        tester,
        sourcePicker: () async => (
          name: 'notes.pdf',
          bytes: Uint8List.fromList('not supported'.codeUnits),
        ),
      );
      await scrollTo(tester, find.text('Import .txt or .docx'));
      await tester.tap(find.text('Import .txt or .docx'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a UTF-8 .txt or .docx file.'), findsOneWidget);
    },
  );

  testWidgets('pre-generation summary shows supplied fields and warnings', (
    tester,
  ) async {
    await pumpInput(tester);
    await scrollTo(tester, find.text('Review before generation'));
    await tester.drag(find.byType(ListView), const Offset(0, -160));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review before generation'));
    await tester.pumpAndSettle();
    expect(find.text('Before generation'), findsOneWidget);
    expect(find.textContaining('No user-supplied references'), findsOneWidget);
    expect(
      find.textContaining('does not send your research anywhere'),
      findsOneWidget,
    );
  });

  testWidgets('save persists the project brief and source draft', (
    tester,
  ) async {
    const context = {
      'research_field': 'Computer science',
      'research_question': 'Old question',
      'objectives': ['Measure the outcome'],
      'claimed_contribution': '',
      'methodology_status': 'unknown',
      'dataset_or_materials_status': 'unknown',
      'results_status': 'unknown',
      'limitations_status': 'unknown',
    };
    await tester.runAsync(
      () => repository.updateProjectInputs(
        projectId: project.id,
        title: project.title,
        projectContext: context,
        sourceDraft: 'Saved source',
      ),
    );
    project = (await tester.runAsync(
      () async => (await repository.getProject(project.id))!,
    ))!;
    await pumpInput(tester);
    await tester.enterText(field('research_question'), 'Updated question');
    await tester.tap(find.text('Save project'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back / cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved project changes'), findsNothing);
    final saved = (await tester.runAsync(
      () async => (await repository.getProject(project.id))!,
    ))!;
    expect(saved.sourceDraft, 'Saved source');
    expect(saved.projectContext['research_question'], 'Updated question');
  });

  testWidgets('cancel offers discard and preserves the last saved draft', (
    tester,
  ) async {
    await tester.runAsync(
      () => repository.updateProjectInputs(
        projectId: project.id,
        title: project.title,
        projectContext: const {'research_question': 'Saved question'},
        sourceDraft: 'Saved source',
      ),
    );
    project = (await tester.runAsync(
      () async => (await repository.getProject(project.id))!,
    ))!;
    await pumpInput(tester);
    await scrollTo(tester, field('source_draft'));
    await tester.enterText(field('source_draft'), 'Unsaved replacement');
    await tester.tap(find.text('Back / cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved project changes'), findsOneWidget);
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(
      (await tester.runAsync(
        () async => (await repository.getProject(project.id))!,
      ))!.sourceDraft,
      'Saved source',
    );
  });

  Future<void> populateValidInputs(WidgetTester tester) async {
    await tester.enterText(field('title'), 'A Valid Title');
    await tester.enterText(field('research_field'), 'Computer Science');
    await tester.enterText(field('research_question'), 'A research question?');
    await scrollTo(tester, field('objectives'));
    await tester.enterText(field('objectives'), 'An objective to accomplish');
    await scrollTo(tester, field('source_draft'));
    await tester.enterText(field('source_draft'), 'Authoritative source draft text.');
  }

  testWidgets('generate validates inputs and does not call API when invalid', (
    tester,
  ) async {
    await pumpInput(tester);
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();
    expect(find.text('Complete the highlighted fields.'), findsOneWidget);
    expect(fakeApi.callCount, 0);
  });

  testWidgets('generation success shows review preview and saves paper version', (
    tester,
  ) async {
    await pumpInput(tester);
    await populateValidInputs(tester);

    await tester.tap(find.text('Generate'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(fakeApi.callCount, 1);
    expect(find.text('Review generated draft'), findsOneWidget);
    expect(find.text('Test Paper Title'), findsOneWidget);
    expect(find.text('Request ID: test-request-id-001'), findsOneWidget);
    expect(find.textContaining('Results section needs user-supplied data.'), findsOneWidget);

    await tester.tap(find.text('Save generated paper'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Generated paper saved as a new version on this device.'),
      findsOneWidget,
    );

    final versions = await tester.runAsync(
      () => repository.listPaperVersions(project.id),
    );
    expect(versions, isNotNull);
    expect(versions!.length, 1);
    expect(versions.first.versionNumber, 1);
    expect(versions.first.origin, PaperVersionOrigin.generation);
  });

  testWidgets('generation preview can be dismissed with keep editing without saving version', (
    tester,
  ) async {
    await pumpInput(tester);
    await populateValidInputs(tester);

    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();

    expect(find.text('Review generated draft'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();

    expect(find.text('Review generated draft'), findsNothing);
    final versions = await tester.runAsync(
      () => repository.listPaperVersions(project.id),
    );
    expect(versions, isEmpty);
  });

  testWidgets('generation failure preserves data and offers safe retry', (
    tester,
  ) async {
    fakeApi.nextError = const GenerationApiFailure(
      code: GenerationFailureCode.providerTimeout,
      requestId: 'timeout-req-123',
      mayHaveCompleted: true,
    );

    await pumpInput(tester);
    await populateValidInputs(tester);

    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();

    expect(fakeApi.callCount, 1);
    expect(find.textContaining('The generation service timed out.'), findsOneWidget);
    expect(find.textContaining('Support request ID: timeout-req-123'), findsOneWidget);
    expect(find.text('Retry generation'), findsOneWidget);

    // Verify saved data remains empty
    final versions = await tester.runAsync(
      () => repository.listPaperVersions(project.id),
    );
    expect(versions, isEmpty);

    // Tap retry -> shows warning dialog about potential duplicate
    await tester.tap(find.text('Retry generation'));
    await tester.pumpAndSettle();

    expect(find.text('Send another generation request?'), findsOneWidget);
    expect(find.textContaining('may still have completed'), findsOneWidget);

    // Retry dialog confirmation retries generation
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(fakeApi.callCount, 2);
    expect(find.text('Review generated draft'), findsOneWidget);
  });

  testWidgets('prevents duplicate generation submit while request is active', (
    tester,
  ) async {
    fakeApi.latency = const Duration(milliseconds: 300);

    await pumpInput(tester);
    await populateValidInputs(tester);

    await tester.tap(find.text('Generate'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Generating…'), findsOneWidget);
    expect(find.text('Generating paper draft — this may take a minute…'), findsOneWidget);

    // Tapping again does not issue second call
    await tester.tap(find.text('Generating…'), warnIfMissed: false);
    expect(fakeApi.callCount, 1);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Review generated draft'), findsOneWidget);
  });

  testWidgets('displays user-facing data transmission and privacy notice', (
    tester,
  ) async {
    await pumpInput(tester);
    final privacyCard = find.byKey(const ValueKey('privacy-transmission-card'));
    await scrollTo(tester, privacyCard);
    expect(privacyCard, findsOneWidget);
    expect(
      find.textContaining('Transmission Notice: Generating transmits your project facts'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Resbud does not store drafts on the server'),
      findsOneWidget,
    );
  });
}
