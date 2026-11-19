import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:resbud_mobile/data/local_project_repository.dart';
import 'package:resbud_mobile/data/project_figure.dart';
import 'package:resbud_mobile/features/docx_viewer/docx_document_canvas.dart';
import 'package:resbud_mobile/features/generation/generation_models.dart';
import 'package:resbud_mobile/features/paper_editor/figure_manager_sheet.dart';
import 'package:resbud_mobile/features/paper_editor/manuscript_outline_view.dart';
import 'package:resbud_mobile/features/paper_editor/paper_editor_page.dart';
import 'package:resbud_mobile/features/pdf_viewer/pdf_viewer.dart';
import 'package:resbud_mobile/features/project_input/project_input_page.dart';
import 'package:resbud_mobile/main.dart';
import 'package:resbud_mobile/shared/design_tokens.dart';

import 'helpers/fake_export_api.dart';
import 'helpers/fake_generation_api.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tempDirectory;
  late LocalProjectRepository repository;
  late LocalProject project;
  late PaperVersion version1;
  late FakeGenerationApi fakeApi;
  late FakePaperExportApi fakeExportApi;
  late FakeDocxFileSaver fakeFileSaver;

  final validPngBytes = Uint8List.fromList([
    137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
    0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196,
    137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 218, 99, 100, 248, 207,
    80, 15, 0, 3, 134, 1, 128, 90, 52, 125, 107, 0, 0, 0, 0,
    73, 69, 78, 68, 174, 66, 96, 130
  ]);

  setUpAll(() {
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('resbud_responsive_test_');
    repository = await LocalProjectRepository.open(
      path: p.join(tempDirectory.path, 'responsive.sqlite'),
      factory: databaseFactoryFfi,
    );
    fakeApi = FakeGenerationApi();
    fakeExportApi = FakePaperExportApi();
    fakeFileSaver = FakeDocxFileSaver();

    project = await repository.createProject(
      title: 'Scalable Consensus via Adaptive Pipelined State Machines',
      projectContext: {
        'title': 'Scalable Consensus via Adaptive Pipelined State Machines',
        'research_field': 'Distributed Systems',
        'research_question': 'How does adaptive batch pipelining impact Byzantine fault-tolerant commit latency?',
        'objectives': ['Model pipeline queue depth', 'Benchmark geo-distributed throughput'],
        'claimed_contribution': 'Adaptive pipeline rate-limiting algorithm with zero throughput penalty',
        'methodology_status': 'provided',
        'methodology': 'Empirical evaluation across AWS multi-region cluster with injected packet delay.',
        'dataset_or_materials_status': 'not_available',
        'results_status': 'provided',
        'results': 'Median latency reduced by 43% under high packet jitter conditions.',
        'limitations_status': 'not_identified',
        'references': [
          {'id': 'lamport1998', 'text': 'Lamport, L. (1998). The Part-Time Parliament. ACM TOCS, 16(2), 133-169.'},
          {'id': 'castro1999', 'text': 'Castro, M., & Liskov, B. (1999). Practical Byzantine Fault Tolerance. OSDI.'},
        ],
        'authors': [
          {
            'id': 'auth_1',
            'name': 'Dr. Elena Vance',
            'order': 1,
            'affiliation_ids': ['aff_1'],
            'email': 'evance@mit.edu',
            'is_corresponding': true,
          },
          {
            'id': 'auth_2',
            'name': 'Prof. Marcus Chen',
            'order': 2,
            'affiliation_ids': ['aff_1', 'aff_2'],
            'email': 'mchen@stanford.edu',
            'is_corresponding': false,
          },
        ],
        'affiliations': [
          {
            'id': 'aff_1',
            'institution': 'Massachusetts Institute of Technology',
            'department': 'Computer Science and Artificial Intelligence Laboratory',
            'city': 'Cambridge',
            'country': 'USA',
          },
          {
            'id': 'aff_2',
            'institution': 'Stanford University',
            'department': 'Department of Computer Science',
            'city': 'Stanford',
            'country': 'USA',
          },
        ],
        'preferences': {
          'document_template': 'ieee_conference',
          'citation_style': 'user_supplied',
          'target_word_count': 3200,
          'desired_sections': ['introduction', 'methodology', 'results', 'conclusion'],
        },
      },
      sourceDraft: 'Preliminary benchmark traces demonstrate substantial latency reduction across 12 datacenters.',
    );

    final genResp = await fakeApi.generate(
      GenerationRequest.fromInputs(
        project: project.projectContext,
        sourceDraft: project.sourceDraft,
      ),
    );

    final paperJson = genResp.response.paper.toJson();
    paperJson['title'] = project.title;
    paperJson['authors'] = [
      {
        'id': 'auth_1',
        'name': 'Dr. Elena Vance',
        'order': 1,
        'affiliation_ids': ['aff_1'],
        'email': 'evance@mit.edu',
        'is_corresponding': true,
      },
      {
        'id': 'auth_2',
        'name': 'Prof. Marcus Chen',
        'order': 2,
        'affiliation_ids': ['aff_1', 'aff_2'],
        'email': 'mchen@stanford.edu',
      },
    ];
    paperJson['affiliations'] = [
      {
        'id': 'aff_1',
        'institution': 'Massachusetts Institute of Technology',
        'department': 'CSAIL',
        'city': 'Cambridge',
        'country': 'USA',
      },
      {
        'id': 'aff_2',
        'institution': 'Stanford University',
        'department': 'CS Department',
        'city': 'Stanford',
        'country': 'USA',
      },
    ];

    version1 = await repository.savePaperVersion(
      projectId: project.id,
      schemaVersion: 1,
      paper: paperJson,
      origin: PaperVersionOrigin.generation,
      metadata: {'words': 2850},
    );

    final fig1 = ProjectFigure(
      id: 'fig_cdf_latency',
      projectId: project.id,
      figureNumber: 1,
      filename: 'commit_latency_cdf.png',
      mimeType: 'image/png',
      fileSize: validPngBytes.length,
      caption: 'Commit latency CDF comparing Adaptive Pipelining against Raft and PBFT.',
      altText: 'Latency CDF chart.',
      storageKey: 'commit_latency_cdf.png',
      cachedBytes: validPngBytes,
      sectionId: 'results',
      placement: FigurePlacement.columnWidth,
    );
    final fig2 = ProjectFigure(
      id: 'fig_throughput_bench',
      projectId: project.id,
      figureNumber: 2,
      filename: 'throughput_nodes.png',
      mimeType: 'image/png',
      fileSize: validPngBytes.length,
      caption: 'System throughput scaling across 10 to 64 cluster nodes.',
      altText: 'Throughput scaling line chart.',
      storageKey: 'throughput_nodes.png',
      cachedBytes: validPngBytes,
      sectionId: 'results',
      placement: FigurePlacement.fullWidth,
    );
    final fig3 = ProjectFigure(
      id: 'fig_arch_diagram',
      projectId: project.id,
      figureNumber: 3,
      filename: 'architecture_diagram.png',
      mimeType: 'image/png',
      fileSize: validPngBytes.length,
      caption: 'Pipelined consensus state machine and batch scheduler architecture.',
      altText: 'Architecture block diagram.',
      storageKey: 'architecture_diagram.png',
      cachedBytes: validPngBytes,
      sectionId: 'methodology',
      placement: FigurePlacement.columnWidth,
    );

    await repository.saveProjectFigures(project.id, [fig1, fig2, fig3]);
  });

  tearDown(() async {
    await repository.close();
    if (tempDirectory.existsSync()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  group('Responsive Viewport Overflow Assertions (320px, 360px, 375px, 390px, 430px, 768px, 1024px)', () {
    const testWidths = [320.0, 360.0, 375.0, 390.0, 430.0, 768.0, 1024.0];

    for (final width in testWidths) {
      testWidgets('Dashboard renders with 0 overflow at ${width.toInt()}px width', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          ResbudApp(
            repository: repository,
            generationApi: fakeApi,
            exportApi: fakeExportApi,
            fileSaver: fakeFileSaver,
          ),
        );
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 20));
        }

        expect(tester.takeException(), isNull, reason: 'RenderFlex overflow at width $width');
        expect(find.text('Resbud'), findsAtLeastNWidgets(1));
      });

      testWidgets('PaperEditorPage renders with 0 overflow at ${width.toInt()}px width', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: ResbudDesignTokens.darkTheme(),
            home: PaperEditorPage(
              repository: repository,
              generationApi: fakeApi,
              project: project,
              initialVersion: version1,
              initialMode: PaperWorkspaceMode.editor,
              exportApi: fakeExportApi,
              fileSaver: fakeFileSaver,
            ),
          ),
        );
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'RenderFlex overflow in editor at width $width');
        expect(find.byType(PaperEditorPage), findsOneWidget);
      });
    }
  });

  group('Visual QA Screenshot Capture (Screenshots 10 through 21)', () {
    testWidgets('10. Home Dashboard Screenshot', (tester) async {
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
            theme: ResbudDesignTokens.darkTheme(),
            home: ResbudApp(
              repository: repository,
              generationApi: fakeApi,
              exportApi: fakeExportApi,
              fileSaver: fakeFileSaver,
            ),
          ),
        ),
      );
      for (var i = 0; i < 15; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 30));
      }

      await _captureAndSave(tester, repaintKey, '10_home_dashboard.png');
      expect(File('docs/screenshots/10_home_dashboard.png').existsSync(), isTrue);
    });

    testWidgets('11. My Papers Library Screenshot', (tester) async {
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
            theme: ResbudDesignTokens.darkTheme(),
            home: ResbudApp(
              repository: repository,
              generationApi: fakeApi,
              exportApi: fakeExportApi,
              fileSaver: fakeFileSaver,
            ),
          ),
        ),
      );
      for (var i = 0; i < 15; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 30));
      }

      // Tap tab-my-papers
      await tester.tap(find.byKey(const ValueKey('tab-my-papers')));
      await tester.pumpAndSettle();

      await _captureAndSave(tester, repaintKey, '11_my_papers_library.png');
      expect(File('docs/screenshots/11_my_papers_library.png').existsSync(), isTrue);
    });

    testWidgets('12. Project Creation Screenshot', (tester) async {
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
            theme: ResbudDesignTokens.darkTheme(),
            home: ResbudApp(
              repository: repository,
              generationApi: fakeApi,
              exportApi: fakeExportApi,
              fileSaver: fakeFileSaver,
            ),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 20));
      }

      // Tap + New Project FAB
      await tester.tap(find.text('New project'));
      await tester.pumpAndSettle();

      await _captureAndSave(tester, repaintKey, '12_project_creation.png');
      expect(File('docs/screenshots/12_project_creation.png').existsSync(), isTrue);
    });

    testWidgets('13. Research Inputs Screen Screenshot', (tester) async {
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
            theme: ResbudDesignTokens.darkTheme(),
            home: ProjectInputPage(
              repository: repository,
              generationApi: fakeApi,
              project: project,
            ),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      await _captureAndSave(tester, repaintKey, '13_research_inputs.png');
      expect(File('docs/screenshots/13_research_inputs.png').existsSync(), isTrue);
    });

    testWidgets('14. Author Management (1 Author) Screenshot', (tester) async {
      final oneAuthorProject = project.copyWith(
        projectContext: {
          ...project.projectContext,
          'authors': [
            {
              'id': 'auth_1',
              'name': 'Dr. Elena Vance',
              'order': 1,
              'affiliation_ids': ['aff_1'],
              'email': 'evance@mit.edu',
              'is_corresponding': true,
            }
          ],
          'affiliations': [
            {
              'id': 'aff_1',
              'institution': 'Massachusetts Institute of Technology',
              'department': 'CSAIL',
              'city': 'Cambridge',
              'country': 'USA',
            }
          ],
        },
      );

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
            theme: ResbudDesignTokens.darkTheme(),
            home: ProjectInputPage(
              repository: repository,
              generationApi: fakeApi,
              project: oneAuthorProject,
            ),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      await _captureAndSave(tester, repaintKey, '14_author_management_1_author.png');
      expect(File('docs/screenshots/14_author_management_1_author.png').existsSync(), isTrue);
    });

    testWidgets('15. Author Management (5 Authors) Screenshot', (tester) async {
      final fiveAuthorsProject = project.copyWith(
        projectContext: {
          ...project.projectContext,
          'authors': [
            {'id': 'a1', 'name': 'Dr. Elena Vance', 'order': 1, 'affiliation_ids': ['aff_1'], 'email': 'evance@mit.edu', 'is_corresponding': true},
            {'id': 'a2', 'name': 'Prof. Marcus Chen', 'order': 2, 'affiliation_ids': ['aff_1', 'aff_2'], 'email': 'mchen@stanford.edu'},
            {'id': 'a3', 'name': 'Sarah Jenkins', 'order': 3, 'affiliation_ids': ['aff_2'], 'email': 'sjenkins@stanford.edu'},
            {'id': 'a4', 'name': 'Dr. Robert Torres', 'order': 4, 'affiliation_ids': ['aff_3'], 'email': 'rtorres@ox.ac.uk'},
            {'id': 'a5', 'name': 'Prof. Lin Zhao', 'order': 5, 'affiliation_ids': ['aff_1', 'aff_3'], 'email': 'lzhao@tsinghua.edu.cn'},
          ],
          'affiliations': [
            {'id': 'aff_1', 'institution': 'MIT CSAIL', 'city': 'Cambridge', 'country': 'USA'},
            {'id': 'aff_2', 'institution': 'Stanford University', 'city': 'Stanford', 'country': 'USA'},
            {'id': 'aff_3', 'institution': 'University of Oxford', 'city': 'Oxford', 'country': 'UK'},
          ],
        },
      );

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
            theme: ResbudDesignTokens.darkTheme(),
            home: ProjectInputPage(
              repository: repository,
              generationApi: fakeApi,
              project: fiveAuthorsProject,
            ),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      await _captureAndSave(tester, repaintKey, '15_author_management_5_authors.png');
      expect(File('docs/screenshots/15_author_management_5_authors.png').existsSync(), isTrue);
    });

    testWidgets('16. Author Management (8 Authors) Screenshot', (tester) async {
      final eightAuthorsProject = project.copyWith(
        projectContext: {
          ...project.projectContext,
          'authors': [
            {'id': 'a1', 'name': 'Dr. Elena Vance', 'order': 1, 'affiliation_ids': ['aff_1'], 'email': 'evance@mit.edu', 'is_corresponding': true},
            {'id': 'a2', 'name': 'Prof. Marcus Chen', 'order': 2, 'affiliation_ids': ['aff_1', 'aff_2']},
            {'id': 'a3', 'name': 'Sarah Jenkins', 'order': 3, 'affiliation_ids': ['aff_2']},
            {'id': 'a4', 'name': 'Dr. Robert Torres', 'order': 4, 'affiliation_ids': ['aff_3']},
            {'id': 'a5', 'name': 'Prof. Lin Zhao', 'order': 5, 'affiliation_ids': ['aff_1', 'aff_3']},
            {'id': 'a6', 'name': 'Dr. Maya Patel', 'order': 6, 'affiliation_ids': ['aff_4']},
            {'id': 'a7', 'name': 'Kevin O’Connor', 'order': 7, 'affiliation_ids': ['aff_4']},
            {'id': 'a8', 'name': 'Dr. Hans Richter', 'order': 8, 'affiliation_ids': ['aff_2']},
          ],
          'affiliations': [
            {'id': 'aff_1', 'institution': 'MIT CSAIL', 'city': 'Cambridge', 'country': 'USA'},
            {'id': 'aff_2', 'institution': 'Stanford University', 'city': 'Stanford', 'country': 'USA'},
            {'id': 'aff_3', 'institution': 'University of Oxford', 'city': 'Oxford', 'country': 'UK'},
            {'id': 'aff_4', 'institution': 'ETH Zurich', 'city': 'Zurich', 'country': 'Switzerland'},
          ],
        },
      );

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
            theme: ResbudDesignTokens.darkTheme(),
            home: ProjectInputPage(
              repository: repository,
              generationApi: fakeApi,
              project: eightAuthorsProject,
            ),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      await _captureAndSave(tester, repaintKey, '16_author_management_8_authors.png');
      expect(File('docs/screenshots/16_author_management_8_authors.png').existsSync(), isTrue);
    });

    testWidgets('17. Figure Management Screenshot', (tester) async {
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
            theme: ResbudDesignTokens.darkTheme(),
            home: Scaffold(
              body: FigureManagerSheet(
                projectId: project.id,
                repository: repository,
                onFiguresUpdated: () {},
                sections: version1.paper['sections'] != null
                    ? (version1.paper['sections'] as List)
                        .map((s) => PaperSectionPayload.fromJson(Map<String, dynamic>.from(s as Map)))
                        .toList()
                    : const [],
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 20));
      }

      await _captureAndSave(tester, repaintKey, '17_figure_management.png');
      expect(File('docs/screenshots/17_figure_management.png').existsSync(), isTrue);
    });

    testWidgets('18. View & Edit Workspace Screenshot', (tester) async {
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
            theme: ResbudDesignTokens.darkTheme(),
            home: PaperEditorPage(
              repository: repository,
              generationApi: fakeApi,
              project: project,
              initialVersion: version1,
              initialMode: PaperWorkspaceMode.editor,
              exportApi: fakeExportApi,
              fileSaver: fakeFileSaver,
            ),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      await _captureAndSave(tester, repaintKey, '18_view_and_edit_workspace.png');
      expect(File('docs/screenshots/18_view_and_edit_workspace.png').existsSync(), isTrue);
    });

    testWidgets('19. Manuscript Outline Screenshot', (tester) async {
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
            theme: ResbudDesignTokens.darkTheme(),
            home: Scaffold(
              body: ManuscriptOutlineView(
                paper: PaperDraftPayload.fromJson(version1.paper),
                editedSectionIds: const {'methodology'},
                onSelectSection: (_) {},
                onMoveSection: (_, __) {},
                onRenameSection: (_, __) {},
                onAddSection: (_) {},
                onDeleteSection: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _captureAndSave(tester, repaintKey, '19_manuscript_outline.png');
      expect(File('docs/screenshots/19_manuscript_outline.png').existsSync(), isTrue);
    });

    testWidgets('20. DOCX Viewer Academic View Screenshot', (tester) async {
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
            theme: ResbudDesignTokens.lightTheme(),
            home: Scaffold(
              body: DocxDocumentCanvas(
                paper: PaperDraftPayload.fromJson(version1.paper),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _captureAndSave(tester, repaintKey, '20_docx_viewer_academic.png');
      expect(File('docs/screenshots/20_docx_viewer_academic.png').existsSync(), isTrue);
    });

    testWidgets('21. PDF Viewer Academic View Screenshot', (tester) async {
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
            theme: ResbudDesignTokens.lightTheme(),
            home: Scaffold(
              body: PdfViewer(
                paper: PaperDraftPayload.fromJson(version1.paper),
                exportApi: fakeExportApi,
                fileSaver: fakeFileSaver,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _captureAndSave(tester, repaintKey, '21_pdf_viewer_academic.png');
      expect(File('docs/screenshots/21_pdf_viewer_academic.png').existsSync(), isTrue);
    });
  });
}
