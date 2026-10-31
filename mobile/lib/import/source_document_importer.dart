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
    bool allowPdf = true,
  }) {
    if (bytes.length > maxSourceFileBytes) {
      throw const SourceImportException(
        SourceImportErrorCode.fileTooLarge,
        'Choose a file no larger than 10 MiB.',
      );
    }

    final extension = _extension(fileName);
    final isText = extension == 'txt' || extension == 'md' || extension == 'markdown';
    final isDocx = extension == 'docx';
    final isPdf = extension == 'pdf';

    if (!allowPdf && isPdf) {
      throw const SourceImportException(
        SourceImportErrorCode.unsupportedFormat,
        'Choose a UTF-8 .txt, .md, or .docx file.',
      );
    }
    if (!isText && !isDocx && (!allowPdf || !isPdf)) {
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

    final text = isText
        ? _readText(bytes)
        : isDocx
            ? _readDocx(bytes)
            : _readPdf(bytes);
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

  ImportedSource importMultipleFiles(
    List<({String fileName, Uint8List bytes, String? contentType})> files,
  ) {
    if (files.isEmpty) {
      throw const SourceImportException(
        SourceImportErrorCode.emptyDocument,
        'No files were selected for upload.',
      );
    }
    if (files.length == 1) {
      return importBytes(
        fileName: files.first.fileName,
        bytes: files.first.bytes,
        contentType: files.first.contentType,
      );
    }
    final buffer = StringBuffer();
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final imported = importBytes(
        fileName: f.fileName,
        bytes: f.bytes,
        contentType: f.contentType,
      );
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write('=== SOURCE FILE: ${f.fileName} ===\n');
      buffer.write(imported.text);
      if (buffer.length > maxImportedTextCharacters) {
        throw const SourceImportException(
          SourceImportErrorCode.contentTooLong,
          'The combined extracted text exceeds the 50,000 character limit.',
        );
      }
    }
    return ImportedSource(text: buffer.toString(), format: 'multi');
  }

  void _validateMediaType(String extension, String? contentType) {
    final normalized = contentType?.split(';').first.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty || normalized == 'application/octet-stream') {
      return;
    }
    final isText = extension == 'txt' || extension == 'md' || extension == 'markdown';
    final isPdf = extension == 'pdf';
    final valid = isText
        ? normalized == 'text/plain' ||
            normalized == 'text/markdown' ||
            normalized == 'text/x-markdown'
        : isPdf
            ? normalized == 'application/pdf' || normalized == 'application/x-pdf'
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

  String _readPdf(Uint8List bytes) {
    if (bytes.length < 8) {
      throw const SourceImportException(
        SourceImportErrorCode.malformedDocument,
        'The selected PDF is malformed or corrupted.',
      );
    }
    final headerStr = String.fromCharCodes(bytes.sublist(0, 5));
    if (!headerStr.startsWith('%PDF-')) {
      throw const SourceImportException(
        SourceImportErrorCode.malformedDocument,
        'The selected file is not a valid PDF document.',
      );
    }

    final rawString = String.fromCharCodes(bytes);
    if (rawString.contains('/Encrypt')) {
      throw const SourceImportException(
        SourceImportErrorCode.encryptedDocument,
        'Encrypted .pdf files are not supported.',
      );
    }

    final text = _extractPdfText(bytes);
    if (text.trim().isEmpty) {
      throw const SourceImportException(
        SourceImportErrorCode.emptyDocument,
        'No readable text was found in the selected PDF document.',
      );
    }
    return _normalizeLineEndings(text);
  }

  String _extractPdfText(Uint8List bytes) {
    final buffer = StringBuffer();
    final len = bytes.length;
    var cursor = 0;
    final streamToken = [115, 116, 114, 101, 97, 109]; // 'stream'
    final endStreamToken = [101, 110, 100, 115, 116, 114, 101, 97, 109]; // 'endstream'

    while (cursor < len - 10) {
      var streamIdx = -1;
      for (var i = cursor; i <= len - 6; i++) {
        if (bytes[i] == streamToken[0] &&
            bytes[i + 1] == streamToken[1] &&
            bytes[i + 2] == streamToken[2] &&
            bytes[i + 3] == streamToken[3] &&
            bytes[i + 4] == streamToken[4] &&
            bytes[i + 5] == streamToken[5]) {
          streamIdx = i;
          break;
        }
      }
      if (streamIdx == -1) break;

      final dictStart = streamIdx > 200 ? streamIdx - 200 : 0;
      final dictStr = String.fromCharCodes(bytes.sublist(dictStart, streamIdx));
      final isFlate = dictStr.contains('/FlateDecode');

      var dataStart = streamIdx + 6;
      if (dataStart < len && bytes[dataStart] == 13) dataStart++;
      if (dataStart < len && bytes[dataStart] == 10) dataStart++;

      var endIdx = -1;
      for (var i = dataStart; i <= len - 9; i++) {
        if (bytes[i] == endStreamToken[0] &&
            bytes[i + 1] == endStreamToken[1] &&
            bytes[i + 2] == endStreamToken[2] &&
            bytes[i + 3] == endStreamToken[3] &&
            bytes[i + 4] == endStreamToken[4] &&
            bytes[i + 5] == endStreamToken[5] &&
            bytes[i + 6] == endStreamToken[6] &&
            bytes[i + 7] == endStreamToken[7] &&
            bytes[i + 8] == endStreamToken[8]) {
          endIdx = i;
          break;
        }
      }
      if (endIdx == -1) {
        cursor = dataStart;
        continue;
      }

      var dataEnd = endIdx;
      while (dataEnd > dataStart &&
          (bytes[dataEnd - 1] == 10 || bytes[dataEnd - 1] == 13 || bytes[dataEnd - 1] == 32)) {
        dataEnd--;
      }

      if (dataEnd > dataStart) {
        final streamBytes = bytes.sublist(dataStart, dataEnd);
        List<int>? decompressed;
        if (isFlate) {
          try {
            decompressed = zlib.decode(streamBytes);
          } catch (_) {
            try {
              decompressed = ZLibDecoder(raw: true).convert(streamBytes);
            } catch (_) {}
          }
        } else {
          decompressed = streamBytes;
        }

        if (decompressed != null && decompressed.isNotEmpty) {
          final text = _parsePdfStreamText(decompressed);
          if (text.isNotEmpty) {
            if (buffer.isNotEmpty) buffer.write('\n');
            buffer.write(text);
            if (buffer.length > maxImportedTextCharacters) break;
          }
        }
      }
      cursor = endIdx + 9;
    }

    return buffer.toString();
  }

  String _parsePdfStreamText(List<int> bytes) {
    final out = StringBuffer();
    final len = bytes.length;
    var i = 0;

    while (i < len) {
      if (bytes[i] == 40) { // '('
        i++;
        final strBuf = StringBuffer();
        var depth = 1;
        while (i < len && depth > 0) {
          final c = bytes[i];
          if (c == 92) { // '\' escape
            i++;
            if (i < len) {
              final esc = bytes[i];
              if (esc == 110) {
                strBuf.write('\n');
              } else if (esc == 114) {
                strBuf.write('\r');
              } else if (esc == 116) {
                strBuf.write('\t');
              } else if (esc == 40 || esc == 41 || esc == 92) {
                strBuf.writeCharCode(esc);
              } else if (esc >= 48 && esc <= 55) {
                var octalVal = esc - 48;
                if (i + 1 < len && bytes[i + 1] >= 48 && bytes[i + 1] <= 55) {
                  i++;
                  octalVal = octalVal * 8 + (bytes[i] - 48);
                  if (i + 1 < len && bytes[i + 1] >= 48 && bytes[i + 1] <= 55) {
                    i++;
                    octalVal = octalVal * 8 + (bytes[i] - 48);
                  }
                }
                strBuf.writeCharCode(octalVal);
              } else {
                strBuf.writeCharCode(esc);
              }
            }
          } else if (c == 40) {
            depth++;
            strBuf.writeCharCode(c);
          } else if (c == 41) {
            depth--;
            if (depth > 0) strBuf.writeCharCode(c);
          } else {
            strBuf.writeCharCode(c);
          }
          i++;
        }

        final str = strBuf.toString().trim();
        if (str.isNotEmpty) {
          if (out.isNotEmpty && !out.toString().endsWith(' ') && !out.toString().endsWith('\n')) {
            out.write(' ');
          }
          out.write(str);
        }
      } else if (i < len - 2 && bytes[i] == 69 && bytes[i + 1] == 84) { // 'ET' (end text)
        if (out.isNotEmpty && !out.toString().endsWith('\n')) {
          out.write('\n');
        }
        i += 2;
      } else {
        i++;
      }
    }
    return out.toString().trim();
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
