import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:resbud_mobile/data/local_project_repository.dart';
import 'package:resbud_mobile/features/docx_viewer/docx_document_canvas.dart';
import 'package:resbud_mobile/features/docx_viewer/docx_viewer.dart';
import 'package:resbud_mobile/features/generation/generation_models.dart';
import 'package:resbud_mobile/features/paper_editor/paper_editor_page.dart';

import 'helpers/fake_export_api.dart';
import 'helpers/fake_generation_api.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory tempDirectory;
  late LocalProjectRepository repository;
  late FakeGenerationApi fakeApi;
  late FakePaperExportApi fakeExportApi;
  late FakeDocxFileSaver fakeSaver;
  late LocalProject testProject;
  late PaperVersion version1;
  late PaperVersion version2;

  const samplePaper = PaperDraftPayload(
    schemaVersion: 1,
    title: 'Equivariant Neural Decoders for Surface Codes',
    abstractText:
        'Quantum error correction requires low-latency decoding of syndrome measurements. '
        'We present an equivariant neural graph decoder that preserves symmetry groups.',
    keywords: const ['quantum', 'decoders', 'surface codes'],
    sections: const [
      PaperSectionPayload(
        id: 'intro',
        heading: 'Introduction',
        content:
            'Topological surface codes represent a leading paradigm for fault-tolerant quantum computing.\n\n'
            'Modern decoders must operate within microsecond coherence times.',
        state: 'draft',
      ),
      PaperSectionPayload(
        id: 'methodology',
        heading: 'Decoder Architecture & Symmetry',
        content:
            'We formulate the syndrome decoding task on a 2D square lattice graph.\n\n'
            '| Parameter | Value | Description |\n'
            '| --- | --- | --- |\n'
            '| Code Distance d | 5 | Minimum weight Pauli error |\n'
            '| Physical Error Rate | 0.001 | Depolarizing noise model |\n'
            '| Latency Target | 1.2 us | FPGA execution budget |\n\n'
            'Key architectural properties:\n'
            '- Translation equivariance across the lattice\n'
            '- Reflection symmetry preservation\n'
            '- Sub-microsecond inference throughput',
        state: 'draft',
      ),
      PaperSectionPayload(
        id: 'results',
        heading: 'Experimental Results',
        content:
            'Simulations across 10 million Monte Carlo rounds show threshold improvement over standard MWPM decoders.',
        state: 'draft',
      ),
    ],
    references: const [
      ReferencePayload(
        id: 'ref-fowler-2012',
        text: 'Fowler, A. G. et al. (2012). Surface codes: Towards practical large-scale quantum computation. PRA, 86(3), 032324.',
      ),
      ReferencePayload(
        id: 'ref-dennis-2002',
        text: 'Dennis, E. et al. (2002). Topological quantum memory. J. Math. Phys., 43(9), 4452-4505.',
      ),
    ],
    reviewWarnings: const [],
  );

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('resbud-viewer-test-');
    repository = await LocalProjectRepository.open(
      path: p.join(tempDirectory.path, 'viewer_test.sqlite'),
      factory: databaseFactoryFfi,
    );
    fakeApi = FakeGenerationApi();
    fakeExportApi = FakePaperExportApi();
    fakeSaver = FakeDocxFileSaver();

    testProject = await repository.createProject(
      title: 'Quantum Decoder Project',
      projectContext: {'creation_mode': 'document'},
    );

    version1 = await repository.savePaperVersion(
      projectId: testProject.id,
      schemaVersion: 1,
      paper: samplePaper.toJson(),
      origin: PaperVersionOrigin.generation,
      metadata: {'generation_id': 'gen-001'},
    );

    final modifiedPaper = samplePaper.copyWith(
      abstractText: 'Refined abstract for Version 2 with updated threshold statistics.',
    );

    version2 = await repository.savePaperVersion(
      projectId: testProject.id,
      schemaVersion: 1,
      paper: modifiedPaper.toJson(),
      origin: PaperVersionOrigin.manualEdit,
      metadata: {'source_version_number': 1},
    );
  });

  tearDown(() async {
    await repository.close();
    await tempDirectory.delete(recursive: true);
  });

  group('Native DOCX Viewer Core Functionality', () {
    testWidgets('renders paginated document canvas with title, abstract, sections, tables, and references', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocxViewer(
              paper: samplePaper,
              exportApi: fakeExportApi,
              fileSaver: fakeSaver,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Title & Abstract
      expect(find.text('Equivariant Neural Decoders for Surface Codes'), findsWidgets);
      expect(find.text('ABSTRACT'), findsOneWidget);
      expect(
        find.textContaining('Quantum error correction requires low-latency decoding'),
        findsOneWidget,
      );

      // Section Headings & Content
      expect(find.text('1. Introduction'), findsOneWidget);
      expect(find.text('2. Decoder Architecture & Symmetry'), findsOneWidget);

      // Markdown Table parsed into Table widget
      expect(find.byType(Table), findsOneWidget);
      expect(find.text('Code Distance d'), findsOneWidget);
      expect(find.text('Physical Error Rate'), findsOneWidget);

      // Bullet lists
      expect(find.textContaining('Translation equivariance across the lattice'), findsOneWidget);

      // References
      expect(find.text('REFERENCES'), findsOneWidget);
      expect(find.textContaining('Fowler, A. G.'), findsOneWidget);

      // Page footer & indicator
      expect(find.textContaining('Research Buddy Academic Manuscript'), findsOneWidget);
      expect(find.byKey(const ValueKey('docx-page-indicator')), findsOneWidget);
    });

    testWidgets('zoom in, zoom out, fit to width, and reset zoom adjust scale smoothly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocxViewer(
              paper: samplePaper,
              exportApi: fakeExportApi,
              fileSaver: fakeSaver,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Default zoom is 100%
      expect(find.text('100%'), findsOneWidget);

      // Zoom in -> 110%
      await tester.tap(find.byKey(const ValueKey('button-docx-zoom-in')));
      await tester.pumpAndSettle();
      expect(find.text('110%'), findsOneWidget);

      // Zoom out -> 100% -> 90%
      await tester.tap(find.byKey(const ValueKey('button-docx-zoom-out')));
      await tester.pumpAndSettle();
      expect(find.text('100%'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('button-docx-zoom-out')));
      await tester.pumpAndSettle();
      expect(find.text('90%'), findsOneWidget);

      // Fit to width -> 115%
      await tester.tap(find.byKey(const ValueKey('button-docx-fit-width')));
      await tester.pumpAndSettle();
      expect(find.text('115%'), findsOneWidget);

      // Tap percentage indicator resets to 100%
      await tester.tap(find.text('115%'));
      await tester.pumpAndSettle();
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('download button in viewer triggers export and saves DOCX document', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocxViewer(
              paper: samplePaper,
              exportApi: fakeExportApi,
              fileSaver: fakeSaver,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('button-docx-viewer-download')));
      await tester.pumpAndSettle();

      expect(fakeSaver.saveCallCount, 1);
      expect(fakeSaver.lastSuggestedFilename, contains('.docx'));
      expect(find.textContaining('Downloaded:'), findsOneWidget);
    });

    testWidgets('fullscreen toggle toggles state and icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocxViewer(
              paper: samplePaper,
              exportApi: fakeExportApi,
              fileSaver: fakeSaver,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final fsBtn = find.byKey(const ValueKey('button-docx-viewer-fullscreen'));
      expect(find.byIcon(Icons.fullscreen), findsOneWidget);

      await tester.tap(fsBtn);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);

      await tester.tap(fsBtn);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.fullscreen), findsOneWidget);
    });
  });

  group('Version Management & In-App Version Switching', () {
    testWidgets('opens paper in native document viewer by default and shows compact version selector', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PaperEditorPage(
            repository: repository,
            generationApi: fakeApi,
            project: testProject,
            initialVersion: version2,
            initialMode: PaperWorkspaceMode.document,
            exportApi: fakeExportApi,
            fileSaver: fakeSaver,
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      // Compact version selector renders current version v2
      expect(find.byKey(const ValueKey('compact-version-selector')), findsWidgets);
      expect(find.textContaining('v2'), findsWidgets);

      // Default mode is Read (DOCX)
      expect(find.byKey(const ValueKey('docx-viewer-toolbar')), findsOneWidget);
      expect(find.text('Equivariant Neural Decoders for Surface Codes'), findsWidgets);
      expect(find.textContaining('Refined abstract for Version 2'), findsOneWidget);
    });

    testWidgets('seamlessly switches versions without navigating away from the document viewer', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PaperEditorPage(
            repository: repository,
            generationApi: fakeApi,
            project: testProject,
            initialVersion: version2,
            initialMode: PaperWorkspaceMode.document,
            exportApi: fakeExportApi,
            fileSaver: fakeSaver,
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      // Currently showing version 2
      expect(find.textContaining('Refined abstract for Version 2'), findsOneWidget);

      // Tap compact version selector in app bar
      await tester.tap(find.byKey(const ValueKey('compact-version-selector')).first);
      await tester.pumpAndSettle();

      // Popover shows Version 1 and Version 2
      expect(find.byKey(const ValueKey('version-selector-item-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('version-selector-item-2')), findsOneWidget);

      // Select Version 1
      await tester.tap(find.byKey(const ValueKey('version-selector-item-1')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      // Document updates to Version 1 content immediately without navigating away!
      expect(find.textContaining('Quantum error correction requires low-latency decoding'), findsOneWidget);
      expect(find.text('Viewing Version 1'), findsOneWidget);

      // Version selector label now shows v1
      expect(find.textContaining('v1'), findsWidgets);

      // Switch back to Version 2
      await tester.tap(find.byKey(const ValueKey('compact-version-selector')).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('version-selector-item-2')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      expect(find.textContaining('Refined abstract for Version 2'), findsOneWidget);
      expect(find.text('Viewing Version 2'), findsOneWidget);
    });

    testWidgets('switching mode between Read (DOCX) and Edit & Outline preserves state and inputs', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PaperEditorPage(
            repository: repository,
            generationApi: fakeApi,
            project: testProject,
            initialVersion: version1,
            initialMode: PaperWorkspaceMode.document,
            exportApi: fakeExportApi,
            fileSaver: fakeSaver,
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      // Starts in Read (DOCX)
      expect(find.byType(DocxDocumentCanvas), findsOneWidget);

      // Switch to Edit & Outline
      await tester.tap(find.text('Edit & Outline'));
      await tester.pumpAndSettle();

      // Editable inputs are accessible
      expect(find.byKey(const ValueKey('paper-title-input')), findsOneWidget);
      expect(find.byKey(const ValueKey('paper-abstract-input')), findsOneWidget);

      // Switch back to Read (DOCX)
      await tester.tap(find.text('Read (DOCX)'));
      await tester.pumpAndSettle();

      expect(find.byType(DocxDocumentCanvas), findsOneWidget);
    });

    testWidgets('switching version with unsaved edits prompts confirmation dialog', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PaperEditorPage(
            repository: repository,
            generationApi: fakeApi,
            project: testProject,
            initialVersion: version2,
            initialMode: PaperWorkspaceMode.editor,
            exportApi: fakeExportApi,
            fileSaver: fakeSaver,
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      // Modify abstract to make editor dirty
      final abstractField = find.byKey(const ValueKey('paper-abstract-input'));
      await tester.enterText(abstractField, 'Unsaved modification that needs confirmation');
      await tester.pumpAndSettle();

      expect(find.text('Unsaved'), findsOneWidget);

      // Attempt to switch to version 1
      await tester.tap(find.byKey(const ValueKey('compact-version-selector')).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('version-selector-item-1')));
      await tester.pumpAndSettle();

      // Unsaved edits warning dialog is displayed
      expect(find.text('Unsaved edits'), findsOneWidget);
      expect(find.textContaining('Switching to Version 1 will discard unsaved edits'), findsOneWidget);

      // Discard edits and proceed
      await tester.tap(find.text('Discard edits'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      // Successfully switched to Version 1
      expect(find.text('Viewing Version 1'), findsOneWidget);
    });
  });
}
