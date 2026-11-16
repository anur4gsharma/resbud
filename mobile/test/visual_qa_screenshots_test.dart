import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resbud_mobile/features/docx_viewer/docx_document_canvas.dart';
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

PaperDraftPayload _buildAcademicFixturePaper({String layout = 'single_column'}) {
  return PaperDraftPayload(
    schemaVersion: 1,
    title: 'Fault-Tolerant Quantum Decoders: Theory and Experiments',
    abstractText:
        'This study investigates real-time decoding for topological surface code lattices under depolarizing noise. '
        'We formulate syndrome graph matching algorithms yielding sub-microsecond error correction cycles with scalable hardware.',
    keywords: const ['Quantum Computing', 'Surface Codes', 'Fault Tolerance', 'Syndrome Decoding'],
    authorInfo: 'Alice Johnson, Bob Smith',
    affiliation: 'Department of Applied Physics, Stanford University',
    pageLayout: layout,
    sections: const [
      PaperSectionPayload(
        id: 'sec1',
        heading: '### 1. Introduction and Architectural Motivation',
        content:
            'Topological surface codes protect quantum states by encoding logical qubits into macroscopic degrees of freedom. '
            'In fault-tolerant architectures, physical error rates must satisfy the threshold condition:\n\n'
            '### Historical Background\n'
            'Prior decoders relied on Minimum Weight Perfect Matching (MWPM), exhibiting polynomial time complexity.\n\n'
            '#### Complexity Constraints\n'
            'Real-time decoding requires sub-microsecond latency. Key requirements include:\n'
            '- High-throughput hardware pipeline\n'
            '- Constant-time syndrome extraction\n'
            '- Translation symmetry preservation\n\n'
            'Ordered execution stages:\n'
            '1. Initialize physical qubit registers\n'
            '2. Measure stabilizer generators\n'
            '3. Correct Pauli frame errors\n\n'
            'The effective syndrome Hamiltonian is expressed as:\n\n'
            r'$$\mathcal{H}_{eff} = -\sum_{v} A_v - \sum_{p} B_p + \sum_{i} \lambda_i X_i X_{i+1}$$'
            '\n\n'
            'Table 1 summarizes code distances and error thresholds:\n\n'
            '| Code Distance d | Physical Threshold | Mean Latency |\n'
            '| --- | --- | --- |\n'
            '| 3 | 0.98% | 340 ns |\n'
            '| 5 | 1.12% | 610 ns |\n'
            '| 7 | 1.25% | 890 ns |\n\n'
            '![Figure 1: Planar Surface Code Lattice Architecture and Stabilizer Layout](schema_lattice_layout)',
        state: 'final',
      ),
      PaperSectionPayload(
        id: 'sec2',
        heading: '2. Mathematical Formulation & Decoding Dynamics',
        content:
            r'Consider a stabilizer code with generator matrix $S \in \mathbb{F}_2^{(n-k) \times 2n}$. '
            'The syndrome measurement operator satisfies:\n\n'
            r'$$P(\mathbf{s} \mid \mathbf{e}) = \frac{1}{\mathcal{Z}} \exp\left(-\beta \sum_{j} J_j s_j\right)$$'
            '\n\n'
            r'where $J_j = \frac{1}{2}\ln\left(\frac{1-p}{p}\right)$ represents the boundary coupling strength. '
            r'The minimum distance satisfies $d \ge 3$ across all planar boundaries.',
        state: 'final',
      ),
      PaperSectionPayload(
        id: 'sec3',
        heading: '3. Experimental Results and Analysis',
        content:
            'Measurements conducted on a superconducting processor demonstrate logical error suppression. '
            'The scaling follows the empirical exponential relation:\n\n'
            r'$$\epsilon_L \propto \left(\frac{p}{p_{th}}\right)^{(d+1)/2}$$'
            '\n\n'
            '| Decoding Algorithm | Threshold (%) | Max Clock (MHz) | LUT Utilization |\n'
            '| --- | --- | --- | --- |\n'
            '| MWPM Baseline | 0.92 | 125 | 42,000 |\n'
            '| Neural Belief Prop | 1.05 | 250 | 68,500 |\n'
            '| Resbud Tensor Flow | 1.28 | 400 | 51,200 |\n\n'
            '![Figure 2: Logical Error Rate vs Physical Depolarizing Error Rate Across Code Distances](chart_error_rates)',
        state: 'final',
      ),
    ],
    references: const [
      ReferencePayload(
        id: 'ref1',
        text: 'Fowler, A. G., et al. (2012). Surface codes: Towards practical large-scale quantum computation. Physical Review A, 86(3), 032324.',
      ),
      ReferencePayload(
        id: 'ref2',
        text: 'Dennis, E., Kitaev, A., Landahl, A., & Preskill, J. (2002). Topological quantum memory. Journal of Mathematical Physics, 43(9), 4452-4505.',
      ),
      ReferencePayload(
        id: 'ref3',
        text: 'Bravyi, S., & Kitaev, A. (1998). Quantum codes on a lattice with boundary. arXiv:quant-ph/9811052.',
      ),
    ],
    reviewWarnings: const [],
  );
}

