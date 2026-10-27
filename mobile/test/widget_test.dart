import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:resbud_mobile/data/local_project_repository.dart';
import 'package:resbud_mobile/main.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory tempDirectory;
  late LocalProjectRepository repository;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'resbud-widget-test-',
    );
    repository = await LocalProjectRepository.open(
      path: p.join(tempDirectory.path, 'projects.sqlite'),
      factory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await repository.close();
    await tempDirectory.delete(recursive: true);
  });

  testWidgets('shows the empty local project state and backup disclosure', (
    tester,
  ) async {
    await tester.pumpWidget(ResbudApp(repository: repository));
    await _pumpUntilVisible(
      tester,
      find.text('Your projects will appear here.'),
    );

    expect(find.text('Resbud'), findsOneWidget);
    expect(find.text('Your projects will appear here.'), findsOneWidget);
    expect(find.textContaining('There is no cloud backup'), findsOneWidget);
  });
}

Future<void> _pumpUntilVisible(WidgetTester tester, Finder finder) async {
  for (var frame = 0; frame < 30 && finder.evaluate().isEmpty; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsAtLeastNWidgets(1));
}
