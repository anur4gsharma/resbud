import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Platform and OS considerations:
///
/// On desktop and host operating systems (Linux, macOS, Windows):
/// Files are saved directly to the user's standard Downloads directory
/// and can be immediately opened in office applications or file managers.
///
/// On mobile platforms (Android, iOS):
/// Files are exported directly to the device's public Downloads directory
/// (via Android MediaStore on Android 10+ so they are immediately accessible
/// in the user's Files and Downloads apps without extra permissions).
///
/// This [DocxFileSaver] interface isolates filesystem and platform-specific file
/// saving and sharing logic from the core paper editor and project state.
abstract interface class DocxFileSaver {
  /// Saves [bytes] as a DOCX file using [suggestedFilename] as the base filename,
  /// returning the absolute file path of the saved document.
  Future<String> saveDocx({
    required Uint8List bytes,
    required String suggestedFilename,
  });

  /// Saves [bytes] as a PDF file using [suggestedFilename] as the base filename,
  /// returning the absolute file path of the saved document.
  Future<String> savePdf({
    required Uint8List bytes,
    required String suggestedFilename,
  });
}

class DocxFileSaverException implements Exception {
  const DocxFileSaverException(this.message);

  final String message;

  @override
  String toString() => 'DocxFileSaverException: $message';
}

/// Local filesystem and platform channel implementation of [DocxFileSaver]
/// that ensures files are saved directly into the user's Downloads directory
/// with safe filename sanitization and conflict resolution (e.g., `paper (1).docx`).
class LocalDocxFileSaver implements DocxFileSaver {
  LocalDocxFileSaver({
    this.targetDirectory,
    this.directoryResolver,
    this.webSaveHandler,
  });

  final Directory? targetDirectory;
  final Future<Directory> Function()? directoryResolver;
  final Future<void> Function({required String fileName, required Uint8List bytes})? webSaveHandler;

  static const MethodChannel _androidChannel = MethodChannel('org.resbud.mobile/file_saver');

  @override
  Future<String> saveDocx({
    required Uint8List bytes,
    required String suggestedFilename,
  }) async {
    if (bytes.isEmpty) {
      throw const DocxFileSaverException('Cannot save an empty DOCX document.');
    }

    final sanitized = sanitizeDocxFilename(suggestedFilename);

    if (kIsWeb) {
      try {
        if (webSaveHandler != null) {
          await webSaveHandler!(fileName: sanitized, bytes: bytes);
        } else {
          await FilePicker.saveFile(
            fileName: sanitized,
            bytes: bytes,
            mimeType:
                'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          );
        }
        return sanitized;
      } on Object catch (error) {
        throw DocxFileSaverException('Could not save exported DOCX: $error');
      }
    }

    // On Android, use native MediaStore via platform channel to save directly to public Downloads
    if (targetDirectory == null && directoryResolver == null && Platform.isAndroid) {
      try {
        final savedPath = await _androidChannel.invokeMethod<String>('saveToDownloads', {
          'fileName': sanitized,
          'bytes': bytes,
          'mimeType':
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        });
        if (savedPath != null && savedPath.isNotEmpty) {
          return savedPath;
        }
      } catch (e) {
        debugPrint('saveToDownloads channel fallback: $e');
      }
    }

    try {
      final dir = targetDirectory ??
          (directoryResolver != null
              ? await directoryResolver!()
              : await _defaultExportDirectory());

      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final uniqueFile = resolveUniqueFile(dir, sanitized);

      await uniqueFile.writeAsBytes(bytes, flush: true);
      return uniqueFile.path;
    } on DocxFileSaverException {
      rethrow;
    } on Object catch (error) {
      throw DocxFileSaverException('Could not save exported DOCX: $error');
    }
  }

  @override
  Future<String> savePdf({
    required Uint8List bytes,
    required String suggestedFilename,
  }) async {
    if (bytes.isEmpty) {
      throw const DocxFileSaverException('Cannot save an empty PDF document.');
    }

    final sanitized = sanitizePdfFilename(suggestedFilename);

    if (kIsWeb) {
      try {
        if (webSaveHandler != null) {
          await webSaveHandler!(fileName: sanitized, bytes: bytes);
        } else {
          await FilePicker.saveFile(
            fileName: sanitized,
            bytes: bytes,
            mimeType: 'application/pdf',
          );
        }
        return sanitized;
      } on Object catch (error) {
        throw DocxFileSaverException('Could not save exported PDF: $error');
      }
    }

    // On Android, use native MediaStore via platform channel to save directly to public Downloads
    if (targetDirectory == null && directoryResolver == null && Platform.isAndroid) {
      try {
        final savedPath = await _androidChannel.invokeMethod<String>('saveToDownloads', {
          'fileName': sanitized,
          'bytes': bytes,
          'mimeType': 'application/pdf',
        });
        if (savedPath != null && savedPath.isNotEmpty) {
          return savedPath;
        }
      } catch (e) {
        debugPrint('saveToDownloads channel fallback: $e');
      }
    }

    try {
      final dir = targetDirectory ??
          (directoryResolver != null
              ? await directoryResolver!()
              : await _defaultExportDirectory());

      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final uniqueFile = resolveUniqueFile(dir, sanitized);

      await uniqueFile.writeAsBytes(bytes, flush: true);
      return uniqueFile.path;
    } on DocxFileSaverException {
      rethrow;
    } on Object catch (error) {
      throw DocxFileSaverException('Could not save exported PDF: $error');
    }
  }

  static Future<Directory> _defaultExportDirectory() async {
    if (!kIsWeb) {
      // 1. Try system Downloads directory from path_provider (Desktop & platforms)
      try {
        final downloads = await getDownloadsDirectory();
        if (downloads != null && await downloads.exists()) {
          return downloads;
        }
      } catch (_) {}

      // 2. Try Android public Downloads directory
      if (Platform.isAndroid) {
        final publicDownload = Directory('/storage/emulated/0/Download');
        if (await publicDownload.exists()) {
          return publicDownload;
        }
      }

      // 3. Try standard user HOME Downloads folder
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home != null && home.isNotEmpty) {
        final homeDownloads = Directory(p.join(home, 'Downloads'));
        if (await homeDownloads.exists()) {
          return homeDownloads;
        }
      }
    }

    // 4. Fallback to temp app directory if downloads cannot be resolved
    final baseDir = Directory(p.join(Directory.systemTemp.path, 'resbud_exports'));
    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }
    return baseDir;
  }
}

