import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:resbud_mobile/data/local_project_repository.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory tempDirectory;
  late LocalProjectRepository repository;
  late String databasePath;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'resbud-storage-test-',
    );
    databasePath = p.join(tempDirectory.path, 'projects.sqlite');
    repository = await LocalProjectRepository.open(
      path: databasePath,
      factory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await repository.close();
    await tempDirectory.delete(recursive: true);
  });

  test(
    'fresh schema has the current version and an empty project list',
    () async {
      expect(await repository.listProjects(), isEmpty);
      final database = await databaseFactoryFfi.openDatabase(databasePath);
      expect(await database.getVersion(), currentDatabaseSchemaVersion);
      final meta = await database.query('database_meta');
      expect(meta.single['schema_version'], currentDatabaseSchemaVersion);
    },
  );

  test(
    'project create, update, delete and serialized inputs round trip',
    () async {
      final project = await repository.createProject(
        title: '  Field notes  ',
        projectContext: {
          'research_field': 'Ecology',
          'objectives': ['Map habitats', 'Compare seasons'],
        },
        sourceDraft: 'Original source\nwith line breaks.',
      );

      expect(project.title, 'Field notes');
      expect(project.originalDraft, 'Original source\nwith line breaks.');
      expect(project.sourceDraft, project.originalDraft);
      expect(project.projectContext['objectives'], [
        'Map habitats',
        'Compare seasons',
      ]);
      expect(project.createdAt.isUtc, isTrue);
      expect(project.currentPaperVersionId, isNull);

      final updated = await repository.updateProjectInputs(
        projectId: project.id,
        title: 'Updated field notes',
        projectContext: const {'research_field': 'Conservation'},
        sourceDraft: 'Edited current source.',
      );
      expect(updated.title, 'Updated field notes');
      expect(updated.sourceDraft, 'Edited current source.');
      expect(updated.originalDraft, 'Original source\nwith line breaks.');

      expect((await repository.getProject(project.id))!.title, updated.title);
      expect((await repository.listProjects()).single.id, updated.id);
      await repository.deleteProject(project.id);
      expect(await repository.getProject(project.id), isNull);
      expect(await repository.listProjects(), isEmpty);
    },
  );

  test(
    'paper versions are immutable snapshots ordered per project with metadata',
    () async {
      final project = await repository.createProject(
        title: 'Versioned paper',
        projectContext: const {'question': 'How does it change?'},
      );
      final firstPaper = <String, Object?>{
        'schema_version': 1,
        'title': 'Version one',
        'sections': [
          {'id': 'intro', 'content': 'A stable claim.'},
        ],
        'references': [
          {'id': 'ref_1', 'text': 'Source (2025).'},
        ],
        'review_warnings': [
          {'code': 'GENERAL_REVIEW', 'message': 'Verify claims.'},
        ],
      };
      final first = await repository.savePaperVersion(
        projectId: project.id,
        schemaVersion: 1,
        paper: firstPaper,
        origin: PaperVersionOrigin.generation,
        metadata: const {'provider': 'fake', 'duration_ms': 12},
      );
      final second = await repository.savePaperVersion(
        projectId: project.id,
        schemaVersion: 1,
        paper: const {'schema_version': 1, 'title': 'Version two'},
        origin: PaperVersionOrigin.manualEdit,
      );

      expect(first.versionNumber, 1);
      expect(second.versionNumber, 2);
      expect(first.paper, firstPaper);
      expect(first.metadata, {'provider': 'fake', 'duration_ms': 12});
      expect(first.origin, PaperVersionOrigin.generation);
      expect(second.origin, PaperVersionOrigin.manualEdit);
      expect(
        (await repository.listPaperVersions(
          project.id,
        )).map((v) => v.versionNumber),
        [1, 2],
      );
      expect(
        (await repository.getCurrentPaperVersion(project.id))!.id,
        second.id,
      );
      expect(
        (await repository.listPaperVersions(project.id)).first.paper,
        firstPaper,
      );
      expect(
        (await repository.getProject(project.id))!.currentPaperVersionId,
        second.id,
      );
    },
  );

  test(
    'closing and reopening the repository restores project and current paper',
    () async {
      final project = await repository.createProject(
        title: 'Restart recovery',
        projectContext: const {'research_field': 'Materials'},
        sourceDraft: 'A persistent source.',
      );
      final saved = await repository.savePaperVersion(
        projectId: project.id,
        schemaVersion: 1,
        paper: const {'schema_version': 1, 'title': 'Saved paper'},
        origin: PaperVersionOrigin.import,
      );
      await repository.close();
      repository = await LocalProjectRepository.open(
        path: databasePath,
        factory: databaseFactoryFfi,
      );

      expect(await repository.getProject(project.id), isNotNull);
      final restored = await repository.getCurrentPaperVersion(project.id);
      expect(restored!.id, saved.id);
      expect(restored.paper, saved.paper);
    },
  );

  test(
    'version insert and current pointer update roll back together on write failure',
    () async {
      final project = await repository.createProject(
        title: 'Atomic project',
        projectContext: const {},
      );
      final first = await repository.savePaperVersion(
        projectId: project.id,
        schemaVersion: 1,
        paper: const {'title': 'Previous saved version'},
        origin: PaperVersionOrigin.generation,
      );
      final database = await databaseFactoryFfi.openDatabase(databasePath);
      await database.execute('''
      CREATE TRIGGER reject_current_pointer
      BEFORE UPDATE OF current_paper_version_id ON projects
      BEGIN
        SELECT RAISE(ABORT, 'injected storage failure');
      END
    ''');

      await expectLater(
        repository.savePaperVersion(
          projectId: project.id,
          schemaVersion: 1,
          paper: const {'title': 'Must roll back'},
          origin: PaperVersionOrigin.manualEdit,
        ),
        throwsA(isA<Exception>()),
      );

      expect(
        (await repository.listPaperVersions(project.id)).map((v) => v.id),
        [first.id],
      );
      expect(
        (await repository.getProject(project.id))!.currentPaperVersionId,
        first.id,
      );
    },
  );

  test(
    'migration from schema version one preserves source and advances metadata',
    () async {
      await repository.close();
      await databaseFactoryFfi.deleteDatabase(databasePath);
      await _createVersionOneDatabase(databasePath);
      repository = await LocalProjectRepository.open(
        path: databasePath,
        factory: databaseFactoryFfi,
      );

      final legacyProject = await repository.getProject('legacy-project');
      expect(legacyProject!.originalDraft, 'Legacy source draft.');
      expect(legacyProject.sourceDraft, 'Legacy source draft.');
      final database = await databaseFactoryFfi.openDatabase(databasePath);
      expect(await database.getVersion(), currentDatabaseSchemaVersion);
      expect(
        (await database.query('database_meta')).single['schema_version'],
        2,
      );
      expect(
        (await database.rawQuery(
          'PRAGMA table_info(paper_versions)',
        )).any((column) => column['name'] == 'metadata_json'),
        isTrue,
      );
    },
  );

  test(
    'failed migration rolls back schema changes and leaves the old database readable',
    () async {
      await repository.close();
      await databaseFactoryFfi.deleteDatabase(databasePath);
      await _createVersionOneDatabase(
        databasePath,
        omitSourceDraftColumn: true,
      );

      await expectLater(
        LocalProjectRepository.open(
          path: databasePath,
          factory: databaseFactoryFfi,
        ),
        throwsA(isA<Exception>()),
      );

      final oldDatabase = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(version: 1),
      );
      expect(await oldDatabase.getVersion(), 1);
      final projectColumns = await oldDatabase.rawQuery(
        'PRAGMA table_info(projects)',
      );
      expect(
        projectColumns.any((column) => column['name'] == 'original_draft'),
        isFalse,
      );
      expect(
        (await oldDatabase.query('projects')).single['id'],
        'legacy-project',
      );
      expect(
        (await oldDatabase.query('database_meta')).single['schema_version'],
        1,
      );
    },
  );

  test(
    'deleting a project removes its immutable version rows in one transaction',
    () async {
      final project = await repository.createProject(
        title: 'Delete cascade',
        projectContext: const {},
      );
      await repository.savePaperVersion(
        projectId: project.id,
        schemaVersion: 1,
        paper: const {'title': 'Paper'},
        origin: PaperVersionOrigin.manualEdit,
      );

      await repository.deleteProject(project.id);

      expect(await repository.listPaperVersions(project.id), isEmpty);
    },
  );
}

