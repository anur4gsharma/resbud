import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:resbud_mobile/data/local_project_repository.dart';
import 'package:resbud_mobile/features/generation/generation_models.dart';
import 'package:resbud_mobile/features/project_input/project_input_page.dart';

import 'helpers/fake_generation_api.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory tempDirectory;
  late LocalProjectRepository repository;
  late FakeGenerationApi fakeApi;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('resbud-upload-test-');
    repository = await LocalProjectRepository.open(
      path: p.join(tempDirectory.path, 'projects.sqlite'),
      factory: databaseFactoryFfi,
    );
    fakeApi = FakeGenerationApi();
  });

  tearDown(() async {
    await repository.close();
    await tempDirectory.delete(recursive: true);
  });

  Future<void> pumpDocInput(
    WidgetTester tester, {
    required LocalProject project,
    SourcePicker? sourcePicker,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectInputPage(
          repository: repository,
          generationApi: fakeApi,
          project: project,
          sourcePicker: sourcePicker,
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('upload-first hero renders all supported format badges and upload CTA', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final project = await tester.runAsync(
      () => repository.createProject(
        title: 'Quantum Synthesis',
        projectContext: const {'creation_mode': 'document'},
      ),
    );

    await pumpDocInput(tester, project: project!);

    // Hero title & format badges
    expect(find.text('Upload Research Material'), findsOneWidget);
    expect(find.text('.txt'), findsOneWidget);
    expect(find.text('.md'), findsOneWidget);
    expect(find.text('.docx'), findsOneWidget);
    expect(find.text('.pdf'), findsOneWidget);

    // Primary upload button
    expect(find.byKey(const ValueKey('button-choose-doc-file')), findsOneWidget);
    expect(find.text('Choose file'), findsOneWidget);
  });

  testWidgets('handles empty file upload with informative error message', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final project = await tester.runAsync(
      () => repository.createProject(
        title: 'Empty File Test',
        projectContext: const {'creation_mode': 'document'},
      ),
    );

    await pumpDocInput(
      tester,
      project: project!,
      sourcePicker: () async => (
        name: 'empty.txt',
        bytes: Uint8List(0),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('button-choose-doc-file')));
    await tester.pumpAndSettle();

    expect(
      find.text('The uploaded file is empty. Please provide research material.'),
      findsOneWidget,
    );
  });

  testWidgets('complete source material generates paper directly without interruption', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const completeNotes = '''
# Equivariant Graph Decoders for Topological Quantum Codes
We present a deep learning decoding methodology using equivariant message passing.
We benchmark against minimum-weight perfect matching on surface codes distance 3, 5, and 7.
Under phenomenological noise model with 0.1% physical error rate, logical error rate is reduced by 42%.
''';

    final project = await tester.runAsync(
      () => repository.createProject(
        title: 'Equivariant Decoders',
        projectContext: const {'creation_mode': 'document'},
        sourceDraft: completeNotes,
      ),
    );

    await pumpDocInput(tester, project: project!);

    // Click Generate Paper with AI
    final genBtn = find.byKey(const ValueKey('button-generate-paper-docmode'));
    await tester.tap(genBtn);
    await tester.pump();
    await tester.pumpAndSettle();

    // Directly reaches preview dialog without blocking
    expect(find.text('Review generated draft'), findsOneWidget);
    expect(fakeApi.callCount, 1);
  });

  testWidgets('conditional workflow opens when AI identifies critical warnings and questions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Provide mock analysis response with warnings and clarification questions
    fakeApi.nextAnalysisResult = const ResearchAnalysisResponsePayload(
      inferredTitle: 'Transformer Optimization Study',
      inferredField: 'Machine Learning',
      inferredQuestion: 'How does attention scaling impact latency?',
      inferredObjectives: ['Analyze latency', 'Formulate complexity'],
      suggestedOutline: [
        DynamicOutlineSectionPayload(
          id: 'sec_arch',
          heading: '1. Attention Architecture & Complexity',
          rationale: 'Formalizes transformer attention equations.',
        ),
        DynamicOutlineSectionPayload(
          id: 'sec_eval',
          heading: '2. Latency Benchmarks & Scaling',
          rationale: 'Evaluates empirical throughput.',
        ),
      ],
      questions: [
        ClarificationQuestionPayload(
          id: 'q_dataset_split',
          question: 'What was the exact train-validation split and dataset size?',
          whyNeeded: 'Dataset size is essential for empirical verification.',
          isEssential: true,
          fieldKey: 'dataset_or_materials',
        ),
      ],
      warnings: [
        AnalysisWarningPayload(
          code: 'INPUT_CONFLICT',
          severity: 'critical',
          message: 'Contradictory accuracy values: 82% vs 91%.',
          whyItMatters: 'Conflicting values undermine peer review reproducibility.',
          potentialImpact: 'Generated paper will highlight contradictory claims.',
        ),
      ],
      canProceedDirectly: false,
      requiresClarification: true,
    );

    final project = await tester.runAsync(
      () => repository.createProject(
        title: 'Transformer Optimization',
        projectContext: const {'creation_mode': 'document'},
        sourceDraft: 'Preliminary notes on transformer attention latency.',
      ),
    );

    await pumpDocInput(tester, project: project!);

    // Tap Generate: AI analysis triggers conditional additional information interface
    final genBtn = find.byKey(const ValueKey('button-generate-paper-docmode'));
    await tester.tap(genBtn);
    await tester.pump();
    await tester.pumpAndSettle();

    // Verify AI Additional Information panel is now visible
    expect(find.text('AI Clarification & Quality Review Required'), findsOneWidget);
    expect(find.text('AI-Proposed Dynamic Section Outline:'), findsOneWidget);
    expect(find.text('1. Attention Architecture & Complexity'), findsOneWidget);

    // Verify Warning with why it matters & potential impact
    expect(find.text('Contradictory accuracy values: 82% vs 91%.'), findsOneWidget);
    expect(
      find.textContaining('Conflicting values undermine peer review reproducibility.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Generated paper will highlight contradictory claims.'),
      findsOneWidget,
    );

    // Verify dynamic clarification question
    expect(
      find.text('What was the exact train-validation split and dataset size?'),
      findsOneWidget,
    );
    expect(find.text('REQUIRED'), findsOneWidget);

    // Answer clarification question
    final clarificationInput = find.byKey(
      const ValueKey('clarification-input-q_dataset_split'),
    );
    expect(clarificationInput, findsOneWidget);
    await tester.enterText(clarificationInput, 'Trained on 100k samples with 80/20 train/validation split.');
    await tester.pumpAndSettle();

    // Tap Confirm Clarifications & Generate Draft
    final confirmBtn = find.byKey(
      const ValueKey('button-confirm-clarifications-generate'),
    );
    expect(confirmBtn, findsOneWidget);
    await tester.tap(confirmBtn);
    await tester.pump();
    await tester.pumpAndSettle();

    // Generation proceeds and opens review dialog
    expect(find.text('Review generated draft'), findsOneWidget);
    expect(fakeApi.callCount, 1);
    expect(
      fakeApi.lastRequest!.sourceDraft,
      contains('Trained on 100k samples with 80/20 train/validation split.'),
    );
  });
}
