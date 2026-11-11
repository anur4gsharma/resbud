import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resbud_mobile/features/docx_viewer/docx_document_canvas.dart';
import 'package:resbud_mobile/features/generation/generation_models.dart';
import 'package:resbud_mobile/features/pdf_viewer/pdf_viewer.dart';

Uint8List _createMockPdfBytes({required int pageCount}) {
  final buffer = StringBuffer();
  buffer.writeln('%PDF-1.4');
  buffer.writeln('1 0 obj');
  buffer.writeln('<< /Type /Catalog /Pages 2 0 R >>');
  buffer.writeln('endobj');
  buffer.writeln('2 0 obj');
  buffer.write('<< /Type /Pages /Kids [');
  for (var i = 0; i < pageCount; i++) {
    buffer.write('${i + 3} 0 R ');
  }
  buffer.writeln('] /Count $pageCount >>');
  buffer.writeln('endobj');

  for (var i = 0; i < pageCount; i++) {
    buffer.writeln('${i + 3} 0 obj');
    buffer.writeln('<< /Type /Page /Parent 2 0 R >>');
    buffer.writeln('endobj');
  }

  buffer.writeln('xref');
  buffer.writeln('trailer');
  buffer.writeln('<< /Root 1 0 R /Size ${pageCount + 3} >>');
  buffer.writeln('%%EOF');

  return Uint8List.fromList(utf8.encode(buffer.toString()));
}

PaperDraftPayload _createSamplePaper({String title = 'Test Paper'}) {
  return PaperDraftPayload(
    schemaVersion: 1,
    title: title,
    abstractText: 'Sample abstract with formula \\(E = mc^2\\).',
    keywords: const ['Rendering', 'PDF', 'Mathematics'],
    sections: const [
      PaperSectionPayload(
        id: 's1',
        heading: 'Introduction',
        content: 'This section contains \\(E = mc^2\\) and registration costs \$50 and \$100.',
        state: 'draft',
      ),
    ],
    references: const [],
    reviewWarnings: const [],
  );
}

void main() {
  group('PDF Page Count Metadata Extraction', () {
    test('extracts exact page count for 8-page document', () {
      final pdfBytes = _createMockPdfBytes(pageCount: 8);
      final count = extractPdfPageCount(pdfBytes);
      expect(count, 8);
    });

    test('extracts exact page count for 1-page document', () {
      final pdfBytes = _createMockPdfBytes(pageCount: 1);
      final count = extractPdfPageCount(pdfBytes);
      expect(count, 1);
    });
  });

  group('Single Authoritative PDF Viewer Toolbar & Controls', () {
    testWidgets('renders exactly ONE toolbar with synchronized 8-page count', (tester) async {
      final eightPagePdf = _createMockPdfBytes(pageCount: 8);
      final paper = _createSamplePaper();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PdfViewer(
              paper: paper,
              initialPdfBytes: eightPagePdf,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Exactly ONE toolbar
      expect(find.byKey(const ValueKey('pdf-viewer-toolbar')), findsOneWidget);

      // Page indicator displays "Page 1 of 8"
      expect(find.byKey(const ValueKey('pdf-page-indicator')), findsOneWidget);
      expect(find.text('Page 1 of 8'), findsOneWidget);

      // Controls present without duplicates
      expect(find.byKey(const ValueKey('button-pdf-page-prev')), findsOneWidget);
      expect(find.byKey(const ValueKey('button-pdf-page-next')), findsOneWidget);
      expect(find.byKey(const ValueKey('button-pdf-zoom-in')), findsOneWidget);
      expect(find.byKey(const ValueKey('button-pdf-zoom-out')), findsOneWidget);
      expect(find.byKey(const ValueKey('button-pdf-fit-width')), findsOneWidget);
      expect(find.byKey(const ValueKey('button-pdf-viewer-rotate')), findsOneWidget);
      expect(find.byKey(const ValueKey('button-pdf-viewer-print')), findsOneWidget);
      expect(find.byKey(const ValueKey('button-pdf-viewer-download')), findsOneWidget);
      expect(find.byKey(const ValueKey('button-pdf-viewer-download-docx')), findsOneWidget);
      expect(find.byKey(const ValueKey('button-pdf-viewer-fullscreen')), findsOneWidget);
    });

    testWidgets('page navigation increments and decrements synchronized page index', (tester) async {
      final eightPagePdf = _createMockPdfBytes(pageCount: 8);
      final paper = _createSamplePaper();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PdfViewer(
              paper: paper,
              initialPdfBytes: eightPagePdf,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Page 1 of 8'), findsOneWidget);

      // Tap Next page
      await tester.tap(find.byKey(const ValueKey('button-pdf-page-next')));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 8'), findsOneWidget);

      // Tap Next page again
      await tester.tap(find.byKey(const ValueKey('button-pdf-page-next')));
      await tester.pumpAndSettle();
      expect(find.text('Page 3 of 8'), findsOneWidget);

      // Tap Previous page
      await tester.tap(find.byKey(const ValueKey('button-pdf-page-prev')));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 8'), findsOneWidget);
    });

    testWidgets('zoom controls scale zoom indicator accurately without duplication', (tester) async {
      final onePagePdf = _createMockPdfBytes(pageCount: 1);
      final paper = _createSamplePaper();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PdfViewer(
              paper: paper,
              initialPdfBytes: onePagePdf,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Page 1 of 1'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);

      // Zoom in
      await tester.tap(find.byKey(const ValueKey('button-pdf-zoom-in')));
      await tester.pumpAndSettle();
      expect(find.text('110%'), findsOneWidget);

      // Zoom out
      await tester.tap(find.byKey(const ValueKey('button-pdf-zoom-out')));
      await tester.pumpAndSettle();
      expect(find.text('100%'), findsOneWidget);

      // Fit to width resets zoom
      await tester.tap(find.byKey(const ValueKey('button-pdf-zoom-in')));
      await tester.pumpAndSettle();
      expect(find.text('110%'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('button-pdf-fit-width')));
      await tester.pumpAndSettle();
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('loading a new PDF updates total page count and resets state', (tester) async {
      final eightPagePdf = _createMockPdfBytes(pageCount: 8);
      final onePagePdf = _createMockPdfBytes(pageCount: 1);
      final paper = _createSamplePaper();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PdfViewer(
              paper: paper,
              initialPdfBytes: eightPagePdf,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Page 1 of 8'), findsOneWidget);

      // Rebuild with 1-page PDF
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PdfViewer(
              paper: paper,
              initialPdfBytes: onePagePdf,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Page 1 of 1'), findsOneWidget);
    });
  });

  group('Mathematical Canvas Rendering & Currency Distinction', () {
    testWidgets('distinguishes currency from mathematical expressions', (tester) async {
      const paper = PaperDraftPayload(
        schemaVersion: 1,
        title: 'Math vs Currency Test',
        abstractText: 'Tests currency vs math delimiters.',
        keywords: ['Math', 'Currency'],
        sections: [
          PaperSectionPayload(
            id: 's1',
            heading: 'Economics & Formulation',
            content: 'Fee is \$50 and discount is \$20. The formula is \\(E = mc^2\\). Also code `\\frac{a}{b}`.',
            state: 'draft',
          ),
        ],
        references: [],
        reviewWarnings: [],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DocxDocumentCanvas(
              paper: paper,
              zoom: 1.0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ensure currency text is preserved in text spans
      expect(find.textContaining('\$50'), findsWidgets);
      expect(find.textContaining('\$20'), findsWidgets);
      // Ensure code block text is preserved
      expect(find.textContaining(r'\frac{a}{b}'), findsWidgets);
    });
  });
}
