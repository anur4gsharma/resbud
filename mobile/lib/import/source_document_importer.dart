import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:xml/xml_events.dart';

const maxSourceFileBytes = 10 * 1024 * 1024;
const maxZipEntries = 1000;
const maxExpandedZipBytes = 50 * 1024 * 1024;
const maxImportedTextCharacters = 50000;

final List<int> _crc32Table = List<int>.generate(256, (index) {
  var value = index;
  for (var bit = 0; bit < 8; bit++) {
    value = (value & 1) == 1 ? (value >> 1) ^ 0xedb88320 : value >> 1;
  }
  return value;
}, growable: false);

enum SourceImportErrorCode {
  unsupportedFormat,
  unsupportedMediaType,
  fileTooLarge,
  expandedDataTooLarge,
  invalidEncoding,
  encryptedDocument,
  malformedDocument,
  emptyDocument,
  contentTooLong,
}

class SourceImportException implements Exception {
  const SourceImportException(this.code, this.message);

  final SourceImportErrorCode code;
  final String message;

  @override
  String toString() => message;
}

class ImportedSource {
  const ImportedSource({required this.text, required this.format});

  final String text;
  final String format;
}

/// Extracts UTF-8 TXT and non-encrypted DOCX files entirely in memory.
///
/// Only the main DOCX document body is read. ZIP metadata is inspected before
/// decompression, and the main XML entry is inflated with a bounded sink.
class SourceDocumentImporter {
  const SourceDocumentImporter();

  ImportedSource importBytes({
    required String fileName,
    required Uint8List bytes,
    String? contentType,
  }) {
    if (bytes.length > maxSourceFileBytes) {
      throw const SourceImportException(
        SourceImportErrorCode.fileTooLarge,
        'Choose a file no larger than 10 MiB.',
      );
    }

    final extension = _extension(fileName);
    final isText = extension == 'txt' || extension == 'md' || extension == 'markdown';
    if (!isText && extension != 'docx') {
      throw const SourceImportException(
        SourceImportErrorCode.unsupportedFormat,
        'Choose a UTF-8 .txt, .md, or .docx file.',
      );
    }
    _validateMediaType(extension, contentType);
    if (bytes.isEmpty) {
      throw const SourceImportException(
        SourceImportErrorCode.emptyDocument,
        'The selected document is empty.',
      );
    }

    final text = isText ? _readText(bytes) : _readDocx(bytes);
    if (text.trim().isEmpty) {
      throw const SourceImportException(
        SourceImportErrorCode.emptyDocument,
        'No readable text was found in the selected document.',
      );
    }
    if (text.runes.length > maxImportedTextCharacters) {
      throw const SourceImportException(
        SourceImportErrorCode.contentTooLong,
        'The extracted text exceeds the 50,000 character generation limit. Shorten the source and try again.',
      );
    }
    return ImportedSource(text: text, format: extension);
  }

  String _readText(Uint8List bytes) {
    try {
      var text = const Utf8Decoder(allowMalformed: false).convert(bytes);
      if (text.startsWith('\uFEFF')) text = text.substring(1);
      return _normalizeLineEndings(text);
    } on FormatException {
      throw const SourceImportException(
        SourceImportErrorCode.invalidEncoding,
        'The .txt file must use valid UTF-8 encoding.',
      );
    }
  }

  String _readDocx(Uint8List bytes) {
    try {
      if (_hasCompoundFileSignature(bytes)) {
        throw const SourceImportException(
          SourceImportErrorCode.encryptedDocument,
          'Encrypted .docx files are not supported.',
        );
      }
      final entry = _findMainDocument(bytes);
      final xmlBytes = _readZipEntry(bytes, entry);
      late final String xml;
      try {
        xml = const Utf8Decoder(allowMalformed: false).convert(xmlBytes);
      } on FormatException {
        throw const SourceImportException(
          SourceImportErrorCode.invalidEncoding,
          'The .docx document body uses an unsupported text encoding.',
        );
      }
      if (RegExp(r'<!\s*(DOCTYPE|ENTITY)', caseSensitive: false).hasMatch(xml)) {
        throw const FormatException('DTD is not supported');
      }
      return _extractDocumentBody(xml);
    } on SourceImportException {
      rethrow;
    } on FormatException {
      throw const SourceImportException(
        SourceImportErrorCode.malformedDocument,
        'The .docx file is malformed or uses an unsupported document structure.',
      );
    } on Object {
      throw const SourceImportException(
        SourceImportErrorCode.malformedDocument,
        'The .docx file could not be read. Choose a valid, non-encrypted .docx file.',
      );
    }
  }