Future<void> _createVersionOneDatabase(
  String path, {
  bool omitSourceDraftColumn = false,
}) async {
  final database = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE projects (
            id TEXT PRIMARY KEY NOT NULL,
            title TEXT NOT NULL,
            project_context_json TEXT NOT NULL,
            ${omitSourceDraftColumn ? '' : 'source_draft TEXT NOT NULL,'}
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            current_paper_version_id TEXT,
            FOREIGN KEY (current_paper_version_id) REFERENCES paper_versions(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE paper_versions (
            id TEXT PRIMARY KEY NOT NULL,
            project_id TEXT NOT NULL,
            version_number INTEGER NOT NULL CHECK (version_number > 0),
            schema_version INTEGER NOT NULL CHECK (schema_version > 0),
            paper_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            origin TEXT NOT NULL CHECK (origin IN ('generation', 'section_acceptance', 'manual_edit', 'import')),
            UNIQUE (project_id, version_number),
            FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE database_meta (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            schema_version INTEGER NOT NULL
          )
        ''');
        await db.insert('database_meta', {'id': 1, 'schema_version': 1});
        await db.insert('projects', {
          'id': 'legacy-project',
          'title': 'Legacy project',
          'project_context_json': jsonEncode({'research_field': 'History'}),
          if (!omitSourceDraftColumn) 'source_draft': 'Legacy source draft.',
          'created_at': '2026-10-27T00:00:00.000Z',
          'updated_at': '2026-10-27T00:00:00.000Z',
          'current_paper_version_id': null,
        });
      },
    ),
  );
  await database.close();
}