Future<void> _captureAndSave(
  WidgetTester tester,
  GlobalKey key,
  String basename,
) async {
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    for (final dir in [
      'releases/android/screenshots',
      'docs/screenshots',
      '../releases/android/screenshots',
      '../docs/screenshots',
    ]) {
      final file = File('$dir/$basename');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(pngBytes);
    }
  });
}

void main() {
  final fakeExportApi = FakePaperExportApi();
  final fakeSaver = FakeDocxFileSaver();
  final singleColPaper = _buildAcademicFixturePaper(layout: 'single_column');
  final twoColPaper = _buildAcademicFixturePaper(layout: 'two_column_academic');

  group('Visual QA Screenshot Generation (Phase 8)', () {
    testWidgets('1. DOCX reading on mobile', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: repaintKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: DocxViewer(
                paper: singleColPaper,
                exportApi: fakeExportApi,
                fileSaver: fakeSaver,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _captureAndSave(tester, repaintKey, '01_docx_reading_mobile.png');
      expect(File('docs/screenshots/01_docx_reading_mobile.png').existsSync(), isTrue);
    });

    testWidgets('2. PDF reading on mobile', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      final pdfBytes = _buildSamplePdfBytes(pageCount: 3);

      await tester.pumpWidget(
        RepaintBoundary(
          key: repaintKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: PdfViewer(
                paper: singleColPaper,
                initialPdfBytes: pdfBytes,
                exportApi: fakeExportApi,
                fileSaver: fakeSaver,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _captureAndSave(tester, repaintKey, '02_pdf_reading_mobile.png');
      expect(File('docs/screenshots/02_pdf_reading_mobile.png').existsSync(), isTrue);
    });

    testWidgets('3. Full-screen reading mode', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: repaintKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: DocxViewer(
                paper: singleColPaper,
                exportApi: fakeExportApi,
                fileSaver: fakeSaver,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap fullscreen button in toolbar after ensuring visibility
      final fullscreenBtn = find.byKey(const ValueKey('button-docx-viewer-fullscreen'));
      await tester.ensureVisible(fullscreenBtn);
      await tester.tap(fullscreenBtn);
      await tester.pumpAndSettle();

      await _captureAndSave(tester, repaintKey, '03_fullscreen_reading.png');
      expect(File('docs/screenshots/03_fullscreen_reading.png').existsSync(), isTrue);
    });

    testWidgets('4. Zoomed document (150%)', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: repaintKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: DocxViewer(
                paper: singleColPaper,
                exportApi: fakeExportApi,
                fileSaver: fakeSaver,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap zoom in multiple times to reach ~150%
      final zoomInBtn = find.byKey(const ValueKey('button-docx-zoom-in'));
      await tester.ensureVisible(zoomInBtn);
      await tester.tap(zoomInBtn);
      await tester.pumpAndSettle();
      await tester.tap(zoomInBtn);
      await tester.pumpAndSettle();
      await tester.tap(zoomInBtn);
      await tester.pumpAndSettle();
      await tester.tap(zoomInBtn);
      await tester.pumpAndSettle();

      await _captureAndSave(tester, repaintKey, '04_zoomed_document.png');
      expect(File('docs/screenshots/04_zoomed_document.png').existsSync(), isTrue);
    });

    testWidgets('5. Two-column academic paper', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: repaintKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: DocxViewer(
                paper: twoColPaper,
                exportApi: fakeExportApi,
                fileSaver: fakeSaver,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _captureAndSave(tester, repaintKey, '05_two_column_paper.png');
      expect(File('docs/screenshots/05_two_column_paper.png').existsSync(), isTrue);
    });

    testWidgets('6. Paper containing figures', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: repaintKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: DocxDocumentCanvas(
                paper: singleColPaper,
                zoom: 0.65,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _captureAndSave(tester, repaintKey, '06_paper_with_figures.png');
      expect(File('docs/screenshots/06_paper_with_figures.png').existsSync(), isTrue);
    });

    testWidgets('7. Paper containing mathematical equations', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: repaintKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: DocxDocumentCanvas(
                paper: twoColPaper,
                zoom: 0.8,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _captureAndSave(tester, repaintKey, '07_paper_with_equations.png');
      expect(File('docs/screenshots/07_paper_with_equations.png').existsSync(), isTrue);
    });

    testWidgets('8. Page navigation (multi-page)', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: repaintKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: DocxViewer(
                paper: singleColPaper,
                exportApi: fakeExportApi,
                fileSaver: fakeSaver,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to next page if available
      final nextBtn = find.byKey(const ValueKey('button-docx-page-next'));
      if (tester.any(nextBtn)) {
        await tester.ensureVisible(nextBtn);
        await tester.tap(nextBtn);
        await tester.pumpAndSettle();
      }

      await _captureAndSave(tester, repaintKey, '08_page_navigation.png');
      expect(File('docs/screenshots/08_page_navigation.png').existsSync(), isTrue);
    });

    testWidgets('9. Desktop reading experience (1280x800)', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repaintKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: repaintKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: DocxViewer(
                paper: twoColPaper,
                exportApi: fakeExportApi,
                fileSaver: fakeSaver,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _captureAndSave(tester, repaintKey, '09_desktop_reading.png');
      expect(File('docs/screenshots/09_desktop_reading.png').existsSync(), isTrue);
    });
  });
}
