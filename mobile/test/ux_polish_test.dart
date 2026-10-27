import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:resbud_mobile/data/local_project_repository.dart';
import 'package:resbud_mobile/features/paper_editor/paper_editor_page.dart';
import 'package:resbud_mobile/features/project_input/project_input_page.dart';
import 'package:resbud_mobile/main.dart';

import 'helpers/fake_export_api.dart';
import 'helpers/fake_generation_api.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory tempDirectory;
  late LocalProjectRepository repository;
  late FakeGenerationApi generationApi;
  late FakePaperExportApi exportApi;
  late FakeDocxFileSaver fileSaver;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('resbud-ux-test-');
    repository = await LocalProjectRepository.open(
      path: p.join(tempDirectory.path, 'projects.sqlite'),
      factory: databaseFactoryFfi,
    );
    generationApi = FakeGenerationApi();
    exportApi = FakePaperExportApi();
    fileSaver = FakeDocxFileSaver();
  });

  tearDown(() async {
    await repository.close();
    await tempDirectory.delete(recursive: true);
  });

  Future<void> pumpUntilFound(
    WidgetTester tester,
    Finder finder, {
    int maxAttempts = 30,
  }) async {
    for (var i = 0; i < maxAttempts; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (finder.evaluate().isNotEmpty) return;
    }
    expect(finder, findsAtLeastNWidgets(1));
  }

  group('UX Polish: ProjectListPage Empty States and Management', () {
    testWidgets('empty state displays create CTA button and opens creation dialog', (tester) async {
      await tester.pumpWidget(
        ResbudApp(
          repository: repository,
          generationApi: generationApi,
          exportApi: exportApi,
          fileSaver: fileSaver,
        ),
      );
      await pumpUntilFound(tester, find.text('Create your first project'));

      expect(find.text('Your projects will appear here.'), findsOneWidget);
      final ctaButton = find.text('Create your first project');
      expect(ctaButton, findsOneWidget);

      await tester.tap(ctaButton);
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('New project')),
        findsOneWidget,
      );
      expect(find.text('Working title'), findsOneWidget);
    });

    testWidgets('project list item options menu allows renaming project', (tester) async {
      final project = (await tester.runAsync(
        () => repository.createProject(
          title: 'Original Title',
          projectContext: const {'research_field': 'Physics'},
          sourceDraft: 'Some draft material here',
        ),
      ))!;

      await tester.pumpWidget(
        ResbudApp(
          repository: repository,
          generationApi: generationApi,
          exportApi: exportApi,
          fileSaver: fileSaver,
        ),
      );
      await pumpUntilFound(tester, find.text('Original Title'));

      final menuButton = find.byKey(ValueKey('project-menu-${project.id}'));
      expect(menuButton, findsOneWidget);

      await tester.tap(menuButton);
      await tester.pumpAndSettle();

      final renameItem = find.text('Rename');
      expect(renameItem, findsOneWidget);

      await tester.tap(renameItem);
      await tester.pumpAndSettle();

      expect(find.text('Rename project'), findsOneWidget);
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);

      await tester.enterText(textField, 'Renamed Quantum Paper');
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();

      await pumpUntilFound(tester, find.text('Renamed Quantum Paper'));
      expect(find.text('Renamed Quantum Paper'), findsOneWidget);
      expect(find.text('Original Title'), findsNothing);

      final updated = await tester.runAsync(() => repository.getProject(project.id));
      expect(updated?.title, 'Renamed Quantum Paper');
    });

    testWidgets('project list item options menu allows deleting project with confirmation', (tester) async {
      final project = (await tester.runAsync(
        () => repository.createProject(
          title: 'Project to Delete',
          projectContext: const {},
        ),
      ))!;

      await tester.pumpWidget(
        ResbudApp(
          repository: repository,
          generationApi: generationApi,
          exportApi: exportApi,
          fileSaver: fileSaver,
        ),
      );
      await pumpUntilFound(tester, find.text('Project to Delete'));

      final menuButton = find.byKey(ValueKey('project-menu-${project.id}'));
      await tester.tap(menuButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete this project?'), findsOneWidget);
      expect(
        find.textContaining('This permanently deletes the project and its saved version history.'),
        findsOneWidget,
      );

      // Confirm delete
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      await pumpUntilFound(tester, find.text('Your projects will appear here.'));
      expect(find.text('Project to Delete'), findsNothing);

      final deleted = await tester.runAsync(() => repository.getProject(project.id));
      expect(deleted, isNull);
    });
  });

  group('UX Polish: ProjectInputPage Status and Narrow Screen Responsiveness', () {
    testWidgets('save status badge transitions between Saved and Unsaved upon modification', (tester) async {
      final project = (await tester.runAsync(
        () => repository.createProject(
          title: 'Adaptive Computing',
          projectContext: const {
            'research_field': 'Computer Science',
            'research_question': 'How to optimize compute?',
            'objectives': ['Reduce latency'],
            'claimed_contribution': 'New scheduler',
          },
          sourceDraft: 'Existing source draft content that is sufficiently long.',
        ),
      ))!;

      await tester.pumpWidget(
        MaterialApp(
          home: ProjectInputPage(
            repository: repository,
            generationApi: generationApi,
            exportApi: exportApi,
            fileSaver: fileSaver,
            project: project,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final statusBadge = find.byKey(const ValueKey('project-save-status-badge'));
      expect(statusBadge, findsOneWidget);
      expect(find.descendant(of: statusBadge, matching: find.text('Saved')), findsOneWidget);

      // Edit field
      await tester.enterText(
        find.byKey(const ValueKey('input-title')),
        'Adaptive Computing Modified',
      );
      await tester.pump();

      expect(find.descendant(of: statusBadge, matching: find.text('Unsaved')), findsOneWidget);

      // Tap save
      await tester.tap(find.text('Save project'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(find.descendant(of: statusBadge, matching: find.text('Saved')), findsOneWidget);
    });

    testWidgets('renders cleanly on narrow viewport (320px width) without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final project = (await tester.runAsync(
        () => repository.createProject(
          title: 'Narrow Screen Test',
          projectContext: const {
            'research_field': 'Bioinformatics',
            'research_question': 'Protein fold prediction?',
            'objectives': ['Fold proteins'],
          },
          sourceDraft: 'Draft content for narrow viewport test.',
        ),
      ))!;

      await tester.pumpWidget(
        MaterialApp(
          home: ProjectInputPage(
            repository: repository,
            generationApi: generationApi,
            exportApi: exportApi,
            fileSaver: fileSaver,
            project: project,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify no overflow errors were thrown
      expect(tester.takeException(), isNull);
      expect(find.text('Back / cancel'), findsOneWidget);
      expect(find.text('Save project'), findsOneWidget);
      expect(find.text('Generate'), findsOneWidget);
    });
  });

  group('UX Polish: PaperEditorPage Save Status and Keyboard Dismiss', () {
    testWidgets('save status badge transitions Saved -> Unsaved -> Saved on edit and save', (tester) async {
      final project = (await tester.runAsync(
        () => repository.createProject(
          title: 'Editor UX Test',
          projectContext: const {},
          sourceDraft: 'Source draft for editor test',
        ),
      ))!;

      final version = (await tester.runAsync(
        () => repository.savePaperVersion(
          projectId: project.id,
          schemaVersion: 1,
          paper: const {
            'schema_version': 1,
            'title': 'Paper Draft Title',
            'abstract': 'Abstract text.',
            'sections': [
              {
                'id': 'introduction',
                'heading': 'Introduction',
                'content': 'Initial intro content.',
                'state': 'draft',
              },
            ],
            'keywords': ['AI', 'Testing'],
            'references': [],
            'review_warnings': [],
          },
          origin: PaperVersionOrigin.generation,
        ),
      ))!;

      await tester.pumpWidget(
        MaterialApp(
          home: PaperEditorPage(
            repository: repository,
            generationApi: generationApi,
            exportApi: exportApi,
            fileSaver: fileSaver,
            project: project,
            initialVersion: version,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('save-status-badge')), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);

      // Edit introduction section
      final introField = find.byKey(const ValueKey('section-content-introduction'));
      await tester.enterText(introField, 'Updated intro text with new insight.');
      await tester.pump();

      expect(find.text('Unsaved'), findsOneWidget);

      // Tap save edits
      await tester.tap(find.byKey(const ValueKey('button-save-edits')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Version 2 saved.'), findsOneWidget);
    });
  });
}
