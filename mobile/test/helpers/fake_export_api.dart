import 'dart:convert';
import 'dart:typed_data';

import 'package:resbud_mobile/features/export/docx_export_client.dart';
import 'package:resbud_mobile/features/export/docx_file_saver.dart';
import 'package:resbud_mobile/features/generation/generation_models.dart';

Uint8List createValidDocxBytes({
  required String title,
  required String abstractText,
  List<String> sectionTexts = const [],
}) {
  final buffer = StringBuffer();
  buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  buffer.writeln('<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">');
  buffer.writeln('  <w:body>');
  buffer.writeln('    <w:p><w:r><w:t>$title</w:t></w:r></w:p>');
  buffer.writeln('    <w:p><w:r><w:t>$abstractText</w:t></w:r></w:p>');
  for (final text in sectionTexts) {
    buffer.writeln('    <w:p><w:r><w:t>$text</w:t></w:r></w:p>');
  }
  buffer.writeln('  </w:body>');
  buffer.writeln('</w:document>');

  return _zip({'word/document.xml': utf8.encode(buffer.toString())});
}

class FakePaperExportApi implements PaperExportApi {
  int exportCallCount = 0;
  PaperDraftPayload? lastExportedPaper;
  DocxExportResult? resultToReturn;
  Object? errorToThrow;

  @override
  Future<DocxExportResult> exportDocx(PaperDraftPayload paper) async {
    exportCallCount++;
    lastExportedPaper = paper;
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return resultToReturn ??
        DocxExportResult(
          bytes: createValidDocxBytes(
            title: paper.title,
            abstractText: paper.abstractText,
            sectionTexts: [for (final s in paper.sections) s.content],
          ),
          suggestedFilename:
              'resbud-${paper.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}.docx',
          requestId: 'test-export-req-1',
        );
  }
}

class FakeDocxFileSaver implements DocxFileSaver {
  int saveCallCount = 0;
  Uint8List? lastSavedBytes;
  String? lastSuggestedFilename;
  String? pathToReturn;
  Object? errorToThrow;

  @override
  Future<String> saveDocx({
    required Uint8List bytes,
    required String suggestedFilename,
  }) async {
    saveCallCount++;
    lastSavedBytes = bytes;
    lastSuggestedFilename = suggestedFilename;
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return pathToReturn ?? '/simulated/documents/$suggestedFilename';
  }
}

Uint8List _zip(Map<String, List<int>> files) {
  final local = BytesBuilder();
  final central = BytesBuilder();
  var localOffset = 0;
  for (final entry in files.entries) {
    final name = utf8.encode(entry.key);
    final payload = entry.value;
    final crc = _crc32(payload);
    final header = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 0, Endian.little)
      ..setUint16(8, 0, Endian.little)
      ..setUint16(10, 0, Endian.little)
      ..setUint16(12, 0, Endian.little)
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, payload.length, Endian.little)
      ..setUint32(22, payload.length, Endian.little)
      ..setUint16(26, name.length, Endian.little)
      ..setUint16(28, 0, Endian.little);
    local.add(header.buffer.asUint8List());
    local.add(name);
    local.add(payload);

    final directory = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(8, 0, Endian.little)
      ..setUint16(10, 0, Endian.little)
      ..setUint16(12, 0, Endian.little)
      ..setUint16(14, 0, Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, payload.length, Endian.little)
      ..setUint32(24, payload.length, Endian.little)
      ..setUint16(28, name.length, Endian.little)
      ..setUint16(30, 0, Endian.little)
      ..setUint16(32, 0, Endian.little)
      ..setUint16(34, 0, Endian.little)
      ..setUint32(42, localOffset, Endian.little);
    central.add(directory.buffer.asUint8List());
    central.add(name);
    localOffset += 30 + name.length + payload.length;
  }
  final centralBytes = central.takeBytes();
  final localBytes = local.takeBytes();
  final end = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, files.length, Endian.little)
    ..setUint16(10, files.length, Endian.little)
    ..setUint32(12, centralBytes.length, Endian.little)
    ..setUint32(16, localBytes.length, Endian.little)
    ..setUint16(20, 0, Endian.little);
  return Uint8List.fromList([
    ...localBytes,
    ...centralBytes,
    ...end.buffer.asUint8List(),
  ]);
}

final List<int> _testCrc32Table = List<int>.generate(256, (index) {
  var value = index;
  for (var bit = 0; bit < 8; bit++) {
    value = (value & 1) == 1 ? (value >> 1) ^ 0xedb88320 : value >> 1;
  }
  return value;
}, growable: false);

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc = (crc >> 8) ^ _testCrc32Table[(crc ^ byte) & 0xff];
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
