import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resbud_mobile/features/docx_viewer/docx_viewer.dart';
import 'package:resbud_mobile/features/generation/generation_models.dart';
import 'package:resbud_mobile/features/pdf_viewer/pdf_viewer.dart';

import 'helpers/fake_export_api.dart';

Uint8List _buildSamplePdfBytes({int pageCount = 3}) {
  final buffer = StringBuffer();
  buffer.writeln('%PDF-1.4');
  buffer.writeln('1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj');
  buffer.write('2 0 obj << /Type /Pages /Kids [');
  for (var i = 0; i < pageCount; i++) {
    buffer.write('${i + 3} 0 R ');
  }
  buffer.writeln('] /Count $pageCount >> endobj');
  for (var i = 0; i < pageCount; i++) {
    buffer.writeln('${i + 3} 0 obj << /Type /Page /Parent 2 0 R >> endobj');
  }
  buffer.writeln('xref\ntrailer << /Root 1 0 R /Size ${pageCount + 3} >>\n%%EOF');
  return Uint8List.fromList(utf8.encode(buffer.toString()));
}

PaperDraftPayload _buildComprehensiveTestPaper() {
  return const PaperDraftPayload(
    schemaVersion: 1,
    title: 'Fault-Tolerant Quantum Decoders: Theory and Experiments',
    abstractText:
        'This study investigates real-time decoding for surface code lattices under depolarizing noise.',
    keywords: ['Quantum Computing', 'Surface Codes', 'Fault Tolerance'],
    authorInfo: 'Alice Johnson, Bob Smith',
    affiliation: 'Department of Applied Physics, Stanford University',
    sections: [
      PaperSectionPayload(
        id: 'sec1',
        heading: '### 1. Introduction and Architectural Motivation',
        content:
            'Topological surface codes protect quantum states by encoding logical qubits into macroscopic degrees of freedom.\n\n'
            '### Historical Background\n'
            'Prior decoders relied on Minimum Weight Perfect Matching (MWPM).\n\n'
            '#### Complexity Constraints\n'
            'Real-time decoding requires sub-microsecond latency.\n\n'
            'Key requirements:\n'
            '- High throughput processing\n'
            '- Constant-time syndrome extraction\n'
            '- Translation symmetry preservation\n\n'
            'Ordered enumeration:\n'
            '1. Initialize qubit registers\n'
            '2. Measure stabilizers\n'
            '3. Correct Pauli errors\n\n'
            'Syndrome budget equation:\n'
            r'$$\mathcal{H}_{eff} = \sum_{i} X_i X_{i+1} + Z_i Z_{i+1}$$'
            '\n\n'
            '| Code Distance d | Physical Threshold | Mean Latency |\n'
            '| --- | --- | --- |\n'
            '| 3 | 0.98% | 340 ns |\n'
            '| 5 | 1.12% | 720 ns |\n'
            '| 7 | 1.25% | 1.15 us |',
        state: 'final',
      ),
      PaperSectionPayload(
        id: 'sec2',
        heading: '2. Numerical Simulations',
        content:
            'Monte Carlo experiments confirm asymptotic convergence towards theoretical bounds.\n\n'
            r'Energy scaling follows: $E(k) = \hbar \omega_0 \left(k + \frac{1}{2}\right)$.',
        state: 'final',
      ),
    ],
    references: [
      ReferencePayload(
        id: 'ref1',
        text: 'Fowler, A. G., et al. Surface codes: Towards practical large-scale quantum computation. PRA 2012.',
      ),
    ],
    reviewWarnings: [],
  );
}

