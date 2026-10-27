import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:resbud_mobile/data/local_project_repository.dart';
import 'package:resbud_mobile/features/project_input/project_input_page.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory tempDirectory;
  late LocalProjectRepository repository;
  late LocalProject project;

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
    const groupLabels = [
      'Methodology',
      'Dataset Or Materials',
      'Results',
      'Limitations',
    ];
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
    for (var index = 0; index < 4; index++) {
      await scrollTo(tester, find.text(groupLabels[index]));
      await tester.tap(
        find.byKey(
          ValueKey(
            'status-${['methodology_status', 'dataset_or_materials_status', 'results_status', 'limitations_status'][index]}',
          ),
        ),
      );
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
}
