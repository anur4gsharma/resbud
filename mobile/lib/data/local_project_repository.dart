import 'dart:convert';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

const currentDatabaseSchemaVersion = 2;
const _databaseFileName = 'resbud_projects.sqlite';

enum PaperVersionOrigin { generation, sectionAcceptance, manualEdit, import }

class LocalProject {
  const LocalProject({
    required this.id,
    required this.title,
    required this.projectContext,
    required this.sourceDraft,
    required this.originalDraft,
    required this.createdAt,
    required this.updatedAt,
    required this.currentPaperVersionId,
  });

  final String id;
  final String title;
  final Map<String, Object?> projectContext;
  final String sourceDraft;
  final String originalDraft;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? currentPaperVersionId;

  factory LocalProject.fromRow(Map<String, Object?> row) => LocalProject(
    id: row['id']! as String,
    title: row['title']! as String,
    projectContext: Map<String, Object?>.from(
      jsonDecode(row['project_context_json']! as String) as Map,
    ),
    sourceDraft: row['source_draft']! as String,
    originalDraft: row['original_draft']! as String,
    createdAt: DateTime.parse(row['created_at']! as String).toUtc(),
    updatedAt: DateTime.parse(row['updated_at']! as String).toUtc(),
    currentPaperVersionId: row['current_paper_version_id'] as String?,
  );
}

class PaperVersion {
  const PaperVersion({
    required this.id,
    required this.projectId,
    required this.versionNumber,
    required this.schemaVersion,
    required this.paper,
    required this.createdAt,
    required this.origin,
    required this.metadata,
  });

  final String id;
  final String projectId;
  final int versionNumber;
  final int schemaVersion;
  final Map<String, Object?> paper;
  final DateTime createdAt;
  final PaperVersionOrigin origin;
  final Map<String, Object?>? metadata;

  factory PaperVersion.fromRow(Map<String, Object?> row) => PaperVersion(
    id: row['id']! as String,
    projectId: row['project_id']! as String,
    versionNumber: row['version_number']! as int,
    schemaVersion: row['schema_version']! as int,
    paper: Map<String, Object?>.from(
      jsonDecode(row['paper_json']! as String) as Map,
    ),
    createdAt: DateTime.parse(row['created_at']! as String).toUtc(),
    origin: _originFromDatabase(row['origin']! as String),
    metadata: row['metadata_json'] == null
        ? null
        : Map<String, Object?>.from(
            jsonDecode(row['metadata_json']! as String) as Map,
          ),
  );
}

class LocalProjectRepository {
  LocalProjectRepository(
    this._database, {
    String Function()? idGenerator,
    DateTime Function()? clock,
  }) : _idGenerator = idGenerator ?? _uuidV4,
       _clock = clock ?? DateTime.now;

  final Database _database;
  final String Function() _idGenerator;
  final DateTime Function() _clock;

  static Future<LocalProjectRepository> open({
    String? path,
    DatabaseFactory? factory,
    String Function()? idGenerator,
    DateTime Function()? clock,
  }) async {
    final databaseBackend = factory ?? databaseFactory;
    final resolvedPath =
        path ?? p.join(await getDatabasesPath(), _databaseFileName);
    final database = await databaseBackend.openDatabase(
      resolvedPath,
      options: OpenDatabaseOptions(
        version: currentDatabaseSchemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => _createCurrentSchema(db),
        onUpgrade: _upgradeSchema,
      ),
    );
    return LocalProjectRepository(
      database,
      idGenerator: idGenerator,
      clock: clock,
    );
  }

  Future<void> close() => _database.close();

  Future<List<LocalProject>> listProjects() async {
    final rows = await _database.query(
      'projects',
      orderBy: 'updated_at DESC, id ASC',
    );
    return rows.map(LocalProject.fromRow).toList(growable: false);
  }

  Future<LocalProject?> getProject(String projectId) async {
    final rows = await _database.query(
      'projects',
      where: 'id = ?',
      whereArgs: [projectId],
      limit: 1,
    );
    return rows.isEmpty ? null : LocalProject.fromRow(rows.single);
  }