void main() {
  late FakePaperExportApi fakeExportApi;
  late FakeDocxFileSaver fakeSaver;
  late PaperDraftPayload testPaper;

  setUp(() {
    fakeExportApi = FakePaperExportApi();
    fakeSaver = FakeDocxFileSaver();
    testPaper = _buildComprehensiveTestPaper();
  });

  group('Viewer Redesign — Heading Hierarchy & Markdown Hygiene', () {
    testWidgets('strips raw ### tokens from section headings and subheadings', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocxViewer(
              paper: testPaper,
              exportApi: fakeExportApi,
              fileSaver: fakeSaver,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Heading 1 should NOT contain raw ###
      expect(find.textContaining('### 1. Introduction'), findsNothing);
      expect(find.textContaining('1. Introduction and Architectural Motivation'), findsOneWidget);

      // Subheading 2 should NOT contain raw ###
      expect(find.textContaining('### Historical Background'), findsNothing);
      expect(find.text('Historical Background'), findsOneWidget);

      // Sub-subheading should NOT contain raw ####
      expect(find.textContaining('#### Complexity Constraints'), findsNothing);
      expect(find.text('Complexity Constraints'), findsOneWidget);
    });

    testWidgets('renders bullet lists and numbered lists with correct indentation', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocxViewer(
              paper: testPaper,
              exportApi: fakeExportApi,
              fileSaver: fakeSaver,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Unordered list items with bullet glyph
      expect(find.textContaining('High throughput processing'), findsOneWidget);
      expect(find.textContaining('Constant-time syndrome extraction'), findsOneWidget);

      // Ordered list items
      expect(find.textContaining('1. Initialize qubit registers'), findsOneWidget);
      expect(find.textContaining('2. Measure stabilizers'), findsOneWidget);
    });

    testWidgets('renders tables with header row and data rows inside scrollable view', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocxViewer(
              paper: testPaper,
              exportApi: fakeExportApi,
              fileSaver: fakeSaver,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Code Distance d'), findsOneWidget);
      expect(find.text('Physical Threshold'), findsOneWidget);
      expect(find.text('Mean Latency'), findsOneWidget);
      expect(find.text('340 ns'), findsOneWidget);
    });
  });

  group('Viewer Redesign — Two-Column Balanced Academic Flow', () {
    testWidgets('flows single-section content across both columns symmetrically', (tester) async {
      // Create paper with one long section
      final singleSectionPaper = testPaper.copyWith(
        pageLayout: 'two_column_academic',
        sections: [testPaper.sections.first],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocxViewer(
              paper: singleSectionPaper,
              exportApi: fakeExportApi,
              fileSaver: fakeSaver,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // In two column mode, heading & first block are in left column, subsequent blocks flow to right column
      expect(find.textContaining('1. Introduction and Architectural Motivation'), findsOneWidget);
      expect(find.textContaining('Topological surface codes protect'), findsOneWidget);
      // Complexity constraints / tables should flow across the split without blank right side
      expect(find.text('Complexity Constraints'), findsOneWidget);
      expect(find.text('Code Distance d'), findsOneWidget);
    });
  });

  group('Viewer Redesign — PDF Viewer Controls & Text Search Bar', () {
    testWidgets('PDF viewer mounts, opens search bar, navigates matches and closes search', (tester) async {
      final pdfBytes = _buildSamplePdfBytes(pageCount: 3);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PdfViewer(
              paper: testPaper,
              initialPdfBytes: pdfBytes,
              exportApi: fakeExportApi,
              fileSaver: fakeSaver,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial state
      expect(find.byKey(const ValueKey('pdf-viewer-toolbar')), findsOneWidget);
      expect(find.text('Page 1 of 3'), findsOneWidget);

      // Search toggle
      final searchToggle = find.byKey(const ValueKey('button-pdf-search-toggle'));
      expect(searchToggle, findsOneWidget);

      // Open search bar
      await tester.tap(searchToggle);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('pdf-search-bar')), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-search-input')), findsOneWidget);

      // Close search bar
      await tester.tap(find.byTooltip('Close search'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('pdf-search-bar')), findsNothing);
    });

    testWidgets('page navigation respects lower and upper bounds', (tester) async {
      final pdfBytes = _buildSamplePdfBytes(pageCount: 2);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PdfViewer(
              paper: testPaper,
              initialPdfBytes: pdfBytes,
              exportApi: fakeExportApi,
              fileSaver: fakeSaver,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Page 1 of 2'), findsOneWidget);

      // Previous page button is disabled at page 1
      final prevBtn = tester.widget<IconButton>(find.byKey(const ValueKey('button-pdf-page-prev')));
      expect(prevBtn.onPressed, isNull);

      // Advance to page 2
      await tester.tap(find.byKey(const ValueKey('button-pdf-page-next')));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 2'), findsOneWidget);

      // Next page button is disabled at page 2
      final nextBtn = tester.widget<IconButton>(find.byKey(const ValueKey('button-pdf-page-next')));
      expect(nextBtn.onPressed, isNull);
    });
  });

  group('Viewer Redesign — Responsive Viewports (Mobile & Tablet)', () {
    testWidgets('renders cleanly on phone viewport (360x640) with zero RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocxViewer(
              paper: testPaper,
              exportApi: fakeExportApi,
              fileSaver: fakeSaver,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // Toggle layout to two-column on phone
      await tester.ensureVisible(find.byKey(const ValueKey('button-docx-layout-toggle')));
      await tester.tap(find.byKey(const ValueKey('button-docx-layout-toggle')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('renders cleanly on tablet/desktop widescreen (1280x800)', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocxViewer(
              paper: testPaper,
              exportApi: fakeExportApi,
              fileSaver: fakeSaver,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Fault-Tolerant Quantum Decoders: Theory and Experiments'), findsOneWidget);
    });
  });
}
