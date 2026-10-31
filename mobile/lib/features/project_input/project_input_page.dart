import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/local_project_repository.dart';
import '../export/docx_export_client.dart';
import '../export/docx_file_saver.dart';
import '../generation/generation_api_client.dart';
import '../generation/generation_models.dart';
import '../paper_editor/paper_editor_page.dart';
import '../../import/source_document_importer.dart';
import '../../import/document_project_extractor.dart';
import '../../shared/design_tokens.dart';

typedef PickedSource = ({String name, Uint8List bytes});
typedef SourcePicker = Future<PickedSource?> Function();

enum GenerationPhase { ready, validating, generating, success, recoverableFailure }

enum _GenerationReviewAction { keepEditing, savePaper }

const _statusChoices = <String, List<String>>{
  'methodology_status': [
    'provided',
    'not_available',
    'not_applicable',
    'unknown',
  ],
  'dataset_or_materials_status': [
    'provided',
    'not_available',
    'not_applicable',
    'unknown',
  ],
  'results_status': [
    'provided',
    'not_collected',
    'not_available',
    'not_applicable',
    'unknown',
  ],
  'limitations_status': [
    'provided',
    'not_identified',
    'not_available',
    'not_applicable',
    'unknown',
  ],
};

const _statusDetails = <String, String>{
  'methodology_status': 'methodology',
  'dataset_or_materials_status': 'dataset_or_materials',
  'results_status': 'results',
  'limitations_status': 'limitations',
};

const _statusLabels = <String, String>{
  'provided': 'Provided',
  'not_collected': 'Not collected',
  'not_identified': 'Not identified',
  'not_available': 'Not available',
  'not_applicable': 'Not applicable',
  'unknown': 'Unknown / not supplied yet',
};

const _baseSections = <String>[
  'abstract',
  'introduction',
  'methodology',
  'results',
  'discussion',
  'conclusion',
  'references',
];

class ProjectInputPage extends StatefulWidget {
  const ProjectInputPage({
    super.key,
    required this.repository,
    required this.generationApi,
    required this.project,
    this.sourcePicker,
    this.exportApi,
    this.fileSaver,
  });

  final LocalProjectRepository repository;
  final PaperGenerationApi generationApi;
  final LocalProject project;
  final SourcePicker? sourcePicker;
  final PaperExportApi? exportApi;
  final DocxFileSaver? fileSaver;

  @override
  State<ProjectInputPage> createState() => _ProjectInputPageState();
}

