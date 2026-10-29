import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:resbud_mobile/data/local_project_repository.dart';
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
    tempDirectory = await Directory.systemTemp.createTemp('resbud-onboard-test-');
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

  testWidgets('displays research philosophy onboarding guide card and dialog', (tester) async {
    await tester.pumpWidget(
      ResbudApp(
        repository: repository,
        generationApi: generationApi,
        exportApi: exportApi,
        fileSaver: fileSaver,
      ),
    );
    await pumpUntilFound(tester, find.byKey(const ValueKey('onboarding-guide-card')));

    // Verify banner text
    expect(find.text('Resbud Academic Writing Philosophy'), findsOneWidget);
    expect(find.textContaining('Strictly grounded in your notes'), findsOneWidget);

    // Tap guide card to open philosophy dialog
    await tester.tap(find.byKey(const ValueKey('onboarding-guide-card')));
    await tester.pumpAndSettle();

    expect(find.text('Research Integrity & Writing Philosophy'), findsOneWidget);
    expect(find.textContaining('Strictly Non-Hallucinatory Grounding'), findsOneWidget);
    expect(find.textContaining('Zero Cloud Retention'), findsOneWidget);
    expect(find.textContaining('Two Input Workflows'), findsOneWidget);

    // Dismiss dialog
    await tester.tap(find.widgetWithText(FilledButton, 'Understood'));
    await tester.pumpAndSettle();
    expect(find.text('Research Integrity & Writing Philosophy'), findsNothing);
  });

  testWidgets('toggles onboarding guide visibility via appbar action', (tester) async {
    await tester.pumpWidget(
      ResbudApp(
        repository: repository,
        generationApi: generationApi,
        exportApi: exportApi,
        fileSaver: fileSaver,
      ),
    );
    await pumpUntilFound(tester, find.byKey(const ValueKey('onboarding-guide-card')));

    // Toggle off
    await tester.tap(find.byKey(const ValueKey('button-toggle-guide')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('onboarding-guide-card')), findsNothing);

    // Toggle on
    await tester.tap(find.byKey(const ValueKey('button-toggle-guide')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('onboarding-guide-card')), findsOneWidget);
  });

  testWidgets('theme switcher toggles between dark and light modes', (tester) async {
    await tester.pumpWidget(
      ResbudApp(
        repository: repository,
        generationApi: generationApi,
        exportApi: exportApi,
        fileSaver: fileSaver,
        initialThemeMode: ThemeMode.light,
      ),
    );
    await pumpUntilFound(tester, find.byKey(const ValueKey('button-toggle-theme')));

    final themeBtn = find.byKey(const ValueKey('button-toggle-theme'));
    expect(themeBtn, findsOneWidget);

    // Tap theme toggle button
    await tester.tap(themeBtn);
    await tester.pumpAndSettle();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.themeMode, ThemeMode.dark);
  });

  testWidgets('project card renders document mode chip and metadata', (tester) async {
    await tester.runAsync(
      () => repository.createProject(
        title: 'Neural Decoder Research',
        projectContext: const {
          'creation_mode': 'document',
          'research_field': 'Quantum Computing',
          'description': 'Evaluating decoders for surface codes.',
        },
        sourceDraft: 'Topological quantum error correction notes.',
      ),
    );

    await tester.pumpWidget(
      ResbudApp(
        repository: repository,
        generationApi: generationApi,
        exportApi: exportApi,
        fileSaver: fileSaver,
      ),
    );
    await pumpUntilFound(tester, find.text('Neural Decoder Research'));

    expect(find.text('Document Mode'), findsOneWidget);
    expect(find.text('Quantum Computing'), findsOneWidget);
    expect(find.textContaining('Updated'), findsOneWidget);
  });
}
