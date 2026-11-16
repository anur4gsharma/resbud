import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:resbud_mobile/data/local_project_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late Directory tempDirectory;
  late LocalProjectRepository repository;
  late String databasePath;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('resbud-repro-test-');
    databasePath = p.join(tempDirectory.path, 'projects.sqlite');
    repository = await LocalProjectRepository.open(
      path: databasePath,
      factory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await repository.close();
    await tempDirectory.delete(recursive: true);
  });

  test('saving project with large attached figure bytes and base64', () async {
    // 3 MiB raw image
    final sampleBytes = Uint8List(3 * 1024 * 1024);
    for (var i = 0; i < sampleBytes.length; i++) {
      sampleBytes[i] = i % 256;
    }

    try {
      final project = await repository.createProject(
        title: 'Project With Large Figure',
        projectContext: {
          'description': 'Test project with high-resolution research figures',
          'creation_mode': 'document',
          'figures': [
            {
              'id': 'fig_1',
              'name': 'high_res_electron_microscopy.png',
              'caption': 'Figure 1: High Resolution Electron Microscopy',
              'description': 'Empirical visual analysis.',
              'base64': 'data:image/png;base64,AAAA',
              'bytes': sampleBytes,
            }
          ],
        },
        sourceDraft: 'Sample draft with figure.',
      );

      expect(project.id, isNotEmpty);

      // Try updateProjectInputs
      final updated = await repository.updateProjectInputs(
        projectId: project.id,
        title: 'Project With Large Figure (Updated)',
        projectContext: {
          'description': 'Test project with high-resolution research figures',
          'creation_mode': 'document',
          'figures': [
            {
              'id': 'fig_1',
              'name': 'high_res_electron_microscopy.png',
              'caption': 'Figure 1: High Resolution Electron Microscopy',
              'description': 'Empirical visual analysis.',
              'base64': 'data:image/png;base64,AAAA',
              'bytes': sampleBytes,
            }
          ],
        },
        sourceDraft: 'Sample draft with figure (updated).',
      );
      expect(updated.title, contains('Updated'));
    } catch (e) {
      rethrow;
    }
  });
}