class _ProjectInputPageState extends State<ProjectInputPage> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  late final Map<String, TextEditingController> _controllers;
  late final Map<String, String> _statuses;
  late Future<List<PaperVersion>> _versions;
  late String _initialFingerprint;
  late final TextEditingController _customSectionsController;
  int _targetWordCount = 1500;
  String _citationStyle = 'user_supplied';
  List<String> _desiredSections = List.of(_baseSections);
  bool _saving = false;
  bool _importing = false;
  bool _allowPop = false;
  GenerationPhase _generationPhase = GenerationPhase.ready;
  GenerationResult? _generationResult;
  GenerationApiFailure? _generationFailure;
  String? _importMessage;
  String? _importedSummaryDetails;
  bool _importError = false;
  String? _sectionError;
  final Map<String, String> _fieldErrors = {};
  bool _documentMode = false;
  ResearchAnalysisResponsePayload? _analysisResponse;
  bool _showAdditionalInfoInterface = false;
  bool _isAnalyzing = false;
  final Map<String, TextEditingController> _clarificationControllers = {};
  bool _clarificationsConfirmed = false;
  final List<({String name, int size})> _attachedFiles = [];

  @override
  void initState() {
    super.initState();
    final context = widget.project.projectContext;
    _versions = widget.repository.listPaperVersions(widget.project.id);
    final creationMode = context['creation_mode'];
    _documentMode = creationMode == 'document' ||
        (context['description'] != null &&
            (context['description'] as String).isNotEmpty &&
            _stringValue(context['research_question'], '').isEmpty);
    _controllers = {
      for (final key in [
        'title',
        'description',
        'research_field',
        'research_question',
        'objectives',
        'claimed_contribution',
        'methodology',
        'dataset_or_materials',
        'results',
        'limitations',
        'references',
        'source_draft',
      ])
        key: TextEditingController(
          text: _initialValue(key, context, widget.project),
        ),
    };
    _statuses = {
      for (final key in _statusChoices.keys)
        key: _stringValue(context[key], 'unknown'),
    };
    final preferences = context['preferences'];
    if (preferences is Map) {
      final count = preferences['target_word_count'];
      if (count is int && count >= 500 && count <= 8000) {
        _targetWordCount = count;
      }
      final citation = preferences['citation_style'];
      if (citation is String &&
          ['user_supplied', 'apa_7', 'ieee', 'other'].contains(citation)) {
        _citationStyle = citation;
      }
      final sections = preferences['desired_sections'];
      if (sections is List && sections.every((value) => value is String)) {
        _desiredSections = List<String>.from(sections);
      }
    }
    _customSectionsController = TextEditingController(
      text: _desiredSections
          .where((section) => !_baseSections.contains(section))
          .join('\n'),
    );
    _initialFingerprint = _fingerprint();
  }

  static String _initialValue(
    String key,
    Map<String, Object?> context,
    LocalProject project,
  ) {
    if (key == 'title') return _stringValue(context[key], project.title);
    if (key == 'source_draft') return project.sourceDraft;
    if (key == 'description') return _stringValue(context[key], '');
    final value = context[key];
    if (value is List) {
      if (key == 'references') {
        return value
            .whereType<Map<Object?, Object?>>()
            .map((reference) => reference['text'])
            .whereType<String>()
            .join('\n');
      }
      return value.whereType<String>().join('\n');
    }
    return _stringValue(value, '');
  }

  static String _stringValue(Object? value, String fallback) =>
      value is String ? value : fallback;

  @override
  void dispose() {
    _scrollController.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final controller in _clarificationControllers.values) {
      controller.dispose();
    }
    _customSectionsController.dispose();
    super.dispose();
  }

  String _fingerprint() => [
    for (final entry in _controllers.entries)
      '${entry.key}:${entry.value.text}',
    for (final entry in _statuses.entries) '${entry.key}:${entry.value}',
    '$_targetWordCount',
    _citationStyle,
    _desiredSections.join(','),
    _customSectionsController.text,
  ].join('|');

  bool get _isDirty => _fingerprint() != _initialFingerprint;

  List<String> get _requestedSections => [
    ..._desiredSections.where(_baseSections.contains),
    ..._nonblankLines(_customSectionsController.text),
  ];

  Map<String, Object?> _buildContext() {
    final title = _controllers['title']!.text.trim();
    final desc = _controllers['description']?.text.trim() ?? '';

    final researchQuestion = _documentMode && _controllers['research_question']!.text.trim().isEmpty
        ? (desc.isNotEmpty ? desc : 'How can the research in "$title" be systematically formalized and evaluated?')
        : _controllers['research_question']!.text.trim();

    final researchField = _documentMode && _controllers['research_field']!.text.trim().isEmpty
        ? 'Scientific & Academic Research'
        : _controllers['research_field']!.text.trim();

    final objectives = _documentMode && _nonblankLines(_controllers['objectives']!.text).isEmpty
        ? [
            if (desc.isNotEmpty) desc,
            'Synthesize and evaluate the research claims presented in the source document.',
          ]
        : _nonblankLines(_controllers['objectives']!.text);

    final claimedContribution = _documentMode && _controllers['claimed_contribution']!.text.trim().isEmpty
        ? desc
        : _controllers['claimed_contribution']!.text.trim();

    final statusEntries = <String, Object?>{};
    for (final entry in _statusDetails.entries) {
      final currentStatus = _statuses[entry.key];
      final statusVal = (_documentMode && (currentStatus == null || currentStatus == 'unknown'))
          ? 'not_available'
          : currentStatus;
      statusEntries[entry.key] = statusVal;
      final textVal = _controllers[entry.value]!.text.trim();
      statusEntries[entry.value] = textVal.isEmpty ? null : textVal;
    }

    return {
      'title': title,
      'description': desc,
      'creation_mode': _documentMode ? 'document' : 'manual',
      'research_field': researchField,
      'research_question': researchQuestion,
      'objectives': objectives,
      'claimed_contribution': claimedContribution,
      ...statusEntries,
      'references': [
        for (
          var index = 0;
          index < _nonblankLines(_controllers['references']!.text).length;
          index++
        )
          {
            'id': 'ref_${index + 1}',
            'text': _nonblankLines(_controllers['references']!.text)[index],
          },
      ],
      'preferences': {
        'target_word_count': _targetWordCount,
        'desired_sections': _requestedSections,
        'citation_style': _citationStyle,
      },
    };
  }

  List<String> _nonblankLines(String value) => value
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  String? _validateContext() {
    _fieldErrors.clear();
    _sectionError = null;

    if (_documentMode) {
      if (_controllers['source_draft']!.text.trim().isEmpty) {
        _fieldErrors['source_draft'] = 'Please upload a .txt, .md, .docx, or .pdf file.';
      }
      if (_controllers['title']!.text.trim().isEmpty && _controllers['source_draft']!.text.trim().isNotEmpty) {
        _controllers['title']!.text = _analysisResponse?.inferredTitle.isNotEmpty == true
            ? _analysisResponse!.inferredTitle
            : 'Scientific Research Study';
      }
      if ((_controllers['description']?.text.trim() ?? '').isEmpty && _controllers['source_draft']!.text.trim().isNotEmpty) {
        _controllers['description']!.text = 'Synthesize and evaluate the research claims presented in the source document.';
      }
      _formKey.currentState?.validate();
      if (_fieldErrors.isNotEmpty) {
        return 'Complete the highlighted fields.';
      }
      return null;
    }

    const requiredInputs = <String, String>{
      'title': 'Working title',
      'research_field': 'Research field',
      'research_question': 'Research question',
      'objectives': 'Objectives',
      'source_draft': 'Existing draft',
    };
    for (final entry in requiredInputs.entries) {
      if (_controllers[entry.key]!.text.trim().isEmpty) {
        _fieldErrors[entry.key] = '${entry.value} is required.';
      }
    }
    for (final entry in _statusDetails.entries) {
      if (_statuses[entry.key] == 'provided' &&
          _controllers[entry.value]!.text.trim().isEmpty) {
        _fieldErrors[entry.value] =
            '${_label(entry.value)} details are required when status is provided.';
      }
    }
    _formKey.currentState!.validate();
    if (_fieldErrors.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
      return 'Complete the highlighted fields.';
    }
    final refs = _nonblankLines(_controllers['references']!.text);
    if (refs.length > 50 || refs.any((text) => text.length > 2000)) {
      _fieldErrors['references'] =
          'Use at most 50 references, each up to 2,000 characters.';
      return 'References must have at most 50 entries, each up to 2,000 characters.';
    }
    final objectives = _nonblankLines(_controllers['objectives']!.text);
    if (objectives.isEmpty ||
        objectives.length > 20 ||
        objectives.any((text) => text.length > 1000)) {
      _fieldErrors['objectives'] =
          'Use 1–20 objectives, each up to 1,000 characters.';
      return 'Add 1–20 objectives, each up to 1,000 characters.';
    }
    final sections = _requestedSections;
    if (sections.length > 15 || sections.toSet().length != sections.length) {
      _sectionError = 'Choose up to 15 unique sections.';
      return 'Choose up to 15 unique sections.';
    }
    if (sections.any(
      (section) => !RegExp(r'^[a-z][a-z0-9_]{1,39}$').hasMatch(section),
    )) {
      _sectionError =
          'IDs must start with a lowercase letter and contain only lowercase letters, numbers, or underscores.';
      return 'Section IDs must start with a lowercase letter and use lowercase letters, numbers, or underscores.';
    }
    return null;
  }

  List<Widget> _buildDocumentModeWidgets() {
    final hasContent = _controllers['source_draft']!.text.trim().isNotEmpty;
    final charCount = _controllers['source_draft']!.text.length;

    return [
      // 1. Primary Upload-First Hero Card
      Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: hasContent ? Colors.green.shade300 : Theme.of(context).colorScheme.outlineVariant,
            width: hasContent ? 1.5 : 1.0,
          ),
        ),
        color: hasContent ? Colors.green.shade50.withValues(alpha: 0.3) : Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: hasContent ? Colors.green.shade100 : Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      hasContent ? Icons.check_circle_outline : Icons.upload_file_outlined,
                      color: hasContent ? Colors.green.shade800 : Colors.indigo.shade700,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Upload Research Material',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Upload notes, experimental results, manuscripts, or drafts. The AI will extract content, analyze research quality, and synthesize the paper.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Supported format chips
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final ext in ['.txt', '.md', '.docx', '.pdf'])
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        ext,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  FilledButton.tonalIcon(
                    key: const ValueKey('button-choose-doc-file'),
                    onPressed: _importing ? null : () => _importFiles(),
                    icon: _importing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.folder_open),
                    label: Text(
                      _importing
                          ? 'Extracting…'
                          : (hasContent ? 'Change file' : 'Choose file'),
                    ),
                  ),
                  if (hasContent) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _controllers['source_draft']!.clear();
                          _attachedFiles.clear();
                          _analysisResponse = null;
                          _showAdditionalInfoInterface = false;
                        });
                      },
                      icon: const Icon(Icons.clear, size: 16),
                      label: const Text('Clear'),
                    ),
                  ],
                ],
              ),
              if (_importMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _importError ? Colors.red.shade50 : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _importError ? Colors.red.shade300 : Colors.green.shade300,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _importError ? Icons.error_outline : Icons.check_circle_outline,
                        size: 16,
                        color: _importError ? Colors.red.shade900 : Colors.green.shade900,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _importMessage!,
                          style: TextStyle(
                            fontSize: 12,
                            color: _importError ? Colors.red.shade900 : Colors.green.shade900,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_fieldErrors.containsKey('source_draft')) ...[
                const SizedBox(height: 8),
                Text(
                  _fieldErrors['source_draft']!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
              if (hasContent) ...[
                const SizedBox(height: 16),
                Text(
                  'Document attached ($charCount characters)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 140,
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _controllers['source_draft']!.text,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      // 2. Paper brief details
      Text(
        'Project brief',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 16),
      _textField(
        'title',
        'Working title',
        maxLength: 300,
        requiredField: false,
      ),
      _textField(
        'description',
        'Paper description',
        maxLength: 4000,
        minLines: 3,
        requiredField: false,
        helper: '(Optional) What is this paper about? Summarize the scope, problem, and focus.',
        hintText: 'e.g. This research develops equivariant neural graph decoders for surface code quantum error correction...',
      ),
      const SizedBox(height: 16),
      // 3. Conditional AI-Triggered Additional Information
      if (_analysisResponse != null || _showAdditionalInfoInterface) ...[
        _buildAdditionalInformationCard(),
        const SizedBox(height: 16),
      ],
      // 4. Advanced: Specific Research Parameters (Optional Expandable)
      Card(
        child: ExpansionTile(
          key: const ValueKey('expansion-specific-parameters'),
          leading: const Icon(Icons.tune),
          title: const Text('Specific Research Parameters (Optional)'),
          subtitle: const Text('Declare status and explicit methodology, dataset, and results details.'),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  for (final key in _statusChoices.keys) _statusGroup(key),
                  _textField('methodology', 'Methodology notes', maxLength: 20000, minLines: 2),
                  _textField('dataset_or_materials', 'Dataset / Materials notes', maxLength: 20000, minLines: 2),
                  _textField('results', 'Results notes', maxLength: 20000, minLines: 2),
                  _textField('limitations', 'Limitations notes', maxLength: 20000, minLines: 2),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      // 5. Paper preferences
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paper preferences',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text('Target word count: $_targetWordCount words'),
              Slider(
                value: _targetWordCount.toDouble(),
                min: 500,
                max: 8000,
                divisions: 15,
                label: '$_targetWordCount words',
                onChanged: (value) => setState(() => _targetWordCount = value.round()),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _citationStyle,
                decoration: const InputDecoration(labelText: 'Citation style'),
                items: const [
                  DropdownMenuItem(value: 'user_supplied', child: Text('Authoritative user citations')),
                  DropdownMenuItem(value: 'ieee', child: Text('IEEE style [1]')),
                  DropdownMenuItem(value: 'apa_7', child: Text('APA 7th edition')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _citationStyle = val);
                },
              ),
            ],
          ),
        ),
      ),
      if (_generationFailure != null)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _generationFailure!.userMessage,
                  style: TextStyle(color: Colors.red.shade900),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _retryGeneration,
                  child: const Text('Retry generation'),
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 20),
      OutlinedButton.icon(
        key: const ValueKey('button-review-before-generation-docmode'),
        onPressed: _showSummary,
        icon: const Icon(Icons.fact_check_outlined),
        label: const Text('Review before generation'),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          key: const ValueKey('button-generate-paper-docmode'),
          onPressed: (_generationPhase == GenerationPhase.generating || _isAnalyzing)
              ? null
              : _generate,
          icon: (_generationPhase == GenerationPhase.generating || _isAnalyzing)
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.auto_awesome),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              _isAnalyzing
                  ? 'Analyzing research material…'
                  : (_generationPhase == GenerationPhase.generating
                      ? 'Generating paper draft…'
                      : 'Generate Paper with AI'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
      const SizedBox(height: 32),
    ];
  }

  Widget _buildAdditionalInformationCard() {
    final analysis = _analysisResponse;
    if (analysis == null) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: analysis.requiresClarification ? Colors.amber.shade600 : Colors.blue.shade300,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  analysis.requiresClarification ? Icons.announcement_outlined : Icons.insights_outlined,
                  color: analysis.requiresClarification ? Colors.amber.shade900 : Colors.blue.shade900,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    analysis.requiresClarification
                        ? 'AI Clarification & Quality Review Required'
                        : 'AI Research Analysis & Outline',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: analysis.requiresClarification ? Colors.amber.shade900 : Colors.blue.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (analysis.inferredTitle.isNotEmpty) ...[
              Text(
                'Inferred Topic: ${analysis.inferredTitle}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 4),
            ],
            if (analysis.inferredField.isNotEmpty) ...[
              Text(
                'Academic Field: ${analysis.inferredField}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
              ),
              const SizedBox(height: 12),
            ],
            if (analysis.suggestedOutline.isNotEmpty) ...[
              const Text(
                'AI-Proposed Dynamic Section Outline:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    for (final sec in analysis.suggestedOutline)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.arrow_right, size: 18, color: Colors.indigo),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    sec.heading,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                  ),
                                  if (sec.rationale.isNotEmpty)
                                    Text(
                                      sec.rationale,
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (analysis.warnings.isNotEmpty) ...[
              Text(
                'Research Integrity & Consistency Warnings:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.amber.shade900,
                ),
              ),
              const SizedBox(height: 6),
              for (final w in analysis.warnings)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: w.severity == 'critical' ? Colors.red.shade50 : Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: w.severity == 'critical' ? Colors.red.shade300 : Colors.amber.shade300,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            w.severity == 'critical' ? Icons.error_outline : Icons.warning_amber,
                            size: 16,
                            color: w.severity == 'critical' ? Colors.red.shade900 : Colors.amber.shade900,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              w.message,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: w.severity == 'critical' ? Colors.red.shade900 : Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Why this matters: ${w.whyItMatters}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Potential impact: ${w.potentialImpact}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
            ],
            if (analysis.clarificationQuestions.isNotEmpty) ...[
              Text(
                'AI Clarification Requests:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.blue.shade900,
                ),
              ),
              const SizedBox(height: 6),
              for (final q in analysis.clarificationQuestions)
                Builder(
                  builder: (context) {
                    _clarificationControllers.putIfAbsent(q.id, () => TextEditingController());
                    final controller = _clarificationControllers[q.id]!;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: q.isEssential ? Colors.red.shade100 : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  q.isEssential ? 'REQUIRED' : 'OPTIONAL',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: q.isEssential ? Colors.red.shade900 : Colors.grey.shade800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  q.question,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Reason: ${q.whyNeeded}',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            key: ValueKey('clarification-input-${q.id}'),
                            controller: controller,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              hintText: 'Type clarification or empirical details here...',
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.all(8),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('button-confirm-clarifications-generate'),
                onPressed: () {
                  setState(() => _clarificationsConfirmed = true);
                  _generate();
                },
                icon: const Icon(Icons.check),
                label: const Text('Confirm Clarifications & Generate Draft'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _save({bool showMessage = true}) async {
    final error = _validateContext();
    if (error != null) {
      setState(() {});
      if (showMessage) _showMessage(error, isError: true);
      return false;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.updateProjectInputs(
        projectId: widget.project.id,
        title: _controllers['title']!.text,
        projectContext: _buildContext(),
        sourceDraft: _controllers['source_draft']!.text,
      );
      if (!mounted) return false;
      setState(() {
        _saving = false;
        _initialFingerprint = _fingerprint();
      });
      if (showMessage) _showMessage('Project saved on this device.');
      return true;
    } on Object {
      if (!mounted) return false;
      setState(() => _saving = false);
      _showMessage(
        'The project could not be saved. Your last saved copy remains available.',
        isError: true,
      );
      return false;
    }
  }

  Future<void> _generate() async {
    if (_generationPhase == GenerationPhase.generating || _isAnalyzing) return;
    setState(() {
      _generationPhase = GenerationPhase.validating;
      _generationFailure = null;
    });
    final validationError = _validateContext();
    if (validationError != null) {
      setState(() => _generationPhase = GenerationPhase.ready);
      setState(() {});
      _showMessage(validationError, isError: true);
      return;
    }

    // Dynamic research analysis & quality check in document mode
    if (_documentMode && !_clarificationsConfirmed && !_showAdditionalInfoInterface) {
      setState(() => _isAnalyzing = true);
      try {
        final analysis = await widget.generationApi.analyzeResearch(
          ResearchAnalysisRequestPayload(
            sourceMaterial: _controllers['source_draft']!.text,
            titleHint: _controllers['title']!.text.trim().isNotEmpty
                ? _controllers['title']!.text.trim()
                : null,
            userGuidance: (_controllers['description']?.text.trim() ?? '').isNotEmpty
                ? _controllers['description']!.text.trim()
                : null,
          ),
        );
        _analysisResponse = analysis;
        _isAnalyzing = false;

        if ((_controllers['title']!.text.trim().isEmpty ||
                _controllers['title']!.text.trim() == 'Scientific Research Study') &&
            analysis.inferredTitle.isNotEmpty) {
          _controllers['title']!.text = analysis.inferredTitle;
        }

        if (analysis.requiresClarification) {
          setState(() {
            _showAdditionalInfoInterface = true;
            _generationPhase = GenerationPhase.ready;
          });
          _showMessage(
            'The AI identified essential clarification questions or warnings. Please review below.',
            isError: false,
          );
          return;
        }
      } catch (_) {
        _isAnalyzing = false;
      }
    }

    // Merge any clarification answers
    final clarificationsBuf = StringBuffer();
    for (final entry in _clarificationControllers.entries) {
      final answer = entry.value.text.trim();
      if (answer.isNotEmpty) {
        final q = _analysisResponse?.questions
            .cast<ClarificationQuestionPayload?>()
            .firstWhere(
              (ClarificationQuestionPayload? item) => item?.id == entry.key,
              orElse: () => null,
            );
        clarificationsBuf.writeln('Clarification on "${q?.question ?? entry.key}":');
        clarificationsBuf.writeln(answer);
        clarificationsBuf.writeln();
      }
    }
    var effectiveDraft = _controllers['source_draft']!.text;
    if (clarificationsBuf.isNotEmpty) {
      effectiveDraft = '$effectiveDraft\n\n=== RESEARCHER CLARIFICATIONS ===\n$clarificationsBuf';
    }

    late final GenerationRequest request;
    try {
      request = GenerationRequest.fromInputs(
        project: _buildContext(),
        sourceDraft: effectiveDraft,
      );
    } on FormatException catch (error) {
      setState(() => _generationPhase = GenerationPhase.ready);
      _showMessage(error.message, isError: true);
      return;
    }

    setState(() => _generationPhase = GenerationPhase.generating);
    try {
      final result = await widget.generationApi.generate(request);
      if (!mounted) return;
      setState(() {
        _generationResult = result;
        _generationFailure = null;
        _generationPhase = GenerationPhase.success;
      });
      await _showGeneratedPreview();
    } on GenerationApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _generationFailure = failure;
        _generationResult = null;
        _generationPhase = GenerationPhase.recoverableFailure;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _generationFailure = const GenerationApiFailure(
          code: GenerationFailureCode.unknown,
        );
        _generationResult = null;
        _generationPhase = GenerationPhase.recoverableFailure;
      });
    }
  }

  Future<void> _retryGeneration() async {
    final failure = _generationFailure;
    if (failure == null || _generationPhase == GenerationPhase.generating) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send another generation request?'),
        content: Text(failure.retryNotice),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _generate();
  }

  Future<void> _showGeneratedPreview() async {
    final result = _generationResult;
    if (result == null || !mounted) return;
    final action = await showDialog<_GenerationReviewAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review generated draft'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result.response.paper.title, style: Theme.of(context).textTheme.titleMedium),
                if (result.response.paper.abstractText.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(result.response.paper.abstractText),
                ],
                const SizedBox(height: 16),
                for (final section in result.response.paper.sections) ...[
                  Text(section.heading, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(section.content.isEmpty ? '[No content supplied]' : _previewText(section.content)),
                  const SizedBox(height: 12),
                ],
                if (result.response.reviewWarnings.isNotEmpty) ...[
                  Text('Review warnings', style: Theme.of(context).textTheme.titleSmall),
                  for (final warning in result.response.reviewWarnings)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('${warning.severity.toUpperCase()}: ${warning.message}'),
                    ),
                ],
                if (result.requestId != null) ...[
                  const SizedBox(height: 16),
                  Text('Request ID: ${result.requestId}', style: Theme.of(context).textTheme.bodySmall),
                ],
                const SizedBox(height: 12),
                Text('The saved paper will change only if you choose “Save generated paper”.', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _GenerationReviewAction.keepEditing),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _GenerationReviewAction.savePaper),
            child: const Text('Save generated paper'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == _GenerationReviewAction.keepEditing) {
      setState(() {
        _generationPhase = GenerationPhase.ready;
        _generationResult = null;
      });
    } else if (action == _GenerationReviewAction.savePaper) {
      await _acceptGeneratedPaper(result);
    }
  }

  Future<void> _acceptGeneratedPaper(GenerationResult result) async {
    if (!await _save(showMessage: false) || !mounted) return;
    try {
      await widget.repository.savePaperVersion(
        projectId: widget.project.id,
        schemaVersion: result.response.paper.schemaVersion,
        paper: result.response.paper.toJson(),
        origin: PaperVersionOrigin.generation,
        metadata: {
          'generation_id': result.response.generationId,
          'provider_name': result.response.meta.providerName,
          'model_name': result.response.meta.modelName,
          if (result.requestId != null) 'request_id': result.requestId,
        },
      );
      if (!mounted) return;
      setState(() {
        _versions = widget.repository.listPaperVersions(widget.project.id);
        _generationPhase = GenerationPhase.ready;
        _generationResult = null;
      });
      _showMessage('Generated paper saved as a new version on this device.');
    } on Object {
      if (mounted) {
        _showMessage(
          'The generated paper was not saved. Your previous saved paper remains current.',
          isError: true,
        );
      }
    }
  }

  String _previewText(String content) => content.length <= 500
      ? content
      : '${content.substring(0, 500)}…';

  Future<void> _requestLeave() async {
    if (_fingerprint() == _initialFingerprint) {
      await _popPage();
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved project changes'),
        content: const Text(
          'Save your changes before leaving, discard them, or keep editing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'stay'),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Discard changes'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Save and leave'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'discard') await _popPage();
    if (choice == 'save' && await _save(showMessage: false) && mounted) {
      await _popPage();
    }
  }

  Future<void> _popPage() async {
    if (!mounted) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _deleteProject() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this project?'),
        content: const Text(
          'This permanently deletes the project and its saved version history. There is no cloud backup or recovery.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.deleteProject(widget.project.id);
      await _popPage();
    } on Object {
      if (mounted) {
        _showMessage(
          'The project could not be deleted. Please try again.',
          isError: true,
        );
      }
    }
  }

  Future<PickedSource?> _pickSource() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'md', 'markdown', 'docx'],
    );
    if (result.isEmpty) return null;
    final file = result.single;
    return (name: file.name, bytes: await file.readAsBytes());
  }

  Future<void> _importFiles() async {
    setState(() {
      _importing = true;
      _importMessage = null;
      _importError = false;
    });
    try {
      if (widget.sourcePicker != null) {
        final picked = await widget.sourcePicker!();
        if (picked == null || !mounted) {
          if (mounted) setState(() => _importing = false);
          return;
        }
        if (picked.bytes.isEmpty) {
          setState(() {
            _importError = true;
            _importMessage = 'The uploaded file is empty. Please provide research material.';
            _importing = false;
          });
          return;
        }
        final imported = const SourceDocumentImporter().importBytes(
          fileName: picked.name,
          bytes: picked.bytes,
          allowPdf: true,
        );
        setState(() {
          _attachedFiles.clear();
          _attachedFiles.add((name: picked.name, size: picked.bytes.length));
          _controllers['source_draft']!.text = imported.text;
          _importMessage = 'Imported ${picked.name} (${imported.text.length} characters).';
          _importing = false;
          _analysisResponse = null;
          _showAdditionalInfoInterface = false;
        });
        return;
      }

      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'md', 'markdown', 'docx', 'pdf'],
      );
      if (result.isEmpty || !mounted) {
        if (mounted) setState(() => _importing = false);
        return;
      }

      final filesToProcess = <({String fileName, Uint8List bytes, String? contentType})>[];
      for (final file in result) {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          setState(() {
            _importError = true;
            _importMessage = 'File "${file.name}" is empty. Please provide research material.';
            _importing = false;
          });
          return;
        }
        filesToProcess.add((fileName: file.name, bytes: bytes, contentType: null));
      }

      final imported = const SourceDocumentImporter().importMultipleFiles(
        filesToProcess,
      );

      setState(() {
        _attachedFiles.clear();
        for (final f in filesToProcess) {
          _attachedFiles.add((name: f.fileName, size: f.bytes.length));
        }
        _controllers['source_draft']!.text = imported.text;
        _importMessage = filesToProcess.length == 1
            ? 'Imported ${filesToProcess.first.fileName} (${imported.text.length} characters).'
            : 'Imported ${filesToProcess.length} files (${imported.text.length} characters).';
        _importing = false;
        _analysisResponse = null;
        _showAdditionalInfoInterface = false;
      });
    } on SourceImportException catch (e) {
      if (mounted) {
        setState(() {
          _importError = true;
          _importMessage = e.message;
          _importing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _importError = true;
          _importMessage = 'Could not process file: $e';
          _importing = false;
        });
      }
    }
  }

  Future<void> _importSource({bool autoFillAll = false, bool? allowPdf}) async {
    setState(() {
      _importing = true;
      _importMessage = null;
      _importError = false;
    });
    try {
      final picked = await (widget.sourcePicker ?? _pickSource)();
      if (picked == null || !mounted) {
        if (mounted) setState(() => _importing = false);
        return;
      }
      final imported = const SourceDocumentImporter().importBytes(
        fileName: picked.name,
        bytes: picked.bytes,
        allowPdf: allowPdf ?? false,
      );

      if (autoFillAll) {
        final extracted = const DocumentProjectExtractor().extract(
          fileName: picked.name,
          rawText: imported.text,
        );
        _controllers['title']!.text = extracted.title;
        _controllers['research_field']!.text = extracted.researchField;
        _controllers['research_question']!.text = extracted.researchQuestion;
        _controllers['objectives']!.text = extracted.objectives.join('\n');
        _controllers['claimed_contribution']!.text = extracted.claimedContribution;
        if (extracted.methodology != null && extracted.methodology!.isNotEmpty) {
          _controllers['methodology']!.text = extracted.methodology!;
        }
        if (extracted.results != null && extracted.results!.isNotEmpty) {
          _controllers['results']!.text = extracted.results!;
        }
        if (extracted.limitations != null && extracted.limitations!.isNotEmpty) {
          _controllers['limitations']!.text = extracted.limitations!;
        }
        _controllers['source_draft']!.text = extracted.sourceDraft;
        if (extracted.references.isNotEmpty) {
          _controllers['references']!.text = extracted.references.join('\n');
        }
        _statuses['methodology_status'] = extracted.methodologyStatus;
        _statuses['dataset_or_materials_status'] = extracted.datasetStatus;
        _statuses['results_status'] = extracted.resultsStatus;
        _statuses['limitations_status'] = extracted.limitationsStatus;

        await _save(showMessage: false);
        if (!mounted) return;
        setState(() {
          _importing = false;
          _fieldErrors.clear();
          _importMessage =
              'Extracted research inputs from "${picked.name}". Ready to generate paper!';
          _importedSummaryDetails =
              'Extracted: "${picked.name}" (${imported.text.length} chars) · Suggested title: "${extracted.title}". Notice: Populated fields are heuristic suggestions from document structure; inspect and edit them before generation.';
        });
        _showMessage('Information extracted from ${picked.name} and auto-populated!');
        return;
      }

      final existing = _controllers['source_draft']!.text;
      var replace = existing.isEmpty;
      if (existing.isNotEmpty) {
        final choice = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Add imported text?'),
            content: const Text(
              'Replace the current draft or append the imported text?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'cancel'),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'append'),
                child: const Text('Append'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, 'replace'),
                child: const Text('Replace'),
              ),
            ],
          ),
        );
        if (!mounted || choice == 'cancel' || choice == null) {
          if (mounted) setState(() => _importing = false);
          return;
        }
        replace = choice == 'replace';
      }
      _controllers['source_draft']!.text = replace
          ? imported.text
          : '$existing\n\n${imported.text}';
      setState(() {
        _importing = false;
        _importMessage =
            'Imported ${picked.name}. Save the project to keep this draft.';
        _importedSummaryDetails =
            'Imported ${picked.name} (${imported.text.length} characters) into existing draft.';
      });
    } on SourceImportException catch (error) {
      if (mounted) {
        setState(() {
          _importing = false;
          _importMessage = error.message;
          _importedSummaryDetails = null;
          _importError = true;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _importing = false;
          _importMessage = 'The selected file could not be opened.';
          _importedSummaryDetails = null;
          _importError = true;
        });
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _showSummary() async {
    final supplied = <String>[];
    final workNotConducted = <String>[];
    final infoNotAvailable = <String>[];
    final warnings = <String>[];

    if (_documentMode) {
      if (_controllers['title']!.text.trim().isNotEmpty) {
        supplied.add('Working title: "${_controllers['title']!.text.trim()}"');
      } else {
        warnings.add('Working title is missing.');
      }
      if ((_controllers['description']?.text.trim() ?? '').isNotEmpty) {
        supplied.add('Description provided');
      }
      if (_controllers['source_draft']!.text.trim().isNotEmpty) {
        supplied.add('Manuscript source text (${_controllers['source_draft']!.text.length} characters)');
      } else {
        warnings.add('No document text supplied yet.');
      }
      warnings.add('No user-supplied references; citations must not be assumed verified.');
    } else {
      if (_controllers['research_field']!.text.trim().isNotEmpty) {
        supplied.add('Research field');
      }
      if (_controllers['research_question']!.text.trim().isNotEmpty) {
        supplied.add('Research question');
      }
      if (_nonblankLines(_controllers['objectives']!.text).isNotEmpty) {
        supplied.add('Objectives');
      }
      if (_controllers['claimed_contribution']!.text.trim().isNotEmpty) {
        supplied.add('Claimed contribution');
      }
      if (_controllers['source_draft']!.text.trim().isNotEmpty) {
        supplied.add('Existing draft');
      }
      if (_nonblankLines(_controllers['references']!.text).isNotEmpty) {
        supplied.add('References');
      }
      for (final key in _statusChoices.keys) {
        final status = _statuses[key]!;
        final label = _label(_statusDetails[key]!);
        if (status == 'provided') {
          supplied.add('$label: ${_statusLabels[status]!.toLowerCase()}');
        } else if (status == 'not_conducted' || status == 'not_applicable') {
          workNotConducted.add('$label is explicitly ${_statusLabels[status]!.toLowerCase()}.');
        } else if (['not_available', 'not_collected', 'not_identified'].contains(status)) {
          infoNotAvailable.add('$label is explicitly ${_statusLabels[status]!.toLowerCase()}.');
        } else if (status == 'unknown') {
          infoNotAvailable.add('$label status is unknown; add the details or choose an explicit status.');
        }
      }

      if (_controllers['research_field']!.text.trim().isEmpty) {
        warnings.add('Research field is missing.');
      }
      if (_controllers['research_question']!.text.trim().isEmpty) {
        warnings.add('Research question is missing.');
      }
      if (_nonblankLines(_controllers['objectives']!.text).isEmpty) {
        warnings.add('No research objectives have been supplied.');
      }
      if (_controllers['claimed_contribution']!.text.trim().isEmpty) {
        warnings.add('No claimed contribution has been supplied.');
      }
      if (_controllers['source_draft']!.text.trim().isEmpty) {
        warnings.add('No existing draft has been supplied.');
      }
      if (_nonblankLines(_controllers['references']!.text).isEmpty) {
        warnings.add('No user-supplied references; citations must not be assumed verified.');
      }
    }

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Before generation'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Supplied information (${supplied.length})',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  supplied.isEmpty
                      ? 'No optional information supplied yet.'
                      : supplied.join(' · '),
                ),
                if (workNotConducted.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Work explicitly not conducted (${workNotConducted.length})',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey.shade800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  for (final item in workNotConducted)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $item'),
                    ),
                ],
                if (infoNotAvailable.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Information not available (${infoNotAvailable.length})',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  for (final item in infoNotAvailable)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $item'),
                    ),
                ],
                const SizedBox(height: 14),
                Text(
                  'Review these points',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                for (final warning in warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• $warning'),
                  ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Target: $_targetWordCount words · ${_citationStyle.replaceAll('_', ' ')} citations · ${_requestedSections.length} sections',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This summary does not send your research anywhere.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  String _label(String key) => key
      .split('_')
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _requestLeave();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _requestLeave,
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Flexible(
              child: Text(
                'Research inputs',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              key: const ValueKey('project-save-status-badge'),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _saving
                    ? Colors.blue.shade50
                    : (_isDirty ? Colors.amber.shade100 : Colors.green.shade50),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _saving ? 'Saving…' : (_isDirty ? 'Unsaved' : 'Saved'),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: _saving
                      ? Colors.blue.shade800
                      : (_isDirty ? Colors.amber.shade900 : Colors.green.shade800),
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('button-upload-file-auto-fill-appbar'),
            onPressed: _importing ? null : () => _importSource(autoFillAll: true),
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Auto-fill from .txt or .md file',
          ),
          IconButton(
            onPressed: _deleteProject,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete project',
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          controller: _scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(ResbudDesignTokens.pagePadding),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SegmentedButton<bool>(
                key: const ValueKey('segmented-project-mode'),
                segments: const [
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('Generate from File (.txt/.md)'),
                    icon: Icon(Icons.description_outlined),
                  ),
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('Manual Form Details'),
                    icon: Icon(Icons.edit_note_outlined),
                  ),
                ],
                selected: {_documentMode},
                onSelectionChanged: (selected) =>
                    setState(() => _documentMode = selected.first),
              ),
            ),
            if (_documentMode) ..._buildDocumentModeWidgets()
            else ...[
              Text(
                'Project brief',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            const SizedBox(height: 8),
            const Text(
              'Required research facts are checked on this device. “Unknown” means you have not supplied the information yet; the other status choices record an explicit answer.',
            ),
            const SizedBox(height: 16),
            _textField(
              'title',
              'Working title',
              maxLength: 300,
              requiredField: true,
            ),
            _textField(
              'research_field',
              'Research field',
              maxLength: 200,
              requiredField: true,
            ),
            _textField(
              'research_question',
              'Research question',
              maxLength: 4000,
              requiredField: true,
              minLines: 2,
            ),
            _textField(
              'objectives',
              'Objectives',
              helper: 'One objective per line (1–20).',
              maxLength: 20000,
              requiredField: true,
              minLines: 3,
            ),
            _textField(
              'claimed_contribution',
              'Claimed contribution',
              maxLength: 4000,
              minLines: 2,
            ),
            for (final key in _statusChoices.keys) _statusGroup(key),
            const SizedBox(height: 12),
            Text(
              'Draft and references',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  key: const ValueKey('button-upload-file-auto-fill'),
                  onPressed: _importing ? null : () => _importSource(autoFillAll: true),
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(
                    _importing ? 'Processing file…' : 'Auto-Fill from File (.txt/.md)',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _importing ? null : () => _importSource(autoFillAll: false),
                  icon: const Icon(Icons.file_open_outlined),
                  label: Text(
                    _importing ? 'Reading file…' : 'Import .txt or .docx',
                  ),
                ),
              ],
            ),
            if (_importMessage != null) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _importMessage!,
                  style: TextStyle(
                    color: _importError
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              if (!_importError && _importedSummaryDetails != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    key: const ValueKey('import-summary-banner'),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.blueGrey.shade200),
                    ),
                    child: Text(
                      _importedSummaryDetails!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12),
                    ),
                  ),
                ),
            ],
            _textField(
              'source_draft',
              'Existing draft',
              helper:
                  'Paste or edit your source material. Maximum 50,000 characters.',
              maxLength: 50000,
              requiredField: true,
              minLines: 8,
            ),
            _textField(
              'references',
              'User-supplied references',
              helper:
                  'One reference per line, up to 50 references (2,000 characters each).',
              maxLength: 50000,
              minLines: 3,
            ),
            const SizedBox(height: 12),
            Text(
              'Paper preferences',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text('Target word count: $_targetWordCount'),
            Slider(
              value: _targetWordCount.toDouble(),
              min: 500,
              max: 8000,
              divisions: 75,
              label: '$_targetWordCount',
              onChanged: (value) =>
                  setState(() => _targetWordCount = value.round()),
            ),
            DropdownButtonFormField<String>(
              key: const ValueKey('citation-style'),
              initialValue: _citationStyle,
              decoration: const InputDecoration(
                labelText: 'Citation preference',
              ),
              items: const [
                DropdownMenuItem(
                  value: 'user_supplied',
                  child: Text('Use supplied references'),
                ),
                DropdownMenuItem(value: 'apa_7', child: Text('APA 7')),
                DropdownMenuItem(value: 'ieee', child: Text('IEEE')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _citationStyle = value);
              },
            ),
            const SizedBox(height: 12),
            Text(
              'Desired sections',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Wrap(
              spacing: 4,
              children: [
                for (final section in _baseSections)
                  FilterChip(
                    label: Text(_label(section)),
                    selected: _desiredSections.contains(section),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        if (_requestedSections.length < 15)
                          _desiredSections.add(section);
                      } else {
                        _desiredSections.remove(section);
                      }
                    }),
                  ),
              ],
            ),
            TextField(
              key: const ValueKey('input-custom-sections'),
              controller: _customSectionsController,
              maxLength: 1000,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Additional section IDs',
                helperText:
                    'Optional, one ID per line (for example: case_study_context).',
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_sectionError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _sectionError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            Container(
              key: const ValueKey('privacy-transmission-card'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blueGrey.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.privacy_tip_outlined,
                    size: 20,
                    color: Colors.blueGrey.shade700,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Transmission Notice: Generating transmits your project facts, source material, and references to the configured model provider to synthesize your draft. Resbud does not store drafts on the server; your work remains saved locally on this device.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                            color: Colors.blueGrey.shade900,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _showSummary,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Review before generation'),
            ),
            const SizedBox(height: 28),
            Text(
              'Saved versions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            FutureBuilder<List<PaperVersion>>(
              future: _versions,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text('Version history could not be loaded.');
                }
                if (!snapshot.hasData) {
                  return const LinearProgressIndicator();
                }
                if (snapshot.data!.isEmpty) {
                  return const Text('No paper versions saved yet.');
                }
                return Column(
                  children: [
                    for (final version in snapshot.data!)
                      ListTile(
                        key: ValueKey('version-${version.versionNumber}'),
                        contentPadding: EdgeInsets.zero,
                        title: Text('Version ${version.versionNumber}'),
                        subtitle: Text(
                          '${version.origin.name} · schema ${version.schemaVersion}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (version.id == widget.project.currentPaperVersionId)
                              const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: Icon(Icons.check_circle_outline, color: Colors.green),
                              ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () async {
                          final latestProject =
                              await widget.repository.getProject(widget.project.id) ?? widget.project;
                          if (!mounted) return;
                          await Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => PaperEditorPage(
                                repository: widget.repository,
                                generationApi: widget.generationApi,
                                project: latestProject,
                                initialVersion: version,
                                exportApi: widget.exportApi,
                                fileSaver: widget.fileSaver,
                              ),
                            ),
                          );
                          if (mounted) {
                            setState(() {
                              _versions = widget.repository.listPaperVersions(widget.project.id);
                            });
                          }
                        },
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 120),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_generationPhase == GenerationPhase.generating)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Column(
                    children: [
                      LinearProgressIndicator(),
                      SizedBox(height: 4),
                      Text(
                        'Generating paper draft — this may take a minute…',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              if (_generationPhase == GenerationPhase.recoverableFailure &&
                  _generationFailure != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    children: [
                      Text(
                        _generationFailure!.supportDetail,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: _retryGeneration,
                        child: const Text('Retry generation'),
                      ),
                    ],
                  ),
                ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 420;
                  final backButton = OutlinedButton(
                    onPressed: _requestLeave,
                    child: const Text('Back / cancel'),
                  );
                  final saveButton = FilledButton.icon(
                    onPressed: _saving ? null : () => _save(),
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Saving…' : 'Save project'),
                  );
                  final generateButton = FilledButton.icon(
                    onPressed: _generationPhase == GenerationPhase.generating || _saving
                        ? null
                        : _generate,
                    icon: _generationPhase == GenerationPhase.generating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_outlined),
                    label: Text(
                      _generationPhase == GenerationPhase.generating
                          ? 'Generating…'
                          : 'Generate',
                    ),
                  );

                  if (isNarrow) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(child: backButton),
                            const SizedBox(width: 8),
                            Expanded(child: saveButton),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(width: double.infinity, child: generateButton),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: backButton),
                      const SizedBox(width: 8),
                      Expanded(child: saveButton),
                      const SizedBox(width: 8),
                      Expanded(child: generateButton),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _textField(
    String key,
    String label, {
    String? helper,
    String? hintText,
    required int maxLength,
    bool requiredField = false,
    int minLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      key: ValueKey('input-$key'),
      controller: _controllers[key],
      maxLength: maxLength,
      minLines: minLines,
      maxLines: minLines == 1 ? 1 : null,
      keyboardType: minLines > 1 ? null : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        hintText: hintText,
        errorText: _fieldErrors[key],
        alignLabelWithHint: minLines > 1,
      ),
      validator: (value) =>
          _fieldErrors[key] ??
          (requiredField && (value == null || value.trim().isEmpty)
              ? '$label is required.'
              : null),
      onChanged: (_) => setState(() {}),
    ),
  );

  Widget _statusGroup(String statusKey) {
    final detailKey = _statusDetails[statusKey]!;
    final status = _statuses[statusKey]!;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _label(detailKey),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            DropdownButtonFormField<String>(
              key: ValueKey('status-$statusKey'),
              initialValue: status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: [
                for (final choice in _statusChoices[statusKey]!)
                  DropdownMenuItem(
                    value: choice,
                    child: Text(_statusLabels[choice]!),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _statuses[statusKey] = value);
              },
            ),
            const SizedBox(height: 4),
            Text(
              status == 'unknown'
                  ? 'Unknown means no answer has been supplied yet.'
                  : 'This is an explicit status; it is different from leaving the field blank.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (status == 'provided')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _textField(
                  detailKey,
                  '${_label(detailKey)} details',
                  maxLength: switch (detailKey) {
                    'methodology' || 'results' => 12000,
                    _ => 8000,
                  },
                  requiredField: true,
                  minLines: 3,
                ),
              ),
            if (status != 'provided' &&
                _controllers[detailKey]!.text.isNotEmpty)
              TextButton(
                onPressed: () =>
                    setState(() => _controllers[detailKey]!.clear()),
                child: const Text('Clear optional details'),
              ),
          ],
        ),
      ),
    );
  }
}