  void _validateMediaType(String extension, String? contentType) {
    final normalized = contentType?.split(';').first.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty || normalized == 'application/octet-stream') {
      return;
    }
    final isText = extension == 'txt' || extension == 'md' || extension == 'markdown';
    final valid = isText
        ? normalized == 'text/plain' ||
            normalized == 'text/markdown' ||
            normalized == 'text/x-markdown'
        : normalized ==
                'application/vnd.openxmlformats-officedocument.wordprocessingml.document' ||
            normalized == 'application/zip';
    if (!valid) {
      throw const SourceImportException(
        SourceImportErrorCode.unsupportedMediaType,
        'The selected file type does not match its file extension.',
      );
    }
  }

  String _extension(String fileName) {
    final name = fileName.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }
}

class _ZipEntry {
  const _ZipEntry({
    required this.flags,
    required this.method,
    required this.crc32,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
  });

  final int flags;
  final int method;
  final int crc32;
  final int compressedSize;
  final int uncompressedSize;
  final int localHeaderOffset;
}

_ZipEntry _findMainDocument(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final eocd = _findEndOfCentralDirectory(data);
  final disk = data.getUint16(eocd + 4, Endian.little);
  final centralDisk = data.getUint16(eocd + 6, Endian.little);
  final diskEntries = data.getUint16(eocd + 8, Endian.little);
  final entryCount = data.getUint16(eocd + 10, Endian.little);
  final centralSize = data.getUint32(eocd + 12, Endian.little);
  final centralOffset = data.getUint32(eocd + 16, Endian.little);
  final commentLength = data.getUint16(eocd + 20, Endian.little);

  if (disk != 0 || centralDisk != 0 || diskEntries != entryCount) {
    throw const FormatException('Multi-disk ZIP is unsupported');
  }
  if (entryCount > maxZipEntries) {
    throw const SourceImportException(
      SourceImportErrorCode.expandedDataTooLarge,
      'The .docx archive exceeds the supported ZIP entry limit.',
    );
  }
  final centralEnd = centralOffset + centralSize;
  if (centralOffset < 0 || centralEnd > eocd || eocd + 22 + commentLength > bytes.length) {
    throw const FormatException('Invalid central directory bounds');
  }

  var cursor = centralOffset;
  var totalExpanded = 0;
  _ZipEntry? mainDocument;
  for (var index = 0; index < entryCount; index++) {
    if (cursor + 46 > centralEnd || data.getUint32(cursor, Endian.little) != 0x02014b50) {
      throw const FormatException('Invalid ZIP central directory entry');
    }
    final flags = data.getUint16(cursor + 8, Endian.little);
    final method = data.getUint16(cursor + 10, Endian.little);
    final crc = data.getUint32(cursor + 16, Endian.little);
    final compressedSize = data.getUint32(cursor + 20, Endian.little);
    final uncompressedSize = data.getUint32(cursor + 24, Endian.little);
    final nameLength = data.getUint16(cursor + 28, Endian.little);
    final extraLength = data.getUint16(cursor + 30, Endian.little);
    final entryCommentLength = data.getUint16(cursor + 32, Endian.little);
    final diskStart = data.getUint16(cursor + 34, Endian.little);
    final localHeaderOffset = data.getUint32(cursor + 42, Endian.little);
    final entryEnd = cursor + 46 + nameLength + extraLength + entryCommentLength;
    if (entryEnd > centralEnd || diskStart != 0) {
      throw const FormatException('Invalid ZIP entry bounds');
    }
    if (compressedSize == 0xffffffff ||
        uncompressedSize == 0xffffffff ||
        localHeaderOffset == 0xffffffff) {
      throw const FormatException('ZIP64 is unsupported');
    }
    if ((flags & 0x0001) != 0 || (flags & 0x0040) != 0) {
      throw const SourceImportException(
        SourceImportErrorCode.encryptedDocument,
        'Encrypted .docx files are not supported.',
      );
    }
    totalExpanded += uncompressedSize;
    if (totalExpanded > maxExpandedZipBytes) {
      throw const SourceImportException(
        SourceImportErrorCode.expandedDataTooLarge,
        'The .docx archive expands beyond the supported 50 MiB limit.',
      );
    }
    final name = String.fromCharCodes(bytes.sublist(cursor + 46, cursor + 46 + nameLength));
    if (name == 'word/document.xml') {
      if (mainDocument != null) throw const FormatException('Duplicate main document');
      mainDocument = _ZipEntry(
        flags: flags,
        method: method,
        crc32: crc,
        compressedSize: compressedSize,
        uncompressedSize: uncompressedSize,
        localHeaderOffset: localHeaderOffset,
      );
    }
    cursor = entryEnd;
  }
  if (cursor != centralEnd || mainDocument == null) {
    throw const FormatException('Missing or malformed main document');
  }
  return mainDocument;
}

