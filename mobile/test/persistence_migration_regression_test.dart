import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:resbud_mobile/data/local_project_repository.dart';
import 'package:resbud_mobile/data/project_figure.dart';
import 'package:resbud_mobile/features/docx_viewer/docx_document_canvas.dart';
import 'package:resbud_mobile/features/paper_editor/paper_editor_page.dart';

import 'helpers/fake_export_api.dart';
import 'helpers/fake_generation_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tempDirectory;
  late String dbPath;

  final samplePngBytes = Uint8List.fromList([
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
    tempDirectory = await Directory.systemTemp.createTemp('resbud_migration_test_');
    dbPath = p.join(tempDirectory.path, 'legacy_resbud.sqlite');
  });

  tearDown(() async {
    if (tempDirectory.existsSync()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  Future<void> seedLegacySchemaV1Database(String path) async {
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE projects (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              project_context_json TEXT,
              source_draft TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              current_paper_version_id TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE paper_versions (
              id TEXT PRIMARY KEY,
              project_id TEXT NOT NULL,
              version_number INTEGER NOT NULL,
              schema_version INTEGER NOT NULL,
              paper_json TEXT NOT NULL,
              created_at TEXT NOT NULL,
              origin TEXT NOT NULL,
              FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
            )
          ''');
          await db.execute('''
            CREATE TABLE auth_session (
              id INTEGER PRIMARY KEY CHECK (id = 1),
              session_token TEXT NOT NULL,
              session_data_json TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE database_meta (
              id INTEGER PRIMARY KEY CHECK (id = 1),
              schema_version INTEGER NOT NULL
            )
          ''');
          await db.insert('database_meta', {
            'id': 1,
            'schema_version': 1,
          });
        },
      ),
    );

    // Seed Project 1: Legacy IEEE Project with generated paper
    final legacyPaperV1 = {
      'schema_version': 1,
      'review_warnings': <dynamic>[],
      'title': 'Legacy Deep Metric Learning for Academic Retrieval',
      'abstract': 'An empirical evaluation of triplet loss representations.',
      'document_template': 'ieee_conference',
      'keywords': ['metric learning', 'embeddings'],
      'sections': [
        {
          'id': 'introduction',
          'heading': 'Introduction',
          'content': 'Deep metric learning optimizes relative semantic distance.',
          'state': 'draft',
        },
        {
          'id': 'methodology',
          'heading': 'Methodology',
          'content': r'We formulate Euclidean margin constraints: $$d(x_a, x_p) + \alpha \le d(x_a, x_n)$$',
          'state': 'draft',
        },
      ],
      'references': [
        {'id': 'ref_1', 'text': 'Schroff, F. et al. (2015). FaceNet: A unified embedding.'},
      ],
    };

    await db.insert('projects', {
      'id': 'proj_legacy_001',
      'title': 'Legacy Deep Metric Learning',
      'project_context_json': jsonEncode({
        'title': 'Legacy Deep Metric Learning',
        'authors': [
          {'name': 'Original Author A', 'affiliation': 'Stanford University'}
        ],
        'preferences': {
          'document_template': 'ieee_conference',
          'citation_style': 'user_supplied',
          'target_word_count': 2500,
        },
      }),
      'source_draft': 'Draft notes describing contrastive margin embeddings.',
      'created_at': '2025-10-01T10:00:00Z',
      'updated_at': '2025-10-01T12:00:00Z',
      'current_paper_version_id': 'ver_legacy_001',
    });

    await db.insert('paper_versions', {
      'id': 'ver_legacy_001',
      'project_id': 'proj_legacy_001',
      'version_number': 1,
      'schema_version': 1,
      'paper_json': jsonEncode(legacyPaperV1),
      'created_at': '2025-10-01T12:00:00Z',
      'origin': 'generation',
    });

    // Seed Project 2: Multi-version paper with v1 (generation) and v2 (manual_edit)
    final multiVersionPaperV1 = {
      'schema_version': 1,
      'review_warnings': <dynamic>[],
      'title': 'Asynchronous Byzantine Paxos v1',
      'abstract': 'Abstract v1 initial draft.',
      'document_template': 'ieee_conference',
      'keywords': ['consensus'],
      'sections': [
        {'id': 'introduction', 'heading': 'Introduction', 'content': 'Initial consensus draft.'},
      ],
      'references': <Map<String, dynamic>>[],
    };
    final multiVersionPaperV2 = {
      'schema_version': 1,
      'review_warnings': <dynamic>[],
      'title': 'Asynchronous Byzantine Paxos v2 Revised',
      'abstract': 'Abstract v2 revised with proof of liveness.',
      'document_template': 'ieee_conference',
      'keywords': ['consensus', 'liveness'],
      'sections': [
        {'id': 'introduction', 'heading': 'Introduction', 'content': 'Revised consensus draft with 3f+1 quorum.'},
      ],
      'references': <Map<String, dynamic>>[],
    };

    await db.insert('projects', {
      'id': 'proj_multi_ver_002',
      'title': 'Asynchronous Byzantine Paxos',
      'project_context_json': jsonEncode({
        'title': 'Asynchronous Byzantine Paxos',
        'preferences': {'document_template': 'ieee_conference'},
      }),
      'source_draft': 'Notes on quorum intersection.',
      'created_at': '2025-11-01T08:00:00Z',
      'updated_at': '2025-11-02T15:00:00Z',
      'current_paper_version_id': 'ver_multi_002',
    });

    await db.insert('paper_versions', {
      'id': 'ver_multi_001',
      'project_id': 'proj_multi_ver_002',
      'version_number': 1,
      'schema_version': 1,
      'paper_json': jsonEncode(multiVersionPaperV1),
      'created_at': '2025-11-01T09:00:00Z',
      'origin': 'generation',
    });

    await db.insert('paper_versions', {
      'id': 'ver_multi_002',
      'project_id': 'proj_multi_ver_002',
      'version_number': 2,
      'schema_version': 1,
      'paper_json': jsonEncode(multiVersionPaperV2),
      'created_at': '2025-11-02T15:00:00Z',
      'origin': 'manual_edit',
    });

    // Seed Project 3: Unfinished draft without any paper generated
    await db.insert('projects', {
      'id': 'proj_unfinished_003',
      'title': 'Unfinished Quantum Error Correction',
      'project_context_json': jsonEncode({
        'title': 'Unfinished Quantum Error Correction',
        'research_question': 'Can surface codes achieve fault tolerance below 10^-3 physical error rate?',
      }),
      'source_draft': 'Preliminary syndrome decoding thoughts.',
      'created_at': '2025-11-10T14:00:00Z',
      'updated_at': '2025-11-10T14:30:00Z',
      'current_paper_version_id': null,
    });

    await db.close();
  }

  test('Database migration from Schema v1 to v3 executes cleanly and preserves all data', () async {
    // 1. Seed legacy schema v1 database
    await seedLegacySchemaV1Database(dbPath);

    // 2. Open via LocalProjectRepository (triggers onUpgrade to v3)
    final repository = await LocalProjectRepository.open(
      path: dbPath,
      factory: databaseFactoryFfi,
    );

    try {
      // Verify schema version is now 3
      final metaRows = await repository.database.query('database_meta');
      expect(metaRows.first['schema_version'], 3);

      // Verify all 3 projects exist
      final projects = await repository.listProjects();
      expect(projects.length, 3);
      final p1 = projects.firstWhere((p) => p.id == 'proj_legacy_001');
      final p2 = projects.firstWhere((p) => p.id == 'proj_multi_ver_002');
      final p3 = projects.firstWhere((p) => p.id == 'proj_unfinished_003');

      // Verify original_draft column migration (v1 -> v2 migration)
      expect(p1.originalDraft, 'Draft notes describing contrastive margin embeddings.');
      expect(p2.originalDraft, 'Notes on quorum intersection.');
      expect(p3.originalDraft, 'Preliminary syndrome decoding thoughts.');

      // Verify listSavedManuscripts returns both legacy generated papers
      final manuscripts = await repository.listSavedManuscripts();
      expect(manuscripts.length, 2);
      expect(manuscripts.any((m) => m.paperTitle == 'Legacy Deep Metric Learning for Academic Retrieval'), isTrue);
      expect(manuscripts.any((m) => m.paperTitle == 'Asynchronous Byzantine Paxos v2 Revised'), isTrue);

      // Verify multi-version paper preservation
      final p2Versions = await repository.listPaperVersions(p2.id);
      expect(p2Versions.length, 2);
      expect(p2Versions[0].versionNumber, 1);
      expect(p2Versions[0].origin, PaperVersionOrigin.generation);
      expect(p2Versions[1].versionNumber, 2);
      expect(p2Versions[1].origin, PaperVersionOrigin.manualEdit);

      // Verify unfinished projects query correctly identifies Project 3
      final unfinished = await repository.listUnfinishedProjects();
      expect(unfinished.length, 1);
      expect(unfinished.first.id, 'proj_unfinished_003');

      // Verify new figures and blobs tables exist and accept records (v2 -> v3 migration)
      final fig = ProjectFigure(
        id: 'fig_migrated_01',
        projectId: p1.id,
        figureNumber: 1,
        filename: 'loss_curve.png',
        mimeType: 'image/png',
        fileSize: samplePngBytes.length,
        caption: 'Loss convergence curve.',
        storageKey: 'loss_curve.png',
        cachedBytes: samplePngBytes,
      );
      await repository.saveProjectFigures(p1.id, [fig]);

      final figures = await repository.listProjectFigures(p1.id);
      expect(figures.length, 1);
      expect(figures.first.caption, 'Loss convergence curve.');

      // Verify saving a new paper version on legacy project does not delete prior versions
      final newV2 = await repository.savePaperVersion(
        projectId: p1.id,
        schemaVersion: 1,
        paper: {
          ...p1.projectContext,
          'title': 'Legacy Deep Metric Learning v2',
          'sections': [
            {'id': 'introduction', 'heading': 'Introduction', 'content': 'Updated intro.'}
          ],
        },
        origin: PaperVersionOrigin.manualEdit,
      );
      expect(newV2.versionNumber, 2);

      final p1VersionsAfter = await repository.listPaperVersions(p1.id);
      expect(p1VersionsAfter.length, 2);
      expect(p1VersionsAfter[0].id, 'ver_legacy_001'); // Original v1 preserved!
    } finally {
      await repository.close();
    }
  });

  testWidgets('Legacy manuscripts open in PaperEditorPage without exceptions', (tester) async {
    late LocalProjectRepository repository;
    late LocalProject project;
    late PaperVersion version;

    await tester.runAsync(() async {
      await seedLegacySchemaV1Database(dbPath);
      repository = await LocalProjectRepository.open(
        path: dbPath,
        factory: databaseFactoryFfi,
      );
      project = (await repository.getProject('proj_legacy_001'))!;
      version = (await repository.getCurrentPaperVersion('proj_legacy_001'))!;
    });
    addTearDown(() async {
      await tester.runAsync(() => repository.close());
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(useMaterial3: true),
        home: PaperEditorPage(
          repository: repository,
          generationApi: FakeGenerationApi(),
          project: project,
          initialVersion: version,
          initialMode: PaperWorkspaceMode.document,
          exportApi: FakePaperExportApi(),
          fileSaver: FakeDocxFileSaver(),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    // Verify document canvas renders legacy paper
    expect(find.byType(DocxDocumentCanvas), findsOneWidget);
    expect(find.textContaining('Legacy Deep Metric Learning'), findsAtLeastNWidgets(1));

    // Switch to Edit mode
    await tester.tap(find.text('Edit & Outline'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('save-status-badge')), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
  });
}
