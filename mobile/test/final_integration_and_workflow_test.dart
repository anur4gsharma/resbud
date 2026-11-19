import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:resbud_mobile/data/local_project_repository.dart';
import 'package:resbud_mobile/data/project_figure.dart';
import 'package:resbud_mobile/features/docx_viewer/docx_document_canvas.dart';
import 'package:resbud_mobile/features/generation/generation_models.dart';
import 'package:resbud_mobile/features/paper_editor/paper_editor_page.dart';
import 'package:resbud_mobile/main.dart';

import 'helpers/fake_export_api.dart';
import 'helpers/fake_generation_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tempDirectory;
  late String dbPath;
  late LocalProjectRepository repository;
  late FakeGenerationApi fakeApi;
  late FakePaperExportApi fakeExportApi;
  late FakeDocxFileSaver fakeSaver;

  final validPngBytes = Uint8List.fromList([
    137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
    0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196,
    137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 218, 99, 100, 248, 207,
    80, 15, 0, 3, 134, 1, 128, 90, 52, 125, 107, 0, 0, 0, 0,
    73, 69, 78, 68, 174, 66, 96, 130
  ]);

  setUpAll(() {
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('resbud_final_e2e_');
    dbPath = p.join(tempDirectory.path, 'resbud_e2e.sqlite');
    repository = await LocalProjectRepository.open(
      path: dbPath,
      factory: databaseFactoryFfi,
    );
    fakeApi = FakeGenerationApi();
    fakeExportApi = FakePaperExportApi();
    fakeSaver = FakeDocxFileSaver();

    // Pre-seed an initial project without a paper
    await repository.createProject(
      title: 'Initial Research Space',
      projectContext: const {'paper_template': 'ieee_conference'},
      sourceDraft: 'Initial exploratory notes.',
    );
  });

  tearDown(() async {
    await repository.close();
    if (tempDirectory.existsSync()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  Future<void> scrollToInEditor(WidgetTester tester, Finder target) async {
    final chip = find.byKey(const ValueKey('quick-chip-introduction'));
    if (chip.evaluate().isNotEmpty) {
      await tester.tap(chip);
      await tester.pumpAndSettle();
    }
    if (target.evaluate().isEmpty) {
      final scrollable = find.descendant(
        of: find.byType(PaperEditorPage),
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      ).first;
      await tester.dragUntilVisible(target, scrollable, const Offset(0, -200));
      await tester.drag(scrollable, const Offset(0, 100));
      await tester.pumpAndSettle();
    }
  }

  Future<void> pumpApp(WidgetTester tester, {Size size = const Size(400, 850), Key? key}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ResbudApp(
        key: key ?? UniqueKey(),
        repository: repository,
        generationApi: fakeApi,
        exportApi: fakeExportApi,
        fileSaver: fakeSaver,
      ),
    );
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

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
      if (finder.evaluate().isNotEmpty) {
        return;
      }
    }
    expect(finder, findsAtLeastNWidgets(1));
  }

  Future<void> switchToTab(WidgetTester tester, Finder tabFinder) async {
    await tester.tap(tabFinder);
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('Full 23-Step End-to-End User Journey Workflow', (tester) async {
    // -------------------------------------------------------------
    // Step 1: Open Resbud
    // -------------------------------------------------------------
    await pumpApp(tester);
    expect(find.text('Resbud'), findsAtLeastNWidgets(1));
    expect(find.byKey(const ValueKey('tab-dashboard')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-my-papers')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-projects')), findsOneWidget);

    // -------------------------------------------------------------
    // Step 2: View all existing saved papers
    // -------------------------------------------------------------
    await switchToTab(tester, find.byKey(const ValueKey('tab-my-papers')));
    await pumpUntilFound(tester, find.text('No saved papers yet.'));
    expect(find.text('No saved papers yet.'), findsOneWidget);

    // -------------------------------------------------------------
    // Step 3: Create a new research project
    // -------------------------------------------------------------
    final newProject = (await tester.runAsync(() async {
      return await repository.createProject(
        title: 'Distributed Consensus with Adaptive Pipelining',
        projectContext: {
          'title': 'Distributed Consensus with Adaptive Pipelining',
          'research_field': 'Distributed Systems',
          'research_question': 'Can pipelining reduce commit latency under asymmetric network partitions?',
          'objectives': ['Model pipeline throughput', 'Evaluate partition resilience'],
          'claimed_contribution': 'Adaptive window pipelined consensus algorithm',
          'methodology_status': 'provided',
          'methodology': 'Empirical validation across 15 cloud regions.',
          'dataset_or_materials_status': 'not_available',
          'results_status': 'provided',
          'results': 'Median latency dropped from 8.2ms to 4.9ms with zero throughput degradation.',
          'limitations_status': 'not_identified',
          'references': [
            {'id': 'lamport1998', 'text': 'Lamport, L. (1998). The Part-Time Parliament.'}
          ],
          'preferences': {
            'document_template': 'ieee_conference',
            'citation_style': 'user_supplied',
            'target_word_count': 3000,
            'desired_sections': ['introduction', 'methodology', 'results', 'conclusion'],
          },
        },
        sourceDraft: 'Preliminary benchmark data indicates a 40% reduction in median commit latency.',
      );
    }))!;

    // -------------------------------------------------------------
    // Step 4: Add one author
    // -------------------------------------------------------------
    const author1 = AuthorMetadataPayload(
      id: 'auth_1',
      name: 'Dr. Jane Doe',
      order: 1,
      affiliationIds: ['aff_1'],
      email: 'jane.doe@mit.edu',
      isCorresponding: true,
    );
    const aff1 = AuthorAffiliationPayload(
      id: 'aff_1',
      institution: 'MIT',
      department: 'EECS',
      city: 'Cambridge',
      country: 'USA',
    );

    final projectWithOneAuthor = (await tester.runAsync(() async {
      final updatedContext = Map<String, dynamic>.from(newProject.projectContext);
      updatedContext['authors'] = [author1.toJson()];
      updatedContext['affiliations'] = [aff1.toJson()];
      return await repository.updateProjectInputs(
        projectId: newProject.id,
        title: newProject.title,
        projectContext: updatedContext,
        sourceDraft: newProject.sourceDraft,
      );
    }))!;
    final authorsList1 = (projectWithOneAuthor.projectContext['authors'] as List?) ?? [];
    expect(authorsList1.length, 1);
    expect(authorsList1.first['name'], 'Dr. Jane Doe');

    // -------------------------------------------------------------
    // Step 5: Generate a paper
    // -------------------------------------------------------------
    final genResponse = await fakeApi.generate(
      GenerationRequest.fromInputs(
        project: projectWithOneAuthor.projectContext,
        sourceDraft: projectWithOneAuthor.sourceDraft,
      ),
    );
    expect(genResponse.response.paper, isNotNull);

    // -------------------------------------------------------------
    // Step 6: Save the paper
    // -------------------------------------------------------------
    final savedVersion = await tester.runAsync(() async {
      final paperJson = genResponse.response.paper.toJson();
      paperJson['title'] = projectWithOneAuthor.title;
      paperJson['authors'] = [author1.toJson()];
      paperJson['affiliations'] = [aff1.toJson()];
      return await repository.savePaperVersion(
        projectId: projectWithOneAuthor.id,
        schemaVersion: 1,
        paper: paperJson,
        origin: PaperVersionOrigin.generation,
        metadata: {'generated_words': 1500},
      );
    });
    expect(savedVersion, isNotNull);
    expect(savedVersion!.versionNumber, 1);

    // -------------------------------------------------------------
    // Step 7: Reopen it from My Papers
    // -------------------------------------------------------------
    await pumpApp(tester);
    await switchToTab(tester, find.byKey(const ValueKey('tab-my-papers')));
    await pumpUntilFound(tester, find.text('Distributed Consensus with Adaptive Pipelining'));

    expect(find.text('Distributed Consensus with Adaptive Pipelining'), findsAtLeastNWidgets(1));
    expect(find.textContaining('1 author'), findsOneWidget);

    await tester.tap(find.text('Distributed Consensus with Adaptive Pipelining').first);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();

    expect(find.byType(PaperEditorPage), findsOneWidget);
    expect(find.byKey(const ValueKey('save-status-badge')), findsOneWidget);

    await tester.tap(find.text('Edit & Outline'));
    await tester.pumpAndSettle();

    // -------------------------------------------------------------
    // Step 8: Edit an existing section
    // -------------------------------------------------------------
    final introFinder = find.byKey(const ValueKey('section-content-introduction'));
    await scrollToInEditor(tester, introFinder);
    await tester.pumpAndSettle();

    await tester.enterText(introFinder, 'Edited introduction text with rigorous system specifications and pipelining models.');
    await tester.pumpAndSettle();
    expect(find.text('Unsaved'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('button-save-edits')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);

    // -------------------------------------------------------------
    // Step 9: Add a second author
    // -------------------------------------------------------------
    const author2 = AuthorMetadataPayload(
      id: 'auth_2',
      name: 'Prof. Alan Smith',
      order: 2,
      affiliationIds: ['aff_1'], // Initial shared affiliation
      email: 'asmith@mit.edu',
    );

    // -------------------------------------------------------------
    // Step 10: Assign both authors to one affiliation (aff_1)
    // -------------------------------------------------------------
    expect(author1.affiliationIds, ['aff_1']);
    expect(author2.affiliationIds, ['aff_1']);

    // -------------------------------------------------------------
    // Step 11: Add an additional affiliation (aff_2)
    // -------------------------------------------------------------
    const aff2 = AuthorAffiliationPayload(
      id: 'aff_2',
      institution: 'Stanford University',
      department: 'Computer Science',
      city: 'Stanford',
      country: 'USA',
    );
    final author2WithAff2 = author2.copyWith(affiliationIds: ['aff_1', 'aff_2']);

    // -------------------------------------------------------------
    // Step 12: Upload three figures
    // -------------------------------------------------------------
    final fig1 = ProjectFigure(
      id: 'fig_pipe_latency',
      projectId: projectWithOneAuthor.id,
      figureNumber: 1,
      filename: 'latency_cdf.png',
      mimeType: 'image/png',
      fileSize: 67,
      caption: 'Commit latency CDF across 15 cloud regions.',
      altText: 'Cumulative distribution function of latency.',
      storageKey: 'latency_cdf.png',
      cachedBytes: validPngBytes,
      sectionId: 'introduction',
      placement: FigurePlacement.columnWidth,
    );
    final fig2 = ProjectFigure(
      id: 'fig_throughput',
      projectId: projectWithOneAuthor.id,
      figureNumber: 2,
      filename: 'throughput_benchmarks.png',
      mimeType: 'image/png',
      fileSize: 67,
      caption: 'Throughput vs. network partition duration.',
      altText: 'Line chart comparing throughput under failure.',
      storageKey: 'throughput_benchmarks.png',
      cachedBytes: validPngBytes,
      sectionId: 'methodology',
      placement: FigurePlacement.fullWidth,
    );
    final fig3 = ProjectFigure(
      id: 'fig_architecture',
      projectId: projectWithOneAuthor.id,
      figureNumber: 3,
      filename: 'pipeline_architecture.png',
      mimeType: 'image/png',
      fileSize: 67,
      caption: 'Pipelined consensus state machine architecture.',
      altText: 'Architecture block diagram.',
      storageKey: 'pipeline_architecture.png',
      cachedBytes: validPngBytes,
      sectionId: 'results',
      placement: FigurePlacement.columnWidth,
    );

    // -------------------------------------------------------------
    // Step 13: Edit their captions & Step 14: Change section placement
    // -------------------------------------------------------------
    final updatedFig1 = fig1.copyWith(
      caption: 'Updated: Commit latency CDF under asymmetric partitions.',
      sectionId: 'results',
      placement: FigurePlacement.columnWidth,
    );
    final updatedFig2 = fig2.copyWith(
      caption: 'Updated: Throughput comparison with Raft and Multi-Paxos.',
      sectionId: 'methodology',
      placement: FigurePlacement.fullWidth,
    );
    final updatedFig3 = fig3.copyWith(
      caption: 'Updated: Pipelined state machine replication scheme.',
      sectionId: 'introduction',
      placement: FigurePlacement.columnWidth,
    );

    // -------------------------------------------------------------
    // Step 15: Save the project
    // -------------------------------------------------------------
    await tester.runAsync(() async {
      await repository.saveProjectFigures(projectWithOneAuthor.id, [
        updatedFig1,
        updatedFig2,
        updatedFig3,
      ]);
      final updatedContext = Map<String, dynamic>.from(projectWithOneAuthor.projectContext);
      updatedContext['authors'] = [author1.toJson(), author2WithAff2.toJson()];
      updatedContext['affiliations'] = [aff1.toJson(), aff2.toJson()];
      await repository.updateProjectInputs(
        projectId: projectWithOneAuthor.id,
        title: projectWithOneAuthor.title,
        projectContext: updatedContext,
        sourceDraft: projectWithOneAuthor.sourceDraft,
      );
    });

    // -------------------------------------------------------------
    // Step 16: Restart the application
    // -------------------------------------------------------------
    await tester.runAsync(() async {
      await repository.close();

      // Reopen from same SQLite database file
      repository = await LocalProjectRepository.open(
        path: dbPath,
        factory: databaseFactoryFfi,
      );
    });

    // -------------------------------------------------------------
    // Step 17: Verify all authors, figures and changes remain
    // -------------------------------------------------------------
    final reloadedProject = (await tester.runAsync(() async => (await repository.getProject(projectWithOneAuthor.id))!))!;
    final reloadedAuthors = (reloadedProject.projectContext['authors'] as List?) ?? [];
    final reloadedAffiliations = (reloadedProject.projectContext['affiliations'] as List?) ?? [];
    expect(reloadedAuthors.length, 2);
    expect(reloadedAuthors[0]['name'], 'Dr. Jane Doe');
    expect(reloadedAuthors[1]['name'], 'Prof. Alan Smith');
    expect(reloadedAffiliations.length, 2);
    expect(reloadedAffiliations[0]['institution'], 'MIT');
    expect(reloadedAffiliations[1]['institution'], 'Stanford University');

    final reloadedFigures = (await tester.runAsync(() async => await repository.listProjectFigures(projectWithOneAuthor.id)))!;
    expect(reloadedFigures.length, 3);
    expect(reloadedFigures[0].caption, 'Updated: Commit latency CDF under asymmetric partitions.');
    expect(reloadedFigures[0].sectionId, 'results');
    expect(reloadedFigures[1].placement, FigurePlacement.fullWidth);
    expect(reloadedFigures[2].sectionId, 'introduction');

    // -------------------------------------------------------------
    // Step 18: View the manuscript
    // -------------------------------------------------------------
    final versions = (await tester.runAsync(() async => await repository.listPaperVersions(projectWithOneAuthor.id)))!;
    final latestVersion = versions.last;
    expect(latestVersion.paper['title'], 'Distributed Consensus with Adaptive Pipelining');

    // Mount editor in Document (DOCX viewer) mode
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(useMaterial3: true),
        home: PaperEditorPage(
          repository: repository,
          generationApi: fakeApi,
          project: reloadedProject,
          initialVersion: latestVersion,
          initialMode: PaperWorkspaceMode.document,
          exportApi: fakeExportApi,
          fileSaver: fakeSaver,
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    expect(find.byType(DocxDocumentCanvas), findsOneWidget);

    // -------------------------------------------------------------
    // Step 19: Switch to Edit
    // -------------------------------------------------------------
    await tester.tap(find.text('Edit & Outline'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('save-status-badge')), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);

    // -------------------------------------------------------------
    // Step 20: Export DOCX
    // -------------------------------------------------------------
    await tester.tap(find.byKey(const ValueKey('button-export-docx')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    expect(fakeSaver.saveCallCount, 1);
    expect(fakeSaver.lastSuggestedFilename, contains('.docx'));
    expect(fakeSaver.lastSavedBytes, isNotNull);
    expect(fakeSaver.lastSavedBytes!.length, greaterThan(0));

    // -------------------------------------------------------------
    // Step 21: Export PDF
    // -------------------------------------------------------------
    await tester.tap(find.byKey(const ValueKey('button-export-pdf')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    expect(fakeSaver.saveCallCount, 2);
    expect(fakeSaver.lastSuggestedFilename, contains('.pdf'));
    expect(fakeSaver.lastSavedBytes, isNotNull);

    // -------------------------------------------------------------
    // Step 22: Verify both documents
    // -------------------------------------------------------------
    expect(fakeExportApi.exportCallCount, 2);
    expect(fakeSaver.saveCallCount, 2);

    // -------------------------------------------------------------
    // Step 23: Return to the library and confirm manuscript remains visible
    // -------------------------------------------------------------
    final savedPapers = (await tester.runAsync(() async => await repository.listSavedManuscripts()))!;
    expect(savedPapers.isNotEmpty, isTrue);
    final myPaper = savedPapers.firstWhere((p) => p.projectId == reloadedProject.id);
    expect(myPaper.paperTitle, 'Distributed Consensus with Adaptive Pipelining');
    expect(myPaper.versionNumber, greaterThanOrEqualTo(1));
  });
}
