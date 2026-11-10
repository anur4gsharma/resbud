import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Platform and OS considerations:
///
/// On desktop and host operating systems (Linux, macOS, Windows):
/// Files are saved directly to the designated filesystem directory (e.g., standard
/// documents or system temp) and can be immediately opened in office applications.
///
/// On mobile platforms (Android, iOS):
/// Applications execute inside OS-enforced sandboxes. Files written to local app
/// directories remain private to the application. To expose documents to external
/// file managers or word processors on physical mobile devices, files must either
/// be saved to public external storage (requiring scoped storage permissions on Android)
/// or transferred via the system share sheet / document provider.
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

/// Local filesystem implementation of [DocxFileSaver] that performs safe filename
/// sanitization and conflict resolution (e.g., `paper (1).docx`).
class LocalDocxFileSaver implements DocxFileSaver {
  LocalDocxFileSaver({
    this.targetDirectory,
    this.directoryResolver,
    this.webSaveHandler,
  });

  final Directory? targetDirectory;
  final Future<Directory> Function()? directoryResolver;
  final Future<void> Function({required String fileName, required Uint8List bytes})? webSaveHandler;

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
