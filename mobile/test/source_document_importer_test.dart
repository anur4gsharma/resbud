import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:resbud_mobile/import/source_document_importer.dart';

void main() {
  const importer = SourceDocumentImporter();

  test('imports UTF-8 text, strips an encoding BOM, and normalizes newlines', () {
    final result = importer.importBytes(
      fileName: 'notes.TXT',
      contentType: 'text/plain; charset=utf-8',
      bytes: Uint8List.fromList(utf8.encode('\uFEFFFirst\r\n🙂\rLast')),
    );

    expect(result.format, 'txt');
    expect(result.text, 'First\n🙂\nLast');
  });

  test('rejects invalid UTF-8 without replacement characters', () {
    expect(
      () => importer.importBytes(
        fileName: 'notes.txt',
        bytes: Uint8List.fromList([0xc3, 0x28]),
      ),
      throwsA(isA<SourceImportException>().having(
        (error) => error.code,
        'code',
        SourceImportErrorCode.invalidEncoding,
      )),
    );
  });

  test('extracts body paragraphs and table cells in readable order', () {
    const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>Opening claim stays intact.</w:t></w:r></w:p>
    <w:tbl><w:tr><w:tc><w:p><w:r><w:t>Cell A</w:t></w:r></w:p></w:tc>
      <w:tc><w:p><w:r><w:t>Cell B</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
    <w:p><w:r><w:t>Final claim.</w:t></w:r></w:p>
  </w:body>
</w:document>''';
    final result = importer.importBytes(
      fileName: 'draft.docx',
      contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      bytes: _zip({'word/document.xml': utf8.encode(xml)}),
    );

    expect(result.format, 'docx');
    expect(result.text, 'Opening claim stays intact.\nCell A\tCell B\nFinal claim.\n');
  });

  test('ignores non-body package entries such as macros and embedded content', () {
    final xml = _document('<w:p><w:r><w:t>Only body text.</w:t></w:r></w:p>');
    final result = importer.importBytes(
      fileName: 'draft.docx',
      bytes: _zip({
        'word/document.xml': utf8.encode(xml),
        'word/vbaProject.bin': [1, 2, 3, 4],
        'word/comments.xml': utf8.encode('<comments>private comments</comments>'),
        'word/_rels/document.xml.rels': utf8.encode('<Relationships/>'),
      }),
    );

    expect(result.text, 'Only body text.\n');
  });

  test('rejects malformed ZIP/XML and packages missing the main document', () {
    expect(
      () => importer.importBytes(
        fileName: 'draft.docx',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
      throwsA(isA<SourceImportException>()),
    );
    expect(
      () => importer.importBytes(
        fileName: 'draft.docx',
        bytes: _zip({'word/document.xml': utf8.encode('<w:document>')}),
      ),
      throwsA(isA<SourceImportException>()),
    );
    expect(
      () => importer.importBytes(
        fileName: 'draft.docx',
        bytes: _zip({
          'word/document.xml': utf8.encode(
            '<!DOCTYPE document [<!ENTITY x "unsafe">]><document><body>&x;</body></document>',
          ),
        }),
      ),
      throwsA(isA<SourceImportException>()),
    );
    expect(
      () => importer.importBytes(
        fileName: 'draft.docx',
        bytes: _zip({'word/styles.xml': utf8.encode('<styles/>')}),
      ),
      throwsA(isA<SourceImportException>()),
    );
  });

  test('rejects encrypted packages', () {
    final encrypted = _zip({'word/document.xml': utf8.encode(_document('Text'))});
    _setZipFlags(encrypted, 0x0001);

    expect(
      () => importer.importBytes(fileName: 'draft.docx', bytes: encrypted),
      throwsA(isA<SourceImportException>().having(
        (error) => error.code,
        'code',
        SourceImportErrorCode.encryptedDocument,
      )),
    );
    expect(
      () => importer.importBytes(
        fileName: 'office-encrypted.docx',
        bytes: Uint8List.fromList([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]),
      ),
      throwsA(isA<SourceImportException>().having(
        (error) => error.code,
        'code',
        SourceImportErrorCode.encryptedDocument,
      )),
    );
  });

  test('rejects ZIP entry count and declared expansion bombs before inflation', () {
    final tooManyEntries = <String, List<int>>{
      for (var i = 0; i < 1001; i++) 'entry-$i': [1],
      'word/document.xml': utf8.encode(_document('Text')),
    };
    expect(
      () => importer.importBytes(fileName: 'draft.docx', bytes: _zip(tooManyEntries)),
      throwsA(isA<SourceImportException>()),
    );

    final bomb = _zip({'word/document.xml': utf8.encode(_document('Text'))});
    _setMainUncompressedSize(bomb, 50 * 1024 * 1024 + 1);
    expect(
      () => importer.importBytes(fileName: 'draft.docx', bytes: bomb),
      throwsA(isA<SourceImportException>().having(
        (error) => error.code,
        'code',
        SourceImportErrorCode.expandedDataTooLarge,
      )),
    );
  });

  test('stops inflation when a compressed entry lies about its expanded size', () {
    final expanded = Uint8List(maxExpandedZipBytes + 1);
    final bomb = _zip(
      {'word/document.xml': expanded},
      deflateFiles: const {'word/document.xml'},
    );
    _setMainUncompressedSize(bomb, 1);

    expect(
      () => importer.importBytes(fileName: 'draft.docx', bytes: bomb),
      throwsA(isA<SourceImportException>().having(
        (error) => error.code,
        'code',
        SourceImportErrorCode.expandedDataTooLarge,
      )),
    );
  });

  test('rejects oversized files, empty documents, unsupported formats and MIME mismatch', () {
    expect(
      () => importer.importBytes(
        fileName: 'large.txt',
        bytes: Uint8List(maxSourceFileBytes + 1),
      ),
      throwsA(isA<SourceImportException>().having(
        (error) => error.code,
        'code',
        SourceImportErrorCode.fileTooLarge,
      )),
    );
    expect(
      () => importer.importBytes(fileName: 'empty.txt', bytes: Uint8List(0)),
      throwsA(isA<SourceImportException>().having(
        (error) => error.code,
        'code',
        SourceImportErrorCode.emptyDocument,
      )),
    );
    expect(
      () => importer.importBytes(
        fileName: 'legacy.doc',
        bytes: Uint8List.fromList([1]),
      ),
      throwsA(isA<SourceImportException>().having(
        (error) => error.code,
        'code',
        SourceImportErrorCode.unsupportedFormat,
      )),
    );
    expect(
      () => importer.importBytes(
        fileName: 'notes.txt',
        contentType: 'application/pdf',
        bytes: utf8.encode('text'),
      ),
      throwsA(isA<SourceImportException>().having(
        (error) => error.code,
        'code',
        SourceImportErrorCode.unsupportedMediaType,
      )),
    );
  });

  test('rejects extracted source beyond the generation character limit', () {
    expect(
      () => importer.importBytes(
        fileName: 'long.txt',
        bytes: Uint8List.fromList(
          utf8.encode(List<String>.filled(maxImportedTextCharacters + 1, 'a').join()),
        ),
      ),
      throwsA(isA<SourceImportException>().having(
        (error) => error.code,
        'code',
        SourceImportErrorCode.contentTooLong,
      )),
    );
    expect(
      () => importer.importBytes(
        fileName: 'empty.docx',
        bytes: _zip({'word/document.xml': utf8.encode(_document(''))}),
      ),
      throwsA(isA<SourceImportException>().having(
        (error) => error.code,
        'code',
        SourceImportErrorCode.emptyDocument,
      )),
    );
  });
}

String _document(String body) => '''<w:document xmlns:w="urn:test"><w:body>$body</w:body></w:document>''';

Uint8List _zip(Map<String, List<int>> files, {Set<String> deflateFiles = const {}}) {
  final local = BytesBuilder(copy: false);
  final central = BytesBuilder(copy: false);
  var localOffset = 0;
  for (final entry in files.entries) {
    final name = utf8.encode(entry.key);
    final content = Uint8List.fromList(entry.value);
    final crc = _crc32(content);
    final method = deflateFiles.contains(entry.key) ? 8 : 0;
    final payload = method == 8 ? ZLibEncoder(raw: true).convert(content) : content;
    final header = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 0, Endian.little)
      ..setUint16(8, method, Endian.little)
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, payload.length, Endian.little)
      ..setUint32(22, content.length, Endian.little)
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
      ..setUint16(10, method, Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, payload.length, Endian.little)
      ..setUint32(24, content.length, Endian.little)
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

void _setZipFlags(Uint8List zip, int flags) {
  final view = ByteData.sublistView(zip);
  var local = 0;
  while (local + 4 < zip.length && view.getUint32(local, Endian.little) != 0x04034b50) {
    local++;
  }
  view.setUint16(local + 6, flags, Endian.little);
  var central = 0;
  while (central + 4 < zip.length && view.getUint32(central, Endian.little) != 0x02014b50) {
    central++;
  }
  view.setUint16(central + 8, flags, Endian.little);
}

void _setMainUncompressedSize(Uint8List zip, int size) {
  final view = ByteData.sublistView(zip);
  var central = 0;
  while (central + 4 < zip.length && view.getUint32(central, Endian.little) != 0x02014b50) {
    central++;
  }
  view.setUint32(central + 24, size, Endian.little);
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
