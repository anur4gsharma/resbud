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
  late String dbPath;
  late LocalProjectRepository repository;
  late FakeGenerationApi fakeApi;
  late FakePaperExportApi fakeExportApi;
  late FakeDocxFileSaver fakeSaver;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('resbud-papers-lib-test-');
    dbPath = p.join(tempDirectory.path, 'resbud_projects.sqlite');
    repository = await LocalProjectRepository.open(
      path: dbPath,
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

  Future<void> pumpResbud(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
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
        fileSaver: fakeSaver,
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
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
  }

  group('Saved Papers Library & Project Management System', () {
    testWidgets('1. Empty library: displays empty state when no generated manuscripts exist', (
      tester,
    ) async {
      await tester.runAsync(() => repository.createProject(
        title: 'Project Without Paper',
        projectContext: const {'paper_template': 'ieee_conference'},
        sourceDraft: 'Early brainstorming notes',
      ));

      await pumpResbud(tester);

      await pumpUntilFound(tester, find.text('Project Without Paper'));
      expect(find.text('Project Without Paper'), findsOneWidget);

      final myPapersTab = find.byKey(const ValueKey('tab-my-papers'));
      await switchToTab(tester, myPapersTab);

      await pumpUntilFound(tester, find.text('No saved papers yet.'));
      expect(find.text('0 saved manuscripts'), findsOneWidget);
      expect(find.text('No saved papers yet.'), findsOneWidget);
      expect(
        find.text('Generate a paper from one of your projects to build your library.'),
        findsOneWidget,
      );
      expect(find.text('View Projects'), findsOneWidget);

      await tester.tap(find.text('View Projects'));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 30));
      }

      expect(find.text('Research Projects'), findsOneWidget);
      expect(find.text('1 research initiative containing inputs, figures, and drafts.'), findsOneWidget);
    });

    testWidgets('2. One saved manuscript: displays title, template, citation style, author count, abstract, and project link', (
      tester,
    ) async {
      final project = (await tester.runAsync(() => repository.createProject(
        title: 'Neural Manifolds Study',
        projectContext: const {
          'paper_template': 'ieee_conference',
          'citation_style': 'ieee',
          'authors': [
            {'name': 'Dr. Ada Lovelace', 'affiliation': 'University of Oxford'},
            {'name': 'Charles Babbage', 'affiliation': 'Analytical Engine Lab'},
          ],
        },
      )))!;

      await tester.runAsync(() => repository.savePaperVersion(
        projectId: project.id,
        schemaVersion: 1,
        paper: {
          'title': 'On Latent Geometries and Neural Manifolds',
          'abstract': 'We uncover intrinsic Riemannian curvature in deep feedforward embeddings.',
          'document_template': 'ieee_conference',
          'citation_style': 'ieee',
          'authors': [
            {'name': 'Dr. Ada Lovelace', 'affiliation': 'University of Oxford'},
            {'name': 'Charles Babbage', 'affiliation': 'Analytical Engine Lab'},
          ],
          'sections': [
            {'title': 'Introduction', 'body': 'Neural representations naturally bend.'},
            {'title': 'Differential Forms', 'body': 'Curvature tensor formulation.'},
          ],
          'references': [
            {'id': 'ref1', 'text': 'Riemann, B. (1854). Ueber die Hypothesen.'},
          ],
        },
        origin: PaperVersionOrigin.generation,
      ));

      await pumpResbud(tester);

      await switchToTab(tester, find.byKey(const ValueKey('tab-my-papers')));
      await pumpUntilFound(tester, find.text('On Latent Geometries and Neural Manifolds'));

      expect(find.text('1 saved manuscript'), findsOneWidget);
      expect(find.text('On Latent Geometries and Neural Manifolds'), findsOneWidget);
      expect(find.text('Project: Neural Manifolds Study'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(Card), matching: find.text('IEEE Conference')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(Card), matching: find.text('IEEE')),
        findsOneWidget,
      );
      expect(find.text('v1'), findsOneWidget);
      expect(find.textContaining('2 authors'), findsOneWidget);
      expect(find.textContaining('2 sections'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
      expect(
        find.text('We uncover intrinsic Riemannian curvature in deep feedforward embeddings.'),
        findsOneWidget,
      );

      expect(find.text('Read DOCX'), findsOneWidget);
      expect(find.text('View PDF'), findsOneWidget);
      expect(find.text('Edit Manuscript'), findsOneWidget);
    });

    testWidgets('3. Multiple manuscripts across projects: displays all saved manuscripts with proper project relations', (
      tester,
    ) async {
      final proj1 = (await tester.runAsync(() => repository.createProject(
        title: 'CRISPR Gene Editing Initiative',
        projectContext: const {'paper_template': 'nature', 'citation_style': 'nature'},
      )))!;
      await tester.runAsync(() => repository.savePaperVersion(
        projectId: proj1.id,
        schemaVersion: 1,
        paper: {
          'title': 'High-Fidelity Epigenetic Modification in Mammalian Cells',
          'abstract': 'Targeted transcriptional silencing without double-strand breaks.',
          'document_template': 'nature',
          'citation_style': 'nature',
          'sections': [{'title': 'Abstract', 'body': 'Results summary.'}],
        },
        origin: PaperVersionOrigin.generation,
      ));

      final proj2 = (await tester.runAsync(() => repository.createProject(
        title: 'Distributed Consensus Protocol',
        projectContext: const {'paper_template': 'acm_sigconf', 'citation_style': 'acm'},
      )))!;
      await tester.runAsync(() => repository.savePaperVersion(
        projectId: proj2.id,
        schemaVersion: 1,
        paper: {
          'title': 'Asynchronous Byzantine Agreement with Optimal Resilience',
          'abstract': 'A sub-quadratic consensus algorithm for partially synchronous networks.',
          'document_template': 'acm_sigconf',
          'citation_style': 'acm',
          'sections': [{'title': 'Introduction', 'body': 'Consensus under adversary.'}],
        },
        origin: PaperVersionOrigin.generation,
      ));

      await pumpResbud(tester);

      await switchToTab(tester, find.byKey(const ValueKey('tab-my-papers')));
      await pumpUntilFound(tester, find.text('High-Fidelity Epigenetic Modification in Mammalian Cells'));

      expect(find.text('2 saved manuscripts'), findsOneWidget);

      expect(find.text('High-Fidelity Epigenetic Modification in Mammalian Cells'), findsOneWidget);
      expect(find.text('Project: CRISPR Gene Editing Initiative'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(Card), matching: find.text('Nature')),
        findsAtLeastNWidgets(1),
      );

      expect(find.text('Asynchronous Byzantine Agreement with Optimal Resilience'), findsOneWidget);
      expect(find.text('Project: Distributed Consensus Protocol'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(Card), matching: find.text('ACM Standard')),
        findsOneWidget,
      );
    });

    testWidgets('4. Multiple manuscripts under one project: manages version history and supports version restoration', (
      tester,
    ) async {
      final project = (await tester.runAsync(() => repository.createProject(
        title: 'Quantum Cryptography',
        projectContext: const {'paper_template': 'ieee_conference'},
      )))!;

      // Version 1
      await tester.runAsync(() => repository.savePaperVersion(
        projectId: project.id,
        schemaVersion: 1,
        paper: {
          'title': 'Quantum Cryptography v1: Initial Theoretical Bounds',
          'abstract': 'Preliminary photon entanglement analysis.',
          'document_template': 'ieee_conference',
          'sections': [{'title': 'Section 1', 'body': 'v1 body'}],
        },
        origin: PaperVersionOrigin.generation,
      ));

      // Version 2 (Current)
      await tester.runAsync(() => repository.savePaperVersion(
        projectId: project.id,
        schemaVersion: 1,
        paper: {
          'title': 'Quantum Cryptography v2: Empirical Protocol Verification',
          'abstract': 'Experimental demonstration over 100km fiber optic line.',
          'document_template': 'ieee_conference',
          'sections': [{'title': 'Section 1', 'body': 'v2 body'}],
        },
        origin: PaperVersionOrigin.generation,
      ));

      await pumpResbud(tester);

      await switchToTab(tester, find.byKey(const ValueKey('tab-my-papers')));
      await pumpUntilFound(tester, find.text('Quantum Cryptography v2: Empirical Protocol Verification'));

      expect(find.text('1 saved manuscript'), findsOneWidget);
      expect(find.text('Quantum Cryptography v2: Empirical Protocol Verification'), findsOneWidget);
      expect(find.text('v2'), findsOneWidget);

      // Open popup menu and wait for transition
      final menuButton = find.byTooltip('Manuscript options');
      expect(menuButton, findsOneWidget);
      await tester.tap(menuButton);
      await tester.pumpAndSettle();

      final historyMenuItem = find.text('Version history');
      expect(historyMenuItem, findsOneWidget);
      await tester.tap(historyMenuItem);

      // Await async fetch and bottom sheet rendering
      await pumpUntilFound(tester, find.text('Version History'));
      await tester.pumpAndSettle();

      expect(find.text('Version History'), findsOneWidget);
      expect(find.text('Version 1 '), findsOneWidget);
      expect(find.text('Version 2 (Current)'), findsOneWidget);

      final restoreButton = find.byTooltip('Restore this version');
      expect(restoreButton, findsOneWidget);
      await tester.tap(restoreButton);

      await pumpUntilFound(tester, find.text('Restored version 1 as new snapshot.'));

      final versions = await tester.runAsync(() => repository.listPaperVersions(project.id));
      expect(versions?.length, 3);
      final latest = versions!.last;
      expect(latest.versionNumber, 3);
      expect(latest.origin, PaperVersionOrigin.manualEdit);
      expect(latest.paper['title'], 'Quantum Cryptography v1: Initial Theoretical Bounds');

      final current = await tester.runAsync(() => repository.getCurrentPaperVersion(project.id));
      expect(current?.id, latest.id);
    });

    testWidgets('5. Unfinished drafts: displays unfinished draft badge, continue draft button, and dashboard counter', (
      tester,
    ) async {
      await tester.runAsync(() => repository.createProject(
        title: 'Draft Project Without Paper',
        projectContext: const {'paper_template': 'ieee_conference'},
        sourceDraft: 'Brainstorming inputs.',
      ));

      final project = (await tester.runAsync(() => repository.createProject(
        title: 'Dark Matter Candidates',
        projectContext: const {'paper_template': 'academic_standard'},
      )))!;

      await tester.runAsync(() => repository.savePaperVersion(
        projectId: project.id,
        schemaVersion: 1,
        paper: {
          'title': 'Axion Mass Spectrometry Draft',
          'abstract': 'Work in progress draft analyzing ultralight bosons.',
          'document_template': 'academic_standard',
          'sections': [],
        },
        origin: PaperVersionOrigin.generation,
        metadata: {'completion_status': 'partial', 'missing_sections': ['Results', 'Discussion']},
      ));

      await pumpResbud(tester);

      await pumpUntilFound(tester, find.text('Drafts (1)'));
      expect(find.text('Drafts (1)'), findsOneWidget);

      await switchToTab(tester, find.byKey(const ValueKey('tab-my-papers')));
      await pumpUntilFound(tester, find.text('Axion Mass Spectrometry Draft'));

      expect(find.text('Unfinished draft'), findsOneWidget);
      expect(find.text('Continue Draft'), findsOneWidget);
      expect(find.text('Edit Manuscript'), findsNothing);
    });

    testWidgets('6. Persistence correctness across restart: closing and reopening SQLite preserves all papers', (
      tester,
    ) async {
      final project = (await tester.runAsync(() => repository.createProject(
        title: 'Topological Quantum Memory',
        projectContext: const {
          'paper_template': 'nature',
          'citation_style': 'nature',
          'authors': [{'name': 'Alexei Kitaev', 'affiliation': 'Caltech'}],
        },
      )))!;

      await tester.runAsync(() => repository.savePaperVersion(
        projectId: project.id,
        schemaVersion: 1,
        paper: {
          'title': 'Fault-Tolerant Anyonic Braiding in Toric Code',
          'abstract': 'Non-abelian anyons protect logical qubits from local thermal noise.',
          'document_template': 'nature',
          'citation_style': 'nature',
          'sections': [{'title': 'Hamiltonian', 'body': 'Stabilizer code derivation.'}],
        },
        origin: PaperVersionOrigin.generation,
      ));

      await tester.runAsync(() => repository.close());

      repository = (await tester.runAsync(() => LocalProjectRepository.open(
        path: dbPath,
        factory: databaseFactoryFfi,
      )))!;

      final savedPapers = (await tester.runAsync(() => repository.listSavedManuscripts()))!;
      expect(savedPapers.length, 1);

      final p = savedPapers.first;
      expect(p.paperTitle, 'Fault-Tolerant Anyonic Braiding in Toric Code');
      expect(p.projectTitle, 'Topological Quantum Memory');
      expect(p.paperFormat, 'Nature');
      expect(p.citationStyle, 'Nature');
      expect(p.authorCount, 1);
      expect(p.isUnfinishedDraft, isFalse);
      expect(p.abstractSnippet, 'Non-abelian anyons protect logical qubits from local thermal noise.');

      await pumpResbud(tester);
      await switchToTab(tester, find.byKey(const ValueKey('tab-my-papers')));
      await pumpUntilFound(tester, find.text('Fault-Tolerant Anyonic Braiding in Toric Code'));

      expect(find.text('Fault-Tolerant Anyonic Braiding in Toric Code'), findsOneWidget);
      expect(find.text('Project: Topological Quantum Memory'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(Card), matching: find.text('Nature')),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('7. Rename paper: synchronizes both paper JSON and project title in SQLite', (
      tester,
    ) async {
      final project = (await tester.runAsync(() => repository.createProject(
        title: 'Original Title',
        projectContext: const {'paper_template': 'ieee_conference'},
      )))!;

      await tester.runAsync(() => repository.savePaperVersion(
        projectId: project.id,
        schemaVersion: 1,
        paper: {
          'title': 'Original Paper Title',
          'abstract': 'Abstract here.',
          'document_template': 'ieee_conference',
          'sections': [{'title': 'Sec 1', 'body': 'Body'}],
        },
        origin: PaperVersionOrigin.generation,
      ));

      await pumpResbud(tester);

      await switchToTab(tester, find.byKey(const ValueKey('tab-my-papers')));
      await pumpUntilFound(tester, find.text('Original Paper Title'));

      expect(find.text('Original Paper Title'), findsOneWidget);

      final menuButton = find.byTooltip('Manuscript options');
      await tester.tap(menuButton);
      await tester.pumpAndSettle();

      final renameOption = find.text('Rename paper');
      await tester.tap(renameOption);
      await pumpUntilFound(tester, find.text('Rename project'));

      expect(find.text('Rename project'), findsOneWidget);
      final textField = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
      await tester.enterText(textField, 'Neural Architecture Search via Evolution');
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));

      await pumpUntilFound(tester, find.text('Neural Architecture Search via Evolution'));
      expect(find.text('Neural Architecture Search via Evolution'), findsOneWidget);
      expect(find.text('Original Paper Title'), findsNothing);

      final currentVer = await tester.runAsync(() => repository.getCurrentPaperVersion(project.id));
      expect(currentVer?.paper['title'], 'Neural Architecture Search via Evolution');

      final updatedProject = await tester.runAsync(() => repository.getProject(project.id));
      expect(updatedProject?.title, 'Neural Architecture Search via Evolution');
    });

    testWidgets('8. Duplicate manuscript: deep copies project, figures, and draft into independent project', (
      tester,
    ) async {
      final project = (await tester.runAsync(() => repository.createProject(
        title: 'Graph Neural Networks',
        projectContext: const {
          'paper_template': 'ieee_conference',
          'domain': 'Deep Learning',
        },
        sourceDraft: 'Source draft notes on message passing.',
      )))!;

      await tester.runAsync(() => repository.savePaperVersion(
        projectId: project.id,
        schemaVersion: 1,
        paper: {
          'title': 'Message Passing on Non-Euclidean Graphs',
          'abstract': 'Spatial convolutions over irregular topologies.',
          'document_template': 'ieee_conference',
          'sections': [{'title': 'Sec 1', 'body': 'Body'}],
        },
        origin: PaperVersionOrigin.generation,
      ));

      await pumpResbud(tester);

      await switchToTab(tester, find.byKey(const ValueKey('tab-my-papers')));
      await pumpUntilFound(tester, find.text('Message Passing on Non-Euclidean Graphs'));

      final menuButton = find.byTooltip('Manuscript options');
      await tester.tap(menuButton);
      await tester.pumpAndSettle();

      final duplicateOption = find.text('Duplicate');
      await tester.tap(duplicateOption);

      await pumpUntilFound(
        tester,
        find.textContaining('Duplicated manuscript into "Message Passing on Non-Euclidean Graphs (Copy)"'),
      );

      final allProjects = await tester.runAsync(() => repository.listProjects());
      expect(allProjects?.length, 2);

      final duplicatedProject = allProjects!.firstWhere(
        (p) => p.title == 'Message Passing on Non-Euclidean Graphs (Copy)',
      );
      expect(duplicatedProject.sourceDraft, 'Source draft notes on message passing.');
      expect(duplicatedProject.projectContext['domain'], 'Deep Learning');

      final duplicatedPaper = await tester.runAsync(
        () => repository.getCurrentPaperVersion(duplicatedProject.id),
      );
      expect(duplicatedPaper?.paper['title'], 'Message Passing on Non-Euclidean Graphs (Copy)');
      expect(duplicatedPaper?.metadata?['duplicated_from_project_id'], project.id);
    });

    testWidgets('9. Delete paper: confirms deletion and removes paper while preserving parent project context', (
      tester,
    ) async {
      final project = (await tester.runAsync(() => repository.createProject(
        title: 'Protein Folding Dynamics',
        projectContext: const {'paper_template': 'nature'},
        sourceDraft: 'AlphaFold molecular dynamics notes.',
      )))!;

      await tester.runAsync(() => repository.savePaperVersion(
        projectId: project.id,
        schemaVersion: 1,
        paper: {
          'title': 'Ab Initio De Novo Protein Design',
          'abstract': 'Generative diffusion models for tertiary backbone generation.',
          'document_template': 'nature',
          'sections': [{'title': 'Sec 1', 'body': 'Body'}],
        },
        origin: PaperVersionOrigin.generation,
      ));

      await pumpResbud(tester);

      await switchToTab(tester, find.byKey(const ValueKey('tab-my-papers')));
      await pumpUntilFound(tester, find.text('Ab Initio De Novo Protein Design'));

      expect(find.text('1 saved manuscript'), findsOneWidget);

      final menuButton = find.byTooltip('Manuscript options');
      await tester.tap(menuButton);
      await tester.pumpAndSettle();

      final deleteOption = find.text('Delete paper');
      await tester.tap(deleteOption);

      await pumpUntilFound(tester, find.text('Delete this manuscript?'));
      expect(
        find.textContaining('This permanently deletes all saved versions of this paper.'),
        findsOneWidget,
      );

      final deleteConfirmButton = find.widgetWithText(FilledButton, 'Delete');
      await tester.tap(deleteConfirmButton);
      await tester.pumpAndSettle();

      await pumpUntilFound(tester, find.text('Manuscript deleted.'));
      await pumpUntilFound(tester, find.text('0 saved manuscripts'));

      expect(find.text('0 saved manuscripts'), findsOneWidget);
      expect(find.text('No saved papers yet.'), findsOneWidget);

      final remainingVersions = await tester.runAsync(
        () => repository.listPaperVersions(project.id),
      );
      expect(remainingVersions?.isEmpty, isTrue);

      final preservedProject = await tester.runAsync(
        () => repository.getProject(project.id),
      );
      expect(preservedProject, isNotNull);
      expect(preservedProject?.title, 'Protein Folding Dynamics');
      expect(preservedProject?.sourceDraft, 'AlphaFold molecular dynamics notes.');
      expect(preservedProject?.currentPaperVersionId, isNull);
    });

    testWidgets('10. Search and format filtering: filters manuscripts by keyword and template format', (
      tester,
    ) async {
      final p1 = (await tester.runAsync(() => repository.createProject(
        title: 'Robotics Project',
        projectContext: const {'paper_template': 'ieee_conference'},
      )))!;
      await tester.runAsync(() => repository.savePaperVersion(
        projectId: p1.id,
        schemaVersion: 1,
        paper: {
          'title': 'Autonomous Navigation in Dense Fog',
          'abstract': 'FMCW radar point cloud clustering for collision avoidance.',
          'document_template': 'ieee_conference',
          'sections': [{'title': 'Sec 1', 'body': 'Body'}],
        },
        origin: PaperVersionOrigin.generation,
      ));

      final p2 = (await tester.runAsync(() => repository.createProject(
        title: 'Genomics Project',
        projectContext: const {'paper_template': 'nature'},
      )))!;
      await tester.runAsync(() => repository.savePaperVersion(
        projectId: p2.id,
        schemaVersion: 1,
        paper: {
          'title': 'Metagenomic Profiling of Deep Sea Vents',
          'abstract': 'Extremophile enzyme identification via long-read sequencing.',
          'document_template': 'nature',
          'sections': [{'title': 'Sec 1', 'body': 'Body'}],
        },
        origin: PaperVersionOrigin.generation,
      ));

      final p3 = (await tester.runAsync(() => repository.createProject(
        title: 'Distributed Systems Project',
        projectContext: const {'paper_template': 'acm_sigconf'},
      )))!;
      await tester.runAsync(() => repository.savePaperVersion(
        projectId: p3.id,
        schemaVersion: 1,
        paper: {
          'title': 'Zero-Knowledge Proofs in Sharded Blockchains',
          'abstract': 'Succinct non-interactive arguments of knowledge for state transitions.',
          'document_template': 'acm_sigconf',
          'sections': [{'title': 'Sec 1', 'body': 'Body'}],
        },
        origin: PaperVersionOrigin.generation,
      ));

      await pumpResbud(tester);

      await switchToTab(tester, find.byKey(const ValueKey('tab-my-papers')));
      await pumpUntilFound(tester, find.text('Autonomous Navigation in Dense Fog'));

      expect(find.text('3 saved manuscripts'), findsOneWidget);
      expect(find.text('Autonomous Navigation in Dense Fog'), findsOneWidget);
      expect(find.text('Metagenomic Profiling of Deep Sea Vents'), findsOneWidget);
      expect(find.text('Zero-Knowledge Proofs in Sharded Blockchains'), findsOneWidget);

      // 1. Search filter by title
      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, 'Fog');
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 30));
      }

      expect(find.text('Autonomous Navigation in Dense Fog'), findsOneWidget);
      expect(find.text('Metagenomic Profiling of Deep Sea Vents'), findsNothing);
      expect(find.text('Zero-Knowledge Proofs in Sharded Blockchains'), findsNothing);

      // 2. Clear search via suffix icon
      final clearIcon = find.byIcon(Icons.clear);
      expect(clearIcon, findsOneWidget);
      await tester.tap(clearIcon);
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 30));
      }

      expect(find.text('3 saved manuscripts'), findsOneWidget);

      // 3. Filter by Nature format chip
      final natureChip = find.widgetWithText(FilterChip, 'Nature');
      await tester.tap(natureChip);
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 30));
      }

      expect(find.text('1 saved manuscript'), findsOneWidget);
      expect(find.text('Metagenomic Profiling of Deep Sea Vents'), findsOneWidget);
      expect(find.text('Autonomous Navigation in Dense Fog'), findsNothing);
      expect(find.text('Zero-Knowledge Proofs in Sharded Blockchains'), findsNothing);

      // 4. Reset to 'All'
      final allChip = find.widgetWithText(FilterChip, 'All');
      await tester.tap(allChip);
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 30));
      }

      expect(find.text('3 saved manuscripts'), findsOneWidget);
    });
  });
}