/// Sanitizes a user- or server-provided filename to ensure safe local filesystem storage:
/// - Strips control characters, null bytes, and traversal separators (`/`, `\`).
/// - Replaces reserved filesystem characters (`:`, `*`, `?`, `"`, `<`, `>`, `|`) with `-`.
/// - Strips leading dots (preventing hidden files).
/// - Clamps length to 60 characters to leave room for duplicate suffixes.
/// - Ensures a `.docx` extension.
String sanitizeDocxFilename(String name) {
  var sanitized = name.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
  sanitized = sanitized.replaceAll(RegExp(r'[\\/:\*\?"<>|]'), '-');
  sanitized = sanitized.trim();
  while (sanitized.startsWith('.')) {
    sanitized = sanitized.substring(1).trim();
  }
  if (sanitized.isEmpty) {
    sanitized = 'research-paper.docx';
  }
  if (!sanitized.toLowerCase().endsWith('.docx')) {
    sanitized = '$sanitized.docx';
  }

  final base = p.basenameWithoutExtension(sanitized);
  final ext = p.extension(sanitized);
  final clampedBase = base.length > 60 ? base.substring(0, 60).trim() : base;
  final finalBase = clampedBase.isEmpty ? 'research-paper' : clampedBase;
  return '$finalBase$ext';
}

/// Sanitizes a user- or server-provided filename for PDF:
String sanitizePdfFilename(String name) {
  var sanitized = name.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
  sanitized = sanitized.replaceAll(RegExp(r'[\\/:\*\?"<>|]'), '-');
  sanitized = sanitized.trim();
  while (sanitized.startsWith('.')) {
    sanitized = sanitized.substring(1).trim();
  }
  if (sanitized.isEmpty) {
    sanitized = 'research-paper.pdf';
  }
  if (!sanitized.toLowerCase().endsWith('.pdf')) {
    sanitized = '$sanitized.pdf';
  }

  final base = p.basenameWithoutExtension(sanitized);
  final ext = p.extension(sanitized);
  final clampedBase = base.length > 60 ? base.substring(0, 60).trim() : base;
  final finalBase = clampedBase.isEmpty ? 'research-paper' : clampedBase;
  return '$finalBase$ext';
}

/// Resolves duplicate filenames by appending a monotonic counter:
/// `name.docx` -> `name (1).docx` -> `name (2).docx`.
File resolveUniqueFile(Directory dir, String filename) {
  var candidate = File(p.join(dir.path, filename));
  if (!candidate.existsSync()) {
    return candidate;
  }

  final ext = p.extension(filename);
  final rawBase = p.basenameWithoutExtension(filename);
  final match = RegExp(r'^(.*) \((\d+)\)$').firstMatch(rawBase);
  final base = match != null ? match.group(1)! : rawBase;
  var counter = match != null ? int.parse(match.group(2)!) + 1 : 1;

  while (true) {
    final candidateName = '$base ($counter)$ext';
    candidate = File(p.join(dir.path, candidateName));
    if (!candidate.existsSync()) {
      return candidate;
    }
    counter++;
  }
}
