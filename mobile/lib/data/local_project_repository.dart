import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'project_figure.dart';
import 'project_image_storage.dart';

const currentDatabaseSchemaVersion = 3;
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

  LocalProject copyWith({
    String? id,
    String? title,
    Map<String, Object?>? projectContext,
    String? sourceDraft,
    String? originalDraft,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? currentPaperVersionId,
  }) => LocalProject(
    id: id ?? this.id,
    title: title ?? this.title,
    projectContext: projectContext ?? this.projectContext,
    sourceDraft: sourceDraft ?? this.sourceDraft,
    originalDraft: originalDraft ?? this.originalDraft,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    currentPaperVersionId: currentPaperVersionId ?? this.currentPaperVersionId,
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

/// Represents a consolidated view of a generated, saved manuscript across projects.
class SavedManuscript {
  const SavedManuscript({
    required this.id,
    required this.projectId,
    required this.projectTitle,
    required this.paperTitle,
    required this.versionNumber,
    required this.schemaVersion,
    required this.createdAt,
    required this.updatedAt,
    required this.origin,
    required this.paperFormat,
    required this.citationStyle,
    required this.authorCount,
    required this.sectionCount,
    required this.referenceCount,
    required this.figureCount,
    required this.abstractSnippet,
    required this.isUnfinishedDraft,
    required this.isCurrentVersion,
    required this.rawPaper,
    this.metadata,
  });

  final String id;
  final String projectId;
  final String projectTitle;
  final String paperTitle;
  final int versionNumber;
  final int schemaVersion;
  final DateTime createdAt;
  final DateTime updatedAt;
  final PaperVersionOrigin origin;
  final String paperFormat;
  final String citationStyle;
  final int authorCount;
  final int sectionCount;
  final int referenceCount;
  final int figureCount;
  final String abstractSnippet;
  final bool isUnfinishedDraft;
  final bool isCurrentVersion;
  final Map<String, Object?> rawPaper;
  final Map<String, Object?>? metadata;

  static String formatTemplateLabel(String? template) {
    if (template == null || template.trim().isEmpty) return 'Academic Standard';
    final lower = template.toLowerCase();
    if (lower.contains('ieee')) return 'IEEE Conference';
    if (lower.contains('nature')) return 'Nature';
    if (lower.contains('acm')) return 'ACM Standard';
    if (lower.contains('apa')) return 'APA 7th';
    return template;
  }

  static String formatCitationStyleLabel(String? style) {
    if (style == null || style.trim().isEmpty) return 'IEEE';
    final lower = style.toLowerCase();
    if (lower == 'ieee') return 'IEEE';
    if (lower == 'apa') return 'APA';
    if (lower == 'acm') return 'ACM';
    if (lower == 'nature') return 'Nature';
    if (lower == 'harvard') return 'Harvard';
    if (lower == 'chicago') return 'Chicago';
    return style.toUpperCase();
  }

  factory SavedManuscript.fromJoinedRow(Map<String, Object?> row) {
    final rawPaper = Map<String, Object?>.from(
      jsonDecode(row['paper_json']! as String) as Map,
    );
    final projectContext = Map<String, Object?>.from(
      jsonDecode(row['project_context_json']! as String) as Map,
    );
    final projectTitle = row['project_title']! as String;
    final paperTitleRaw = (rawPaper['title'] as String?)?.trim();
    final paperTitle = (paperTitleRaw != null && paperTitleRaw.isNotEmpty)
        ? paperTitleRaw
        : projectTitle;

    final templateRaw = (rawPaper['document_template'] ??
        projectContext['paper_template']) as String?;
    final citationStyleRaw = (rawPaper['citation_style'] ??
        projectContext['citation_style']) as String?;

    final authorsList = (rawPaper['authors'] as List?) ??
        (projectContext['authors'] as List?);
    final sectionsList = rawPaper['sections'] as List?;
    final referencesList = rawPaper['references'] as List?;
    final figuresList = (rawPaper['figures'] as List?) ??
        (projectContext['figures'] as List?);

    final abstractRaw = (rawPaper['abstract_text'] as String?) ??
        (rawPaper['abstract'] as String?) ??
        '';

    final metadataRaw = row['metadata_json'] == null
        ? null
        : Map<String, Object?>.from(
            jsonDecode(row['metadata_json']! as String) as Map,
          );

    final isPartial = metadataRaw?['completion_status'] == 'partial' ||
        metadataRaw?['missing_sections'] != null ||
        (sectionsList == null || sectionsList.isEmpty);

    final currentPaperVerId = row['current_paper_version_id'] as String?;
    final isCurrent = currentPaperVerId == row['version_id'];

    return SavedManuscript(
      id: row['version_id']! as String,
      projectId: row['project_id']! as String,
      projectTitle: projectTitle,
      paperTitle: paperTitle,
      versionNumber: row['version_number']! as int,
      schemaVersion: row['schema_version']! as int,
      createdAt: DateTime.parse(row['version_created_at']! as String).toUtc(),
      updatedAt: DateTime.parse(row['project_updated_at']! as String).toUtc(),
      origin: _originFromDatabase(row['origin']! as String),
      paperFormat: formatTemplateLabel(templateRaw),
      citationStyle: formatCitationStyleLabel(citationStyleRaw),
      authorCount: authorsList?.length ?? 0,
      sectionCount: sectionsList?.length ?? 0,
      referenceCount: referencesList?.length ?? 0,
      figureCount: figuresList?.length ?? 0,
      abstractSnippet: abstractRaw.trim(),
      isUnfinishedDraft: isPartial,
      isCurrentVersion: isCurrent,
      rawPaper: rawPaper,
      metadata: metadataRaw,
    );
  }
}

class LocalProjectRepository {
  LocalProjectRepository(
    this._database, {
    ProjectImageStorage? imageStorage,
    String Function()? idGenerator,
    DateTime Function()? clock,
  }) : _imageStorage = imageStorage,
       _idGenerator = idGenerator ?? _uuidV4,
       _clock = clock ?? DateTime.now;

  final Database _database;
  final ProjectImageStorage? _imageStorage;
  final String Function() _idGenerator;
  final DateTime Function() _clock;

  ProjectImageStorage get imageStorage =>
      _imageStorage ?? DatabaseProjectImageStorage(_database);

  static Future<LocalProjectRepository> open({
    String? path,
    DatabaseFactory? factory,
    ProjectImageStorage? imageStorage,
    String Function()? idGenerator,
    DateTime Function()? clock,
  }) async {
    final databaseBackend = factory ?? databaseFactory;
    final resolvedPath =
        path ?? (kIsWeb ? _databaseFileName : p.join(await getDatabasesPath(), _databaseFileName));
    final database = await databaseBackend.openDatabase(
      resolvedPath,
      options: OpenDatabaseOptions(
        version: currentDatabaseSchemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => _createCurrentSchema(db),
        onUpgrade: _upgradeSchema,
      ),
    );
    final storage = imageStorage ?? await ProjectImageStorage.create(database: database);
    return LocalProjectRepository(
      database,
      imageStorage: storage,
      idGenerator: idGenerator,
      clock: clock,
    );
  }

  Future<void> close() => _database.close();

  Database get database => _database;

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

  Future<(Map<String, Object?>, List<ProjectFigure>)> _prepareFiguresAndContext(
    String projectId,
    Map<String, Object?> projectContext,
  ) async {
    final sanitized = Map<String, Object?>.from(projectContext);
    final figuresToPersist = <ProjectFigure>[];
    final rawFigures = projectContext['figures'];
    if (rawFigures is List && rawFigures.isNotEmpty) {
      final sanitizedFigures = <Map<String, Object?>>[];
      for (var i = 0; i < rawFigures.length; i++) {
        final raw = rawFigures[i];
        if (raw is Map) {
          final figMap = Map<String, dynamic>.from(raw);
          final fig = ProjectFigure.fromMap(
            figMap,
            projectId: projectId,
            defaultNumber: i + 1,
          );
          var finalFig = fig;
          if (fig.cachedBytes != null && fig.cachedBytes!.isNotEmpty) {
            final key = await imageStorage.saveImage(
              projectId: projectId,
              figureId: fig.id,
              filename: fig.filename,
              bytes: fig.cachedBytes!,
            );
            finalFig = fig.copyWith(storageKey: key);
          }
          figuresToPersist.add(finalFig);
          sanitizedFigures.add(finalFig.toMetadataMap());
        }
      }
      sanitized['figures'] = sanitizedFigures;
    }
    return (sanitized, figuresToPersist);
  }

  Future<LocalProject> createProject({
    required String title,
    required Map<String, Object?> projectContext,
    String sourceDraft = '',
    String? originalDraft,
  }) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', 'must not be blank');
    }
    final id = _idGenerator();
    final now = _clock().toUtc().toIso8601String();

    final (sanitizedContext, figuresToPersist) =
        await _prepareFiguresAndContext(id, projectContext);

    await _database.transaction((transaction) async {
      await transaction.insert('projects', {
        'id': id,
        'title': normalizedTitle,
        'project_context_json': jsonEncode(sanitizedContext),
        'source_draft': sourceDraft,
        'original_draft': originalDraft ?? sourceDraft,
        'created_at': now,
        'updated_at': now,
        'current_paper_version_id': null,
      });

      for (final fig in figuresToPersist) {
        await transaction.insert(
          'project_figures',
          fig.toDatabaseRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
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
    if (normalizedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', 'must not be blank');
    }

    final (sanitizedContext, figuresToPersist) =
        await _prepareFiguresAndContext(projectId, projectContext);

    await _database.transaction((transaction) async {
      final changed = await transaction.update(
        'projects',
        {
          'title': normalizedTitle,
          'project_context_json': jsonEncode(sanitizedContext),
          'source_draft': sourceDraft,
          'updated_at': _clock().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [projectId],
      );
      if (changed != 1) throw StateError('Project not found');

      for (final fig in figuresToPersist) {
        await transaction.insert(
          'project_figures',
          fig.toDatabaseRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
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
      await transaction.delete(
        'project_figures',
        where: 'project_id = ?',
        whereArgs: [projectId],
      );
    });
    await imageStorage.deleteProjectImages(projectId);
  }

  Future<List<ProjectFigure>> listProjectFigures(String projectId) async {
    final rows = await _database.query(
      'project_figures',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'figure_number ASC, id ASC',
    );
    return rows.map(ProjectFigure.fromDatabaseRow).toList(growable: false);
  }

  Future<Uint8List?> getFigureBytes(String storageKey) async {
    return imageStorage.readImage(storageKey);
  }

  Future<void> saveProjectFigures(String projectId, List<ProjectFigure> figures) async {
    final updatedFigures = <ProjectFigure>[];
    for (final figure in figures) {
      var key = figure.storageKey;
      if (figure.cachedBytes != null && figure.cachedBytes!.isNotEmpty) {
        key = await imageStorage.saveImage(
          projectId: projectId,
          figureId: figure.id,
          filename: figure.filename,
          bytes: figure.cachedBytes!,
        );
      }
      updatedFigures.add(figure.copyWith(storageKey: key));
    }
    await _database.transaction((transaction) async {
      for (final figure in updatedFigures) {
        await transaction.insert(
          'project_figures',
          figure.toDatabaseRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> deleteProjectFigure(String projectId, String figureId) async {
    final rows = await _database.query(
      'project_figures',
      columns: ['storage_key'],
      where: 'project_id = ? AND id = ?',
      whereArgs: [projectId, figureId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final key = rows.first['storage_key'] as String?;
      if (key != null && key.isNotEmpty) {
        await imageStorage.deleteImage(key);
      }
    }
    await _database.delete(
      'project_figures',
      where: 'project_id = ? AND id = ?',
      whereArgs: [projectId, figureId],
    );
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

  /// Lists saved manuscripts across projects, with support for title search,
  /// template format filtering, and custom sorting.
  Future<List<SavedManuscript>> listSavedManuscripts({
    String? search,
    String? format,
    String? sortBy, // 'date_desc', 'date_asc', 'title_asc', 'title_desc'
    bool onlyCurrent = true,
  }) async {
    final query = '''
      SELECT 
        pv.id AS version_id,
        pv.project_id,
        pv.version_number,
        pv.schema_version,
        pv.paper_json,
        pv.created_at AS version_created_at,
        pv.origin,
        pv.metadata_json,
        p.title AS project_title,
        p.project_context_json,
        p.source_draft,
        p.original_draft,
        p.created_at AS project_created_at,
        p.updated_at AS project_updated_at,
        p.current_paper_version_id
      FROM paper_versions pv
      JOIN projects p ON pv.project_id = p.id
      ${onlyCurrent ? 'WHERE (pv.id = p.current_paper_version_id OR (p.current_paper_version_id IS NULL AND pv.version_number = (SELECT MAX(pv2.version_number) FROM paper_versions pv2 WHERE pv2.project_id = p.id)))' : ''}
      ORDER BY pv.created_at DESC
    ''';
    final rows = await _database.rawQuery(query);
    var list = rows.map((r) => SavedManuscript.fromJoinedRow(r)).toList();

    if (search != null && search.trim().isNotEmpty) {
      final q = search.trim().toLowerCase();
      list = list.where((m) =>
        m.paperTitle.toLowerCase().contains(q) ||
        m.projectTitle.toLowerCase().contains(q) ||
        m.abstractSnippet.toLowerCase().contains(q)
      ).toList();
    }

    if (format != null && format.trim().isNotEmpty && format.toLowerCase() != 'all') {
      final f = format.trim().toLowerCase();
      list = list.where((m) => m.paperFormat.toLowerCase().contains(f)).toList();
    }

    if (sortBy != null) {
      switch (sortBy) {
        case 'title_asc':
          list.sort((a, b) => a.paperTitle.toLowerCase().compareTo(b.paperTitle.toLowerCase()));
        case 'title_desc':
          list.sort((a, b) => b.paperTitle.toLowerCase().compareTo(a.paperTitle.toLowerCase()));
        case 'date_asc':
          list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        case 'date_desc':
        default:
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
    }

    return list;
  }

  /// Retrieves a specific saved manuscript by version id.
  Future<SavedManuscript?> getSavedManuscript(String versionId) async {
    const query = '''
      SELECT 
        pv.id AS version_id,
        pv.project_id,
        pv.version_number,
        pv.schema_version,
        pv.paper_json,
        pv.created_at AS version_created_at,
        pv.origin,
        pv.metadata_json,
        p.title AS project_title,
        p.project_context_json,
        p.source_draft,
        p.original_draft,
        p.created_at AS project_created_at,
        p.updated_at AS project_updated_at,
        p.current_paper_version_id
      FROM paper_versions pv
      JOIN projects p ON pv.project_id = p.id
      WHERE pv.id = ?
      LIMIT 1
    ''';
    final rows = await _database.rawQuery(query, [versionId]);
    if (rows.isEmpty) return null;
    return SavedManuscript.fromJoinedRow(rows.single);
  }

  /// Renames a manuscript, updating the title in the paper JSON and synchronizing
  /// with the parent project title.
  Future<void> renamePaper({
    required String projectId,
    required String newTitle,
    String? versionId,
  }) async {
    final title = newTitle.trim();
    if (title.isEmpty) throw ArgumentError.value(newTitle, 'newTitle', 'must not be blank');

    await _database.transaction((txn) async {
      final projectRows = await txn.query(
        'projects',
        where: 'id = ?',
        whereArgs: [projectId],
        limit: 1,
      );
      if (projectRows.isEmpty) throw StateError('Project not found');
      final project = LocalProject.fromRow(projectRows.single);

      final targetVerId = versionId ?? project.currentPaperVersionId;
      if (targetVerId != null) {
        final verRows = await txn.query(
          'paper_versions',
          where: 'id = ? AND project_id = ?',
          whereArgs: [targetVerId, projectId],
          limit: 1,
        );
        if (verRows.isNotEmpty) {
          final ver = PaperVersion.fromRow(verRows.single);
          final updatedPaper = Map<String, Object?>.from(ver.paper);
          updatedPaper['title'] = title;
          await txn.update(
            'paper_versions',
            {'paper_json': jsonEncode(updatedPaper)},
            where: 'id = ?',
            whereArgs: [targetVerId],
          );
        }
      }

      await txn.update(
        'projects',
        {
          'title': title,
          'updated_at': _clock().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [projectId],
      );
    });
  }

  /// Duplicates a manuscript into an independent new project with figures and context preserved.
  Future<LocalProject> duplicatePaper({
    required String projectId,
    String? versionId,
    String? newTitle,
  }) async {
    final origProject = await getProject(projectId);
    if (origProject == null) throw StateError('Project not found');

    final targetVerId = versionId ?? origProject.currentPaperVersionId;
    PaperVersion? targetVer;
    if (targetVerId != null) {
      final verRows = await _database.query(
        'paper_versions',
        where: 'id = ? AND project_id = ?',
        whereArgs: [targetVerId, projectId],
        limit: 1,
      );
      if (verRows.isNotEmpty) {
        targetVer = PaperVersion.fromRow(verRows.single);
      }
    }

    final paperTitle = targetVer != null &&
            (targetVer.paper['title'] as String?)?.trim().isNotEmpty == true
        ? targetVer.paper['title'] as String
        : origProject.title;
    final copyTitle = newTitle?.trim().isNotEmpty == true
        ? newTitle!.trim()
        : '$paperTitle (Copy)';

    final newProject = await createProject(
      title: copyTitle,
      projectContext: origProject.projectContext,
      sourceDraft: origProject.sourceDraft,
      originalDraft: origProject.originalDraft,
    );

    // Duplicate figures from original project if any
    final figures = await listProjectFigures(projectId);
    if (figures.isNotEmpty) {
      final copiedFigures = <ProjectFigure>[];
      for (final fig in figures) {
        final bytes = await getFigureBytes(fig.storageKey);
        copiedFigures.add(fig.copyWith(
          id: _idGenerator(),
          projectId: newProject.id,
          cachedBytes: bytes,
        ));
      }
      await saveProjectFigures(newProject.id, copiedFigures);
    }

    if (targetVer != null) {
      final copiedPaper = Map<String, Object?>.from(targetVer.paper);
      copiedPaper['title'] = copyTitle;
      await savePaperVersion(
        projectId: newProject.id,
        schemaVersion: targetVer.schemaVersion,
        paper: copiedPaper,
        origin: PaperVersionOrigin.import,
        metadata: {
          'duplicated_from_project_id': projectId,
          'duplicated_from_version_id': targetVer.id,
        },
      );
    }

    return (await getProject(newProject.id))!;
  }

  /// Deletes a paper (all versions) while preserving the parent project context,
  /// or optionally deletes the entire project cascade.
  Future<void> deletePaper({
    required String projectId,
    bool deleteEntireProject = false,
  }) async {
    if (deleteEntireProject) {
      await deleteProject(projectId);
      return;
    }
    await _database.transaction((txn) async {
      await txn.update(
        'projects',
        {
          'current_paper_version_id': null,
          'updated_at': _clock().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [projectId],
      );
      await txn.delete(
        'paper_versions',
        where: 'project_id = ?',
        whereArgs: [projectId],
      );
    });
  }

  /// Deletes an individual paper version, updating the current version pointer if necessary.
  Future<void> deletePaperVersion({
    required String projectId,
    required String versionId,
  }) async {
    await _database.transaction((txn) async {
      final projectRows = await txn.query(
        'projects',
        columns: ['current_paper_version_id'],
        where: 'id = ?',
        whereArgs: [projectId],
        limit: 1,
      );
      final currentVerId = projectRows.isNotEmpty
          ? projectRows.first['current_paper_version_id'] as String?
          : null;

      final remaining = await txn.query(
        'paper_versions',
        where: 'project_id = ? AND id != ?',
        whereArgs: [projectId, versionId],
        orderBy: 'version_number DESC',
      );
      final newCurrentId =
          remaining.isNotEmpty ? remaining.first['id'] as String : null;

      if (currentVerId == versionId) {
        await txn.update(
          'projects',
          {
            'current_paper_version_id': newCurrentId,
            'updated_at': _clock().toUtc().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [projectId],
        );
      }

      await txn.delete(
        'paper_versions',
        where: 'id = ? AND project_id = ?',
        whereArgs: [versionId, projectId],
      );
    });
  }

  /// Lists projects that have research materials or context but have no generated paper yet.
  Future<List<LocalProject>> listUnfinishedProjects() async {
    final rows = await _database.query(
      'projects',
      where: 'current_paper_version_id IS NULL',
      orderBy: 'updated_at DESC',
    );
    return rows.map(LocalProject.fromRow).toList(growable: false);
  }

  Future<String?> getSetting(String key) async {
    try {
      final rows = await _database.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isNotEmpty) return rows.first['value'] as String?;
    } catch (_) {
      // Table might not exist yet
    }
    return null;
  }

  Future<void> setSetting(String key, String value) async {
    await _database.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL
      )
    ''');
    await _database.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteSetting(String key) async {
    try {
      await _database.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: [key],
      );
    } catch (_) {}
  }

  static Future<void> _createCurrentSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL
      )
    ''');
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
    await db.execute('''
      CREATE TABLE IF NOT EXISTS project_figures (
        id TEXT NOT NULL,
        project_id TEXT NOT NULL,
        figure_number INTEGER NOT NULL DEFAULT 1,
        filename TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        width INTEGER NOT NULL DEFAULT 0,
        height INTEGER NOT NULL DEFAULT 0,
        file_size INTEGER NOT NULL DEFAULT 0,
        caption TEXT NOT NULL,
        alt_text TEXT NOT NULL DEFAULT '',
        placement TEXT NOT NULL DEFAULT 'column_width',
        section_id TEXT,
        storage_key TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (project_id, id),
        FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS project_image_blobs (
        storage_key TEXT PRIMARY KEY NOT NULL,
        image_bytes BLOB NOT NULL
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
    if (version == 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS project_figures (
          id TEXT NOT NULL,
          project_id TEXT NOT NULL,
          figure_number INTEGER NOT NULL DEFAULT 1,
          filename TEXT NOT NULL,
          mime_type TEXT NOT NULL,
          width INTEGER NOT NULL DEFAULT 0,
          height INTEGER NOT NULL DEFAULT 0,
          file_size INTEGER NOT NULL DEFAULT 0,
          caption TEXT NOT NULL,
          alt_text TEXT NOT NULL DEFAULT '',
          placement TEXT NOT NULL DEFAULT 'column_width',
          section_id TEXT,
          storage_key TEXT NOT NULL,
          created_at TEXT NOT NULL,
          PRIMARY KEY (project_id, id),
          FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS project_image_blobs (
          storage_key TEXT PRIMARY KEY NOT NULL,
          image_bytes BLOB NOT NULL
        )
      ''');
      await db.update('database_meta', {'schema_version': 3}, where: 'id = 1');
      version = 3;
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
