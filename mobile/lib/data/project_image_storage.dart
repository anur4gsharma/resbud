import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Abstract durable image storage contract for project figures.
abstract interface class ProjectImageStorage {
  /// Save raw image bytes under a durable identifier and return its storage key.
  Future<String> saveImage({
    required String projectId,
    required String figureId,
    required String filename,
    required Uint8List bytes,
  });

  /// Retrieve the binary bytes for a figure given its [storageKey].
  Future<Uint8List?> readImage(String storageKey);

  /// Delete a single figure image by [storageKey].
  Future<void> deleteImage(String storageKey);

  /// Delete all image assets belonging to [projectId].
  Future<void> deleteProjectImages(String projectId);

  /// Factory constructor to create the appropriate storage for the platform.
  static Future<ProjectImageStorage> create({
    Database? database,
    Directory? customDirectory,
  }) async {
    if (kIsWeb) {
      if (database == null) {
        throw StateError('Database must be provided for web image storage.');
      }
      return DatabaseProjectImageStorage(database);
    }

    try {
      final baseDir = customDirectory ?? await getApplicationDocumentsDirectory();
      return FileProjectImageStorage(baseDir, fallbackDatabase: database);
    } catch (e) {
      debugPrint('Falling back to database image storage: $e');
      if (database != null) {
        return DatabaseProjectImageStorage(database);
      }
      rethrow;
    }
  }
}

/// Filesystem-based image storage for mobile and desktop platforms.
class FileProjectImageStorage implements ProjectImageStorage {
  FileProjectImageStorage(
    this.baseDirectory, {
    this.fallbackDatabase,
  });

  final Directory baseDirectory;
  final Database? fallbackDatabase;

  String _sanitize(String input) => input.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

  File _resolveFile(String storageKey) {
    return File(p.join(baseDirectory.path, 'resbud_media', 'figures', storageKey));
  }

  @override
  Future<String> saveImage({
    required String projectId,
    required String figureId,
    required String filename,
    required Uint8List bytes,
  }) async {
    final cleanProj = _sanitize(projectId);
    final cleanFig = _sanitize(figureId);
    final cleanName = _sanitize(filename);
    final relativeKey = '$cleanProj/${cleanFig}_$cleanName';

    final file = _resolveFile(relativeKey);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);

    // Also mirror to database blob store if available as a safety layer
    if (fallbackDatabase != null) {
      try {
        await fallbackDatabase!.insert(
          'project_image_blobs',
          {'storage_key': relativeKey, 'image_bytes': bytes},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } catch (_) {}
    }

    return relativeKey;
  }

  @override
  Future<Uint8List?> readImage(String storageKey) async {
    try {
      final file = _resolveFile(storageKey);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (e) {
      debugPrint('Error reading figure file from disk: $e');
    }

    // Try fallback database if file not found or on migration
    if (fallbackDatabase != null) {
      try {
        final rows = await fallbackDatabase!.query(
          'project_image_blobs',
          columns: ['image_bytes'],
          where: 'storage_key = ?',
          whereArgs: [storageKey],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          final blob = rows.first['image_bytes'];
          if (blob is Uint8List) {
            // Restore file cache
            try {
              final file = _resolveFile(storageKey);
              await file.parent.create(recursive: true);
              await file.writeAsBytes(blob, flush: true);
            } catch (_) {}
            return blob;
          }
        }
      } catch (_) {}
    }

    return null;
  }

  @override
  Future<void> deleteImage(String storageKey) async {
    try {
      final file = _resolveFile(storageKey);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}

    if (fallbackDatabase != null) {
      try {
        await fallbackDatabase!.delete(
          'project_image_blobs',
          where: 'storage_key = ?',
          whereArgs: [storageKey],
        );
      } catch (_) {}
    }
  }

  @override
  Future<void> deleteProjectImages(String projectId) async {
    final cleanProj = _sanitize(projectId);
    try {
      final projectDir = Directory(
        p.join(baseDirectory.path, 'resbud_media', 'figures', cleanProj),
      );
      if (await projectDir.exists()) {
        await projectDir.delete(recursive: true);
      }
    } catch (_) {}

    if (fallbackDatabase != null) {
      try {
        await fallbackDatabase!.delete(
          'project_image_blobs',
          where: 'storage_key LIKE ?',
          whereArgs: ['$cleanProj/%'],
        );
      } catch (_) {}
    }
  }
}

/// Database BLOB-based image storage for Web and fallback environments.
class DatabaseProjectImageStorage implements ProjectImageStorage {
  DatabaseProjectImageStorage(this.database);

  final Database database;

  String _sanitize(String input) => input.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

  @override
  Future<String> saveImage({
    required String projectId,
    required String figureId,
    required String filename,
    required Uint8List bytes,
  }) async {
    final cleanProj = _sanitize(projectId);
    final cleanFig = _sanitize(figureId);
    final cleanName = _sanitize(filename);
    final relativeKey = '$cleanProj/${cleanFig}_$cleanName';

    await database.insert(
      'project_image_blobs',
      {
        'storage_key': relativeKey,
        'image_bytes': bytes,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return relativeKey;
  }

  @override
  Future<Uint8List?> readImage(String storageKey) async {
    try {
      final rows = await database.query(
        'project_image_blobs',
        columns: ['image_bytes'],
        where: 'storage_key = ?',
        whereArgs: [storageKey],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final blob = rows.first['image_bytes'];
        if (blob is Uint8List) return blob;
        if (blob is List<int>) return Uint8List.fromList(blob);
      }
    } catch (e) {
      debugPrint('Error reading figure blob from database: $e');
    }
    return null;
  }

  @override
  Future<void> deleteImage(String storageKey) async {
    try {
      await database.delete(
        'project_image_blobs',
        where: 'storage_key = ?',
        whereArgs: [storageKey],
      );
    } catch (_) {}
  }

  @override
  Future<void> deleteProjectImages(String projectId) async {
    final cleanProj = _sanitize(projectId);
    try {
      await database.delete(
        'project_image_blobs',
        where: 'storage_key LIKE ?',
        whereArgs: ['$cleanProj/%'],
      );
    } catch (_) {}
  }
}