int _findEndOfCentralDirectory(ByteData data) {
  final minimum = data.lengthInBytes - 22 - 65535;
  for (var offset = data.lengthInBytes - 22; offset >= minimum && offset >= 0; offset--) {
    if (data.getUint32(offset, Endian.little) == 0x06054b50) return offset;
  }
  throw const FormatException('ZIP end record not found');
}

Uint8List _readZipEntry(Uint8List bytes, _ZipEntry entry) {
  final data = ByteData.sublistView(bytes);
  final offset = entry.localHeaderOffset;
  if (offset + 30 > bytes.length || data.getUint32(offset, Endian.little) != 0x04034b50) {
    throw const FormatException('Invalid local ZIP header');
  }
  final flags = data.getUint16(offset + 6, Endian.little);
  final method = data.getUint16(offset + 8, Endian.little);
  final nameLength = data.getUint16(offset + 26, Endian.little);
  final extraLength = data.getUint16(offset + 28, Endian.little);
  if (flags != entry.flags || method != entry.method || (flags & 0x0001) != 0) {
    throw const FormatException('ZIP headers disagree');
  }
  final nameStart = offset + 30;
  final dataStart = nameStart + nameLength + extraLength;
  final dataEnd = dataStart + entry.compressedSize;
  if (dataEnd > bytes.length || dataStart > dataEnd) {
    throw const FormatException('Compressed data is outside the file');
  }
  final localName = String.fromCharCodes(bytes.sublist(nameStart, nameStart + nameLength));
  if (localName != 'word/document.xml') throw const FormatException('Unexpected local entry');
  final compressed = bytes.sublist(dataStart, dataEnd);
  late final Uint8List result;
  if (entry.method == 0) {
    result = compressed;
  } else if (entry.method == 8) {
    final sink = _BoundedBytesSink(maxExpandedZipBytes);
    final inflater = ZLibDecoder(raw: true).startChunkedConversion(sink);
    inflater.add(compressed);
    inflater.close();
    result = sink.takeBytes();
  } else {
    throw const FormatException('Unsupported ZIP compression method');
  }
  if (result.length != entry.uncompressedSize || _crc32(result) != entry.crc32) {
    throw const FormatException('DOCX data integrity check failed');
  }
  return result;
}

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc = (crc >> 8) ^ _crc32Table[(crc ^ byte) & 0xff];
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

