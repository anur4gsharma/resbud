import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:resbud_mobile/data/local_project_repository.dart';
import 'package:resbud_mobile/data/project_figure.dart';
import 'package:resbud_mobile/data/project_image_storage.dart';
import 'package:resbud_mobile/features/export/figure_export_resolver.dart';
import 'package:resbud_mobile/features/generation/generation_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late Directory tempDirectory;
  late Directory storageDirectory;
  late LocalProjectRepository repository;
  late String databasePath;
  late ProjectImageStorage imageStorage;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('resbud-image-test-');
    storageDirectory = Directory(p.join(tempDirectory.path, 'storage'));
    await storageDirectory.create();
    databasePath = p.join(tempDirectory.path, 'projects.sqlite');

    imageStorage = FileProjectImageStorage(storageDirectory);
    repository = await LocalProjectRepository.open(
      path: databasePath,
      factory: databaseFactoryFfi,
      imageStorage: imageStorage,
    );
  });

  tearDown(() async {
    await repository.close();
    await tempDirectory.delete(recursive: true);
  });

  Uint8List createSampleImageBytes(int sizeInBytes, [int fillByte = 0x89]) {
    final list = Uint8List(sizeInBytes);
    list.fillRange(0, sizeInBytes, fillByte);
    // Header signature
    list[0] = 0x89;
    list[1] = 0x50;
    list[2] = 0x4e;
    list[3] = 0x47;
    return list;
  }

  group('Resbud Durable Image Persistence & Lifecycle Tests', () {
    test('1. Create text-only project and save without errors', () async {
      final project = await repository.createProject(
        title: 'Text Only Research Study',
        projectContext: {
          'description': 'Pure text research',
          'creation_mode': 'document',
        },
        sourceDraft: 'Standard academic source draft with no images.',
      );

      expect(project.id, isNotEmpty);
      expect(project.title, equals('Text Only Research Study'));

      final loaded = await repository.getProject(project.id);
      expect(loaded, isNotNull);
      expect(loaded!.projectContext['figures'], isNull);
    });

    test('2. Create project with single PNG image and verify persistence', () async {
      final pngBytes = createSampleImageBytes(1024 * 50); // 50 KB

      final project = await repository.createProject(
        title: 'Project with 1 Figure',
        projectContext: {
          'description': 'Single figure project',
          'figures': [
            {
              'id': 'fig_1',
              'name': 'microscopy.png',
              'caption': 'Figure 1: Confocal microscopy analysis',
              'description': 'Fluorescent markers show expression.',
              'bytes': pngBytes,
              'placement': 'column_width',
            }
          ],
        },
        sourceDraft: 'Draft referring to Figure 1.',
      );

      final loaded = await repository.getProject(project.id);
      expect(loaded, isNotNull);
      final rawFigures = loaded!.projectContext['figures'] as List;
      expect(rawFigures.length, equals(1));
      final figMeta = rawFigures.first as Map;
      expect(figMeta['id'], equals('fig_1'));
      expect(figMeta['name'], equals('microscopy.png'));
      expect(figMeta['caption'], equals('Figure 1: Confocal microscopy analysis'));
      // Raw bytes and base64 MUST be stripped from project_context_json to protect CursorWindow
      expect(figMeta['bytes'], isNull);
      expect(figMeta['base64'], isNull);

      // Verify binary bytes can be retrieved from durable storage
      final figures = await repository.listProjectFigures(project.id);
      expect(figures.length, equals(1));
      expect(figures.first.id, equals('fig_1'));
      expect(figures.first.placement, equals(FigurePlacement.columnWidth));

      final retrievedBytes = await repository.getFigureBytes(figures.first.storageKey);
      expect(retrievedBytes, isNotNull);
      expect(retrievedBytes!.length, equals(pngBytes.length));
      expect(retrievedBytes[0], equals(0x89));
    });

    test('3. Create project with multiple images of diverse formats', () async {
      final pngBytes = createSampleImageBytes(1024 * 30, 0x89);
      final jpgBytes = createSampleImageBytes(1024 * 40, 0xff);
      final webpBytes = createSampleImageBytes(1024 * 20, 0x52);

      final project = await repository.createProject(
        title: 'Multi-Image Multi-Format Project',
        projectContext: {
          'description': 'Multi format test',
          'figures': [
            {
              'id': 'fig_1',
              'name': 'diagram.png',
              'caption': 'Figure 1: System Architecture',
              'bytes': pngBytes,
              'placement': 'full_width',
            },
            {
              'id': 'fig_2',
              'name': 'photo.jpg',
              'caption': 'Figure 2: Experimental Apparatus',
              'bytes': jpgBytes,
              'placement': 'column_width',
            },
            {
              'id': 'fig_3',
              'name': 'chart.webp',
              'caption': 'Figure 3: Benchmark Curves',
              'bytes': webpBytes,
              'placement': 'column_width',
            },
          ],
        },
        sourceDraft: 'Comprehensive draft with three figures.',
      );

      final figures = await repository.listProjectFigures(project.id);
      expect(figures.length, equals(3));
      expect(figures[0].placement, equals(FigurePlacement.fullWidth));
      expect(figures[1].placement, equals(FigurePlacement.columnWidth));
      expect(figures[2].placement, equals(FigurePlacement.columnWidth));

      final bytes1 = await repository.getFigureBytes(figures[0].storageKey);
      final bytes2 = await repository.getFigureBytes(figures[1].storageKey);
      final bytes3 = await repository.getFigureBytes(figures[2].storageKey);

      expect(bytes1, isNotNull);
      expect(bytes2, isNotNull);
      expect(bytes3, isNotNull);
      expect(bytes1!.length, equals(pngBytes.length));
      expect(bytes2!.length, equals(jpgBytes.length));
      expect(bytes3!.length, equals(webpBytes.length));
    });

    test('4. Add figures to an already saved text project and save again', () async {
      final initialProject = await repository.createProject(
        title: 'Originally Text Only',
        projectContext: {'description': 'Text only'},
        sourceDraft: 'Initial draft',
      );

      final newImageBytes = createSampleImageBytes(1024 * 45);

      final updatedProject = await repository.updateProjectInputs(
        projectId: initialProject.id,
        title: 'Now Has Figures',
        projectContext: {
          'description': 'Text plus figure',
          'figures': [
            {
              'id': 'fig_1',
              'name': 'new_addition.png',
              'caption': 'Figure 1: Added after creation',
              'bytes': newImageBytes,
              'placement': 'column_width',
            }
          ],
        },
        sourceDraft: 'Draft updated to cite Figure 1.',
      );

      expect(updatedProject.title, equals('Now Has Figures'));
      final figures = await repository.listProjectFigures(initialProject.id);
      expect(figures.length, equals(1));
      expect(figures.first.filename, equals('new_addition.png'));

      final bytes = await repository.getFigureBytes(figures.first.storageKey);
      expect(bytes, isNotNull);
      expect(bytes!.length, equals(newImageBytes.length));
    });

    test('5. Edit captions and layout placement without modifying image binaries', () async {
      final imageBytes = createSampleImageBytes(1024 * 25);
      final project = await repository.createProject(
        title: 'Caption Edit Project',
        projectContext: {
          'figures': [
            {
              'id': 'fig_1',
              'name': 'plot.png',
              'caption': 'Draft Caption',
              'bytes': imageBytes,
              'placement': 'column_width',
            }
          ]
        },
      );

      final initialFigures = await repository.listProjectFigures(project.id);
      expect(initialFigures.first.caption, equals('Draft Caption'));
      expect(initialFigures.first.placement, equals(FigurePlacement.columnWidth));

      // Update metadata (caption and placement) without re-uploading bytes
      await repository.updateProjectInputs(
        projectId: project.id,
        title: 'Caption Edit Project',
        projectContext: {
          'figures': [
            {
              'id': 'fig_1',
              'name': 'plot.png',
              'caption': 'Figure 1: Final Polished Academic Caption',
              'placement': 'full_width',
              'storage_key': initialFigures.first.storageKey,
              'file_size': imageBytes.length,
            }
          ]
        },
        sourceDraft: 'Source draft.',
      );

      final updatedFigures = await repository.listProjectFigures(project.id);
      expect(updatedFigures.first.caption, equals('Figure 1: Final Polished Academic Caption'));
      expect(updatedFigures.first.placement, equals(FigurePlacement.fullWidth));

      // Bytes remain completely intact
      final bytes = await repository.getFigureBytes(updatedFigures.first.storageKey);
      expect(bytes, isNotNull);
      expect(bytes!.length, equals(imageBytes.length));
    });

    test('6. Repository restart simulation: close, reopen and recover image binaries', () async {
      final imageBytes = createSampleImageBytes(1024 * 64);
      final project = await repository.createProject(
        title: 'Persistent Across Restarts',
        projectContext: {
          'figures': [
            {
              'id': 'fig_1',
              'name': 'restart_test.png',
              'caption': 'Figure 1: Durable image across app launch',
              'bytes': imageBytes,
            }
          ]
        },
      );

      // Close the current repository instance
      await repository.close();

      // Open a brand new repository instance pointing to the same database & storage
      final restartedRepo = await LocalProjectRepository.open(
        path: databasePath,
        factory: databaseFactoryFfi,
        imageStorage: FileProjectImageStorage(storageDirectory),
      );

      final loadedProject = await restartedRepo.getProject(project.id);
      expect(loadedProject, isNotNull);
      expect(loadedProject!.title, equals('Persistent Across Restarts'));

      final figures = await restartedRepo.listProjectFigures(project.id);
      expect(figures.length, equals(1));
      expect(figures.first.caption, equals('Figure 1: Durable image across app launch'));

      final loadedBytes = await restartedRepo.getFigureBytes(figures.first.storageKey);
      expect(loadedBytes, isNotNull);
      expect(loadedBytes!.length, equals(imageBytes.length));

      await restartedRepo.close();
    });

    test('7. Delete project removes project metadata and cleans up image storage', () async {
      final imageBytes = createSampleImageBytes(1024 * 20);
      final project = await repository.createProject(
        title: 'Project To Delete',
        projectContext: {
          'figures': [
            {
              'id': 'fig_1',
              'name': 'to_delete.png',
              'caption': 'Figure to clean up',
              'bytes': imageBytes,
            }
          ]
        },
      );

      final figures = await repository.listProjectFigures(project.id);
      expect(figures.length, equals(1));
      final storageKey = figures.first.storageKey;

      final preCheckBytes = await repository.getFigureBytes(storageKey);
      expect(preCheckBytes, isNotNull);

      // Delete project
      await repository.deleteProject(project.id);

      final deletedProject = await repository.getProject(project.id);
      expect(deletedProject, isNull);

      final deletedFigures = await repository.listProjectFigures(project.id);
      expect(deletedFigures, isEmpty);

      final postCheckBytes = await repository.getFigureBytes(storageKey);
      expect(postCheckBytes, isNull);
    });

    test('8. Figure export resolution: substitute (fig_1) markers with embedded data URIs', () async {
      final imageBytes = createSampleImageBytes(1024 * 10);
      final project = await repository.createProject(
        title: 'Export Resolution Project',
        projectContext: {
          'figures': [
            {
              'id': 'fig_1',
              'name': 'convergence.png',
              'caption': 'Figure 1: Rate of Convergence',
              'bytes': imageBytes,
              'placement': 'full_width',
            }
          ]
        },
      );

      const paper = PaperDraftPayload(
        schemaVersion: 1,
        title: 'Resolution Test',
        abstractText: 'Testing figure substitution.',
        keywords: const ['test', 'figures'],
        reviewWarnings: const [],
        sections: [
          const PaperSectionPayload(
            id: 'sec_results',
            heading: 'Results',
            content: 'As shown in the empirical evaluation below:\n\n![Figure 1: Rate of Convergence](fig_1)\n\nWe observe rapid convergence.',
            state: 'complete',
          )
        ],
        references: const [],
      );

      final resolved = await resolveFiguresForExport(
        paper: paper,
        repository: repository,
        projectId: project.id,
      );

      final sectionContent = resolved.sections.first.content;
      // Should not contain the unresolved (fig_1) marker
      expect(sectionContent.contains('(fig_1)'), isFalse);
      // Should contain data URI and placement metadata
      expect(sectionContent.contains('data:image/png;base64,'), isTrue);
      expect(sectionContent.contains('#placement=full_width'), isTrue);
    });
  });
}