  Future<LocalProject> createProject({
    required String title,
    required Map<String, Object?> projectContext,
    String sourceDraft = '',
    String? originalDraft,
  }) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty)
      throw ArgumentError.value(title, 'title', 'must not be blank');
    final id = _idGenerator();
    final now = _clock().toUtc().toIso8601String();
    await _database.insert('projects', {
      'id': id,
      'title': normalizedTitle,
      'project_context_json': jsonEncode(projectContext),
      'source_draft': sourceDraft,
      'original_draft': originalDraft ?? sourceDraft,
      'created_at': now,
      'updated_at': now,
      'current_paper_version_id': null,
    });
    return (await getProject(id))!;
  }

  Future<LocalProject> updateProjectInputs({
    required String projectId,
    required String title,
    required Map<String, Object?> projectContext,
    required String sourceDraft,
  }) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty)
      throw ArgumentError.value(title, 'title', 'must not be blank');
    await _database.transaction((transaction) async {
      final changed = await transaction.update(
        'projects',
        {
          'title': normalizedTitle,
          'project_context_json': jsonEncode(projectContext),
          'source_draft': sourceDraft,
          'updated_at': _clock().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [projectId],
      );
      if (changed != 1) throw StateError('Project not found');
    });
    return (await getProject(projectId))!;
  }

  Future<void> deleteProject(String projectId) async {
    await _database.transaction((transaction) async {
      final deleted = await transaction.delete(
        'projects',
        where: 'id = ?',
        whereArgs: [projectId],
      );
      if (deleted != 1) throw StateError('Project not found');
    });
  }

  Future<PaperVersion> savePaperVersion({
    required String projectId,
    required int schemaVersion,
    required Map<String, Object?> paper,
    required PaperVersionOrigin origin,
    Map<String, Object?>? metadata,
  }) async {
    final paperJson = jsonEncode(paper);
    final metadataJson = metadata == null ? null : jsonEncode(metadata);
    final id = _idGenerator();
    final createdAt = _clock().toUtc().toIso8601String();
    late final int versionNumber;

    await _database.transaction((transaction) async {
      final project = await transaction.query(
        'projects',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [projectId],
        limit: 1,
      );
      if (project.isEmpty) throw StateError('Project not found');
      final maximum = Sqflite.firstIntValue(
        await transaction.rawQuery(
          'SELECT MAX(version_number) FROM paper_versions WHERE project_id = ?',
          [projectId],
        ),
      );
      versionNumber = (maximum ?? 0) + 1;
      await transaction.insert('paper_versions', {
        'id': id,
        'project_id': projectId,
        'version_number': versionNumber,
        'schema_version': schemaVersion,
        'paper_json': paperJson,
        'created_at': createdAt,
        'origin': _originToDatabase(origin),
        'metadata_json': metadataJson,
      });
      final changed = await transaction.update(
        'projects',
        {'current_paper_version_id': id, 'updated_at': createdAt},
        where: 'id = ?',
        whereArgs: [projectId],
      );
      if (changed != 1) throw StateError('Project not found');
    });

    return PaperVersion(
      id: id,
      projectId: projectId,
      versionNumber: versionNumber,
      schemaVersion: schemaVersion,
      paper: Map<String, Object?>.from(jsonDecode(paperJson) as Map),
      createdAt: DateTime.parse(createdAt).toUtc(),
      origin: origin,
      metadata: metadataJson == null
          ? null
          : Map<String, Object?>.from(jsonDecode(metadataJson) as Map),
    );
  }

  Future<List<PaperVersion>> listPaperVersions(String projectId) async {
    final rows = await _database.query(
      'paper_versions',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'version_number ASC',
    );
    return rows.map(PaperVersion.fromRow).toList(growable: false);
  }

  Future<PaperVersion?> getCurrentPaperVersion(String projectId) async {
    final project = await getProject(projectId);
    if (project?.currentPaperVersionId == null) return null;
    final rows = await _database.query(
      'paper_versions',
      where: 'id = ? AND project_id = ?',
      whereArgs: [project!.currentPaperVersionId, projectId],
      limit: 1,
    );
    return rows.isEmpty ? null : PaperVersion.fromRow(rows.single);
  }

  Future<PaperVersion> restorePaperVersion({
    required String projectId,
    required String targetVersionId,
  }) async {
    final rows = await _database.query(
      'paper_versions',
      where: 'id = ? AND project_id = ?',
      whereArgs: [targetVersionId, projectId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Target paper version not found');
    final target = PaperVersion.fromRow(rows.single);
    return savePaperVersion(
      projectId: projectId,
      schemaVersion: target.schemaVersion,
      paper: target.paper,
      origin: PaperVersionOrigin.manualEdit,
      metadata: {
        'restored_from_version_number': target.versionNumber,
        'restored_from_version_id': target.id,
      },
    );
  }

  static Future<void> _createCurrentSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE projects (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        project_context_json TEXT NOT NULL,
        source_draft TEXT NOT NULL,
        original_draft TEXT NOT NULL,
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
        metadata_json TEXT,
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
    await db.insert('database_meta', {
      'id': 1,
      'schema_version': currentDatabaseSchemaVersion,
    });
  }

  static Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    var version = oldVersion;
    if (version < 1 || newVersion != currentDatabaseSchemaVersion) {
      throw StateError('Unsupported local database migration');
    }
    if (version == 1) {
      await db.execute(
        "ALTER TABLE projects ADD COLUMN original_draft TEXT NOT NULL DEFAULT ''",
      );
      await db.execute('UPDATE projects SET original_draft = source_draft');
      await db.execute(
        'ALTER TABLE paper_versions ADD COLUMN metadata_json TEXT',
      );
      await db.update('database_meta', {'schema_version': 2}, where: 'id = 1');
      version = 2;
    }
    if (version != newVersion)
      throw StateError('No migration found for local database version');
  }
}

String _uuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

String _originToDatabase(PaperVersionOrigin origin) => switch (origin) {
  PaperVersionOrigin.generation => 'generation',
  PaperVersionOrigin.sectionAcceptance => 'section_acceptance',
  PaperVersionOrigin.manualEdit => 'manual_edit',
  PaperVersionOrigin.import => 'import',
};

PaperVersionOrigin _originFromDatabase(String origin) => switch (origin) {
  'generation' => PaperVersionOrigin.generation,
  'section_acceptance' => PaperVersionOrigin.sectionAcceptance,
  'manual_edit' => PaperVersionOrigin.manualEdit,
  'import' => PaperVersionOrigin.import,
  _ => throw StateError('Unsupported local paper version origin'),
};