String _extractDocumentBody(String xml) {
  final output = _BoundedTextBuilder(maxImportedTextCharacters);
  final stack = <String>[];
  final rowCellCounts = <int>[];
  final cells = <_BoundedTextBuilder>[];
  var bodyCount = 0;
  var inBody = false;
  var paragraphDepth = -1;
  var textDepth = -1;

  void add(String value) {
    if (cells.isEmpty) {
      output.add(value);
    } else {
      cells.last.add(value);
    }
  }

  for (final event in parseEvents(
    xml,
    validateDocument: true,
    validateNesting: true,
  )) {
    if (event is XmlDoctypeEvent) {
      throw const FormatException('Document types are not supported');
    }
    if (event is XmlStartElementEvent) {
      final name = event.localName;
      stack.add(name);
      if (stack.length == 1 && name != 'document') {
        throw const FormatException('Unexpected document root');
      }
      if (stack.length == 2 && stack[0] == 'document' && name == 'body') {
        bodyCount++;
        inBody = true;
      }
      if (!inBody) continue;
      switch (name) {
        case 'p':
          if (paragraphDepth < 0) paragraphDepth = stack.length;
          break;
        case 'tr':
          rowCellCounts.add(0);
          break;
        case 'tc':
          if (rowCellCounts.isNotEmpty) {
            if (rowCellCounts.last > 0) add('\t');
            rowCellCounts[rowCellCounts.length - 1]++;
          }
          cells.add(_BoundedTextBuilder(maxImportedTextCharacters));
          break;
        case 't':
          if (paragraphDepth >= 0) textDepth = stack.length;
          break;
        case 'tab':
          if (paragraphDepth >= 0) add('\t');
          break;
        case 'br':
        case 'cr':
          if (paragraphDepth >= 0) add('\n');
          break;
      }
      if (event.isSelfClosing) {
        if (name == 't' && textDepth == stack.length) textDepth = -1;
        if (name == 'p' && paragraphDepth == stack.length) {
          add('\n');
          paragraphDepth = -1;
        }
        if (name == 'tc' && cells.isNotEmpty) {
          final cellText = cells.removeLast().toString().trimRight().replaceAll('\n', ' ');
          add(cellText);
        }
        if (name == 'tr' && rowCellCounts.isNotEmpty) {
          add('\n');
          rowCellCounts.removeLast();
        }
        if (name == 'body' && stack.length == 2) inBody = false;
        stack.removeLast();
      }
      continue;
    }
    if (event is XmlTextEvent) {
      if (inBody && textDepth >= 0) add(event.value);
      continue;
    }
    if (event is XmlCDATAEvent) {
      if (inBody && textDepth >= 0) add(event.value);
      continue;
    }
    if (event is XmlEndElementEvent) {
      final name = event.localName;
      if (inBody) {
        if (name == 't' && textDepth == stack.length) textDepth = -1;
        if (name == 'p' && paragraphDepth == stack.length) {
          add('\n');
          paragraphDepth = -1;
        }
        if (name == 'tc' && cells.isNotEmpty) {
          final cellText = cells.removeLast().toString().trimRight().replaceAll('\n', ' ');
          add(cellText);
        }
        if (name == 'tr' && rowCellCounts.isNotEmpty) {
          add('\n');
          rowCellCounts.removeLast();
        }
      }
      if (stack.isEmpty || stack.removeLast() != name) {
        throw const FormatException('Mismatched document tags');
      }
      if (stack.length == 1 && stack.single == 'document' && name == 'body') {
        inBody = false;
      }
    }
  }
  if (stack.isNotEmpty || bodyCount != 1) {
    throw const FormatException('Missing or malformed document body');
  }
  return _normalizeLineEndings(output.toString());
}

String _normalizeLineEndings(String text) => text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

bool _hasCompoundFileSignature(Uint8List bytes) {
  const signature = [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1];
  if (bytes.length < signature.length) return false;
  for (var index = 0; index < signature.length; index++) {
    if (bytes[index] != signature[index]) return false;
  }
  return true;
}

class _BoundedTextBuilder {
  _BoundedTextBuilder(this.limit);

  final int limit;
  final StringBuffer _buffer = StringBuffer();
  int _length = 0;

  void add(String value) {
    _length += value.runes.length;
    if (_length > limit) {
      throw const SourceImportException(
        SourceImportErrorCode.contentTooLong,
        'The extracted text exceeds the 50,000 character generation limit. Shorten the source and try again.',
      );
    }
    _buffer.write(value);
  }

  @override
  String toString() => _buffer.toString();
}

class _BoundedBytesSink implements Sink<List<int>> {
  _BoundedBytesSink(this.limit);

  final int limit;
  final BytesBuilder _builder = BytesBuilder(copy: false);
  int _length = 0;

  @override
  void add(List<int> data) {
    _length += data.length;
    if (_length > limit) {
      throw const SourceImportException(
        SourceImportErrorCode.expandedDataTooLarge,
        'The .docx archive expands beyond the supported 50 MiB limit.',
      );
    }
    _builder.add(data);
  }

  @override
  void close() {}

  Uint8List takeBytes() => _builder.takeBytes();
}
