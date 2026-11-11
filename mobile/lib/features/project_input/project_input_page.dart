import 'dart:convert';
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
  'introduction',
  'related_work',
  'methodology',
  'results',
  'discussion',
  'conclusion',
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
  int _targetWordCount = 5000;
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
  final List<Map<String, dynamic>> _attachedFigures = [];
  late final PaperExportApi _exportApi;
  late final DocxFileSaver _fileSaver;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _exportApi = widget.exportApi ?? DocxExportApiClient.fromEnvironment();
    _fileSaver = widget.fileSaver ?? LocalDocxFileSaver();
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
    final savedFigures = context['figures'];
    if (savedFigures is List) {
      for (final item in savedFigures) {
        if (item is Map) {
          _attachedFigures.add(Map<String, dynamic>.from(item));
        }
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
            'Formalize research methodology and experimental benchmark evaluation.',
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
      if (_attachedFigures.isNotEmpty) 'figures': _attachedFigures,
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
        _controllers['description']!.text = 'Investigation and manuscript synthesis based on the supplied research dossier.';
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Upload Research Material',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Generate from File (.txt/.md)',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo),
                              ),
                            ),
                          ],
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
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.article_outlined,
                          color: Theme.of(context).colorScheme.primary,
                          size: 24,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _attachedFiles.isNotEmpty
                                    ? _attachedFiles.first.name
                                    : 'Attached Research Material',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$charCount characters • ~${(charCount / 6).round()} words ready for synthesis',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green.shade300),
                          ),
                          child: Text(
                            'Ready for AI analysis',
                            style: TextStyle(
                              color: Colors.green.shade900,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 12),
              _textField(
                'source_draft',
                'Source research material / draft',
                maxLength: 50000,
                minLines: 3,
                maxLines: 6,
                helper: hasContent
                    ? 'Document attached ($charCount characters)'
                    : 'Upload a file above or paste research notes directly.',
              ),
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
      // 5. Illustrations & Figures (Optional)
      _buildFiguresSection(),
      const SizedBox(height: 16),
      // 6. Manuscript Depth & Publication Format
      _buildManuscriptDepthSelector(),
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
      const SizedBox(height: 20),
      _buildDocumentModeExportAndVersionsSection(),
      const SizedBox(height: 32),
    ];
  }

  Future<void> _viewVersion(
    PaperVersion version, {
    PaperWorkspaceMode mode = PaperWorkspaceMode.editor,
  }) async {
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
          initialMode: mode,
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
  }

  Future<void> _downloadVersionDocx(PaperVersion version) async {
    if (_isExporting) return;
    PaperDraftPayload paperToExport;
    try {
      paperToExport = PaperDraftPayload.fromJson(version.paper);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot parse version data: $e')),
      );
      return;
    }

    if (paperToExport.title.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot export: Paper title cannot be blank.')),
      );
      return;
    }
    if (paperToExport.sections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot export: Paper must contain at least one section.')),
      );
      return;
    }

    setState(() => _isExporting = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exporting Version ${version.versionNumber} to DOCX…'),
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      final result = await _exportApi.exportDocx(paperToExport);
      final savedPath = await _fileSaver.saveDocx(
        bytes: result.bytes,
        suggestedFilename: result.suggestedFilename,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported DOCX: $savedPath'),
          backgroundColor: Colors.green.shade800,
        ),
      );
    } on DocxExportFailure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: ${failure.userMessage}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export error: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _downloadVersionPdf(PaperVersion version) async {
    if (_isExporting) return;
    PaperDraftPayload paperToExport;
    try {
      paperToExport = PaperDraftPayload.fromJson(version.paper);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot parse version data: $e')),
      );
      return;
    }

    if (paperToExport.title.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot export: Paper title cannot be blank.')),
      );
      return;
    }
    if (paperToExport.sections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot export: Paper must contain at least one section.')),
      );
      return;
    }

    setState(() => _isExporting = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exporting Version ${version.versionNumber} to PDF…'),
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      final result = await _exportApi.exportPdf(paperToExport);
      final savedPath = await _fileSaver.savePdf(
        bytes: result.bytes,
        suggestedFilename: result.suggestedFilename,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported PDF: $savedPath'),
          backgroundColor: Colors.green.shade800,
        ),
      );
    } on DocxExportFailure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: ${failure.userMessage}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export error: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  Widget _buildDocumentModeExportAndVersionsSection() {
    return FutureBuilder<List<PaperVersion>>(
      future: _versions,
      builder: (context, snapshot) {
        final versions = snapshot.data ?? [];
        final hasVersions = versions.isNotEmpty;

        return Card(
          key: const ValueKey('card-document-mode-export-versions'),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: hasVersions ? Colors.teal.shade400 : Colors.grey.shade300,
              width: hasVersions ? 1.5 : 1,
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
                      hasVersions ? Icons.description : Icons.article_outlined,
                      color: hasVersions ? Colors.teal.shade700 : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hasVersions ? 'Generated Paper & Export' : 'Generated Paper',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (hasVersions)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.teal.shade200),
                        ),
                        child: Text(
                          '${versions.length} version${versions.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.teal.shade800,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!hasVersions) ...[
                  Text(
                    'No paper generated yet. Click "Generate Paper with AI" above to analyze your attached research material and synthesize your paper draft.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Once generated, your paper will appear here with direct options to View & Edit in the full editor or Download as a formatted DOCX document.',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ] else ...[
                  Builder(
                    builder: (context) {
                      final latest = versions.first;
                      final paperData = latest.paper;
                      final title = paperData['title'] as String? ?? 'Research Paper';
                      final sections = paperData['sections'] as List? ?? [];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.teal.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.teal.shade100),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Chip(
                                      label: Text(
                                        'Latest: v${latest.versionNumber}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                      backgroundColor: Colors.teal.shade100,
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        title,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${sections.length} academic sections · ${latest.origin.name} · Created ${_formatDate(latest.createdAt)}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 8,
                                  children: [
                                    FilledButton.icon(
                                      key: const ValueKey('button-view-latest-paper'),
                                      onPressed: () => _viewVersion(latest),
                                      icon: const Icon(Icons.edit_note, size: 18),
                                      label: const Text('View & Edit Paper'),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.teal.shade700,
                                      ),
                                    ),
                                    FilledButton.icon(
                                      key: const ValueKey('button-view-latest-pdf'),
                                      onPressed: () => _viewVersion(latest, mode: PaperWorkspaceMode.pdf),
                                      icon: const Icon(Icons.picture_as_pdf, size: 18),
                                      label: const Text('View as PDF'),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.indigo.shade700,
                                      ),
                                    ),
                                    FilledButton.tonalIcon(
                                      key: const ValueKey('button-download-latest-docx'),
                                      onPressed: _isExporting ? null : () => _downloadVersionDocx(latest),
                                      icon: _isExporting
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : const Icon(Icons.download, size: 18),
                                      label: const Text('Download DOCX'),
                                    ),
                                    FilledButton.tonalIcon(
                                      key: const ValueKey('button-download-latest-pdf'),
                                      onPressed: _isExporting ? null : () => _downloadVersionPdf(latest),
                                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                                      label: const Text('Download PDF'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Divider(),
                          const SizedBox(height: 4),
                          Text(
                            'All Saved Versions',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          for (final v in versions)
                            ListTile(
                              key: ValueKey('version-${v.versionNumber}'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'Version ${v.versionNumber}',
                                style: TextStyle(
                                  fontWeight: v.id == latest.id ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              subtitle: Text('${v.origin.name} · ${_formatDate(v.createdAt)}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    key: ValueKey('button-view-version-${v.versionNumber}'),
                                    tooltip: 'View / Edit in paper editor',
                                    icon: const Icon(Icons.visibility_outlined, size: 20),
                                    onPressed: () => _viewVersion(v),
                                  ),
                                  IconButton(
                                    key: ValueKey('button-view-version-pdf-${v.versionNumber}'),
                                    tooltip: 'View as PDF',
                                    icon: const Icon(Icons.picture_as_pdf, size: 20),
                                    onPressed: () => _viewVersion(v, mode: PaperWorkspaceMode.pdf),
                                  ),
                                  IconButton(
                                    key: ValueKey('button-download-version-${v.versionNumber}'),
                                    tooltip: 'Download DOCX',
                                    icon: const Icon(Icons.file_download_outlined, size: 20),
                                    onPressed: _isExporting ? null : () => _downloadVersionDocx(v),
                                  ),
                                  IconButton(
                                    key: ValueKey('button-download-version-pdf-${v.versionNumber}'),
                                    tooltip: 'Download PDF',
                                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                                    onPressed: _isExporting ? null : () => _downloadVersionPdf(v),
                                  ),
                                ],
                              ),
                              onTap: () => _viewVersion(v),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
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

        if (_controllers['references']!.text.trim().isEmpty &&
            analysis.extractedReferences.isNotEmpty) {
          _controllers['references']!.text =
              analysis.extractedReferences.map((r) => r.text).join('\n');
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
    if (_attachedFigures.isNotEmpty) {
      final figBuf = StringBuffer('\n\n=== RESEARCH FIGURES & ILLUSTRATIONS ===\n');
      for (final fig in _attachedFigures) {
        figBuf.writeln('Figure ID: ${fig['id']}');
        figBuf.writeln('Caption: ${fig['caption']}');
        if ((fig['description'] as String? ?? '').isNotEmpty) {
          figBuf.writeln('Description / Key Takeaways: ${fig['description']}');
        }
        figBuf.writeln('Marker to insert: ![${fig['caption']}](${fig['id']})');
      }
      effectiveDraft = '$effectiveDraft\n$figBuf';
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

  Map<String, dynamic> _embedFiguresInPaper(
    Map<String, dynamic> paperJson,
    List<Map<String, dynamic>> figures,
  ) {
    if (figures.isEmpty) return paperJson;
    final copy = Map<String, dynamic>.from(paperJson);
    final rawSections = copy['sections'];
    if (rawSections is! List) return paperJson;

    final sections = rawSections
        .map((s) => Map<String, dynamic>.from(s as Map))
        .toList();

    bool anyFigureFound = false;
    for (final s in sections) {
      String content = s['content'] as String? ?? '';
      for (final fig in figures) {
        final figId = fig['id'] as String? ?? '';
        final b64 = fig['base64'] as String? ?? '';
        if (figId.isNotEmpty && b64.isNotEmpty && content.contains('($figId)')) {
          content = content.replaceAll('($figId)', '($b64)');
          anyFigureFound = true;
        }
      }
      s['content'] = content;
    }

    if (!anyFigureFound && sections.isNotEmpty) {
      final targetIdx = sections.indexWhere((s) {
        final sid = (s['id'] as String? ?? '').toLowerCase();
        return sid.contains('method') || sid.contains('result') || sid.contains('approach');
      });
      final idx = targetIdx >= 0 ? targetIdx : 0;
      final target = sections[idx];
      final buf = StringBuffer(target['content'] as String? ?? '');
      for (final fig in figures) {
        final caption = fig['caption'] as String? ?? 'Figure';
        final b64 = fig['base64'] as String? ?? '';
        if (b64.isNotEmpty) {
          buf.writeln('\n\n![$caption]($b64)\n');
        }
      }
      target['content'] = buf.toString();
    }

    copy['sections'] = sections;
    return copy;
  }

  Future<void> _acceptGeneratedPaper(GenerationResult result) async {
    if (!await _save(showMessage: false) || !mounted) return;
    try {
      final enrichedPaper = _embedFiguresInPaper(
        result.response.paper.toJson(),
        _attachedFigures,
      );
      await widget.repository.savePaperVersion(
        projectId: widget.project.id,
        schemaVersion: result.response.paper.schemaVersion,
        paper: enrichedPaper,
        origin: PaperVersionOrigin.generation,
        metadata: {
          'generation_id': result.response.generationId,
          'provider_name': result.response.meta.providerName,
          'model_name': result.response.meta.modelName,
          if (result.requestId != null) 'request_id': result.requestId,
          if (result.response.meta.requestedWords != null)
            'requested_words': result.response.meta.requestedWords,
          if (result.response.meta.generatedWords != null)
            'generated_words': result.response.meta.generatedWords,
          if (result.response.meta.wordsPerSection != null)
            'words_per_section': result.response.meta.wordsPerSection,
          if (result.response.meta.completionStatus != null)
            'completion_status': result.response.meta.completionStatus,
          if (result.response.meta.missingSections != null)
            'missing_sections': result.response.meta.missingSections,
          if (result.response.meta.evidenceRestrictions != null)
            'evidence_restrictions': result.response.meta.evidenceRestrictions,
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
        allowedExtensions: [
          'txt', 'md', 'markdown', 'docx', 'pdf',
          'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp',
        ],
      );
      if (result.isEmpty || !mounted) {
        if (mounted) setState(() => _importing = false);
        return;
      }

      final filesToProcess = <({String fileName, Uint8List bytes, String? contentType})>[];
      int imagesAdded = 0;

      for (final file in result) {
        Uint8List? bytes;
        try {
          bytes = await file.readAsBytes();
        } catch (_) {}
        if (bytes == null || bytes.isEmpty) {
          continue;
        }

        final ext = file.name.split('.').last.toLowerCase();
        final isImage = const {'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'}.contains(ext);

        if (isImage) {
          final mediaType = switch (ext) {
            'jpg' || 'jpeg' => 'image/jpeg',
            'webp' => 'image/webp',
            'gif' => 'image/gif',
            'bmp' => 'image/bmp',
            _ => 'image/png',
          };
          final b64 = 'data:$mediaType;base64,${base64Encode(bytes)}';
          final figNumber = _attachedFigures.length + 1;
          final cleanName = file.name
              .replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '')
              .replaceAll('_', ' ');

          _attachedFigures.add({
            'id': 'fig_$figNumber',
            'name': file.name,
            'caption': 'Figure $figNumber: $cleanName',
            'description': '',
            'base64': b64,
            'bytes': bytes,
          });
          imagesAdded++;
        } else {
          filesToProcess.add((fileName: file.name, bytes: bytes, contentType: null));
        }
      }

      if (filesToProcess.isEmpty && imagesAdded > 0) {
        setState(() {
          _importing = false;
          _importMessage = 'Attached $imagesAdded figure${imagesAdded == 1 ? '' : 's'} to Illustrations & Figures.';
          _importError = false;
        });
        return;
      }

      if (filesToProcess.isEmpty) {
        setState(() {
          _importError = true;
          _importMessage = 'The selected file(s) could not be read.';
          _importing = false;
        });
        return;
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
        final docMsg = filesToProcess.length == 1
            ? 'Imported ${filesToProcess.first.fileName} (${imported.text.length} characters)'
            : 'Imported ${filesToProcess.length} files (${imported.text.length} characters)';
        _importMessage = imagesAdded > 0
            ? '$docMsg and attached $imagesAdded figure${imagesAdded == 1 ? '' : 's'}.'
            : '$docMsg.';
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
            ],
            const SizedBox(height: 120),
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
    int? maxLines,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      key: ValueKey('input-$key'),
      controller: _controllers[key],
      maxLength: maxLength,
      minLines: minLines,
      maxLines: maxLines ?? (minLines == 1 ? 1 : null),
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

  Future<void> _pickFigureImage() async {
    try {
      List<PlatformFile> pickedFiles = [];
      try {
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'],
        );
        pickedFiles = result;
      } catch (_) {
        final result = await FilePicker.pickFiles(type: FileType.image);
        pickedFiles = result;
      }

      if (pickedFiles.isEmpty || !mounted) return;

      int addedCount = 0;
      for (final file in pickedFiles) {
        Uint8List? bytes;
        try {
          bytes = await file.readAsBytes();
        } catch (_) {}
        if (bytes == null || bytes.isEmpty) continue;

        final ext = file.name.split('.').last.toLowerCase();
        final mediaType = switch (ext) {
          'jpg' || 'jpeg' => 'image/jpeg',
          'webp' => 'image/webp',
          'gif' => 'image/gif',
          'bmp' => 'image/bmp',
          _ => 'image/png',
        };
        final b64 = 'data:$mediaType;base64,${base64Encode(bytes)}';
        final figNumber = _attachedFigures.length + 1;
        final cleanName = file.name.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '').replaceAll('_', ' ');

        setState(() {
          _attachedFigures.add({
            'id': 'fig_$figNumber',
            'name': file.name,
            'caption': 'Figure $figNumber: $cleanName',
            'description': '',
            'base64': b64,
            'bytes': bytes,
          });
        });
        addedCount++;
      }

      if (addedCount > 0 && mounted) {
        _showMessage('Added $addedCount figure${addedCount == 1 ? '' : 's'} to manuscript.');
      }
    } catch (e) {
      if (mounted) _showMessage('Could not attach figure: $e', isError: true);
    }
  }

  Widget _buildFiguresSection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.photo_library_outlined, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Illustrations & Figures',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  key: const ValueKey('button-upload-figure'),
                  onPressed: _pickFigureImage,
                  icon: const Icon(Icons.add_photo_alternate, size: 16),
                  label: const Text('Add Figure'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Upload architectural diagrams, benchmark charts, or schematics. The AI will weave references and discuss them directly in the paper.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_attachedFigures.isNotEmpty) ...[
              const SizedBox(height: 14),
              for (var i = 0; i < _attachedFigures.length; i++) ...[
                _buildFigureItemCard(i),
                if (i < _attachedFigures.length - 1) const SizedBox(height: 10),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFigureItemCard(int index) {
    final fig = _attachedFigures[index];
    Uint8List? bytes;
    if (fig['bytes'] is Uint8List) {
      bytes = fig['bytes'] as Uint8List;
    } else if (fig['bytes'] is List) {
      try {
        bytes = Uint8List.fromList((fig['bytes'] as List).map((e) => (e as num).toInt()).toList());
        fig['bytes'] = bytes;
      } catch (_) {}
    }
    if (bytes == null && fig['base64'] is String) {
      try {
        final b64 = (fig['base64'] as String).split('base64,').last;
        bytes = base64Decode(b64);
        fig['bytes'] = bytes;
      } catch (_) {}
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: bytes != null
                ? Image.memory(
                    bytes,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 72,
                    height: 72,
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.image, color: Colors.grey),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  initialValue: fig['caption'] as String? ?? '',
                  decoration: const InputDecoration(
                    labelText: 'Figure Caption',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  onChanged: (val) {
                    fig['caption'] = val;
                  },
                ),
                const SizedBox(height: 6),
                TextFormField(
                  initialValue: fig['description'] as String? ?? '',
                  decoration: const InputDecoration(
                    labelText: 'Key Takeaways / Description (for AI)',
                    hintText: 'e.g. Highlights the convergence speedup...',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  onChanged: (val) {
                    fig['description'] = val;
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Remove figure',
            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
            onPressed: () {
              setState(() {
                _attachedFigures.removeAt(index);
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildManuscriptDepthSelector() {
    final depths = [
      (
        id: 'short',
        title: 'Short',
        scope: '~1,500 words',
        targetWords: 1500,
        description: 'Concise scientific communication focusing on the primary problem, core methodology, and immediate takeaways.',
      ),
      (
        id: 'standard',
        title: 'Standard',
        scope: '~3,000 words',
        targetWords: 3000,
        description: 'Standard academic paper length. Balanced distribution across literature context, methodology, results, and discussion.',
      ),
      (
        id: 'detailed',
        title: 'Detailed',
        scope: '~5,000 words',
        targetWords: 5000,
        description: 'Full peer-reviewed conference depth (NeurIPS, ICML). Formal technical architecture, multi-paragraph validation, and extensive analysis.',
      ),
      (
        id: 'extended',
        title: 'Extended',
        scope: '~7,000 words',
        targetWords: 7000,
        description: 'Exhaustive journal article depth. Deep theoretical foundations, thorough methodology, comprehensive ablation benchmarks, and complete limitations.',
      ),
    ];

    final isCustom = !depths.any((d) => d.targetWords == _targetWordCount);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Manuscript Depth & Length Target',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Select the target academic scope. The AI adapts section budgets and paragraph depth accordingly.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Target word count covers manuscript body text and abstract. References, tables, figures, captions, and supplementary materials are excluded from this limit.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (final depth in depths) ...[
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  setState(() {
                    _targetWordCount = depth.targetWords;
                  });
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: (_targetWordCount == depth.targetWords)
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                      width: (_targetWordCount == depth.targetWords) ? 1.5 : 1.0,
                    ),
                    color: (_targetWordCount == depth.targetWords)
                        ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.18)
                        : Theme.of(context).colorScheme.surface,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2, right: 8),
                        child: Icon(
                          (_targetWordCount == depth.targetWords)
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 20,
                          color: (_targetWordCount == depth.targetWords)
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey.shade500,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  depth.title,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    depth.scope,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              depth.description,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            // Custom Word Target Option
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                if (!isCustom) {
                  setState(() => _targetWordCount = 4000);
                }
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isCustom
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                    width: isCustom ? 1.5 : 1.0,
                  ),
                  color: isCustom
                      ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.18)
                      : Theme.of(context).colorScheme.surface,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 8),
                      child: Icon(
                        isCustom ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        size: 20,
                        color: isCustom
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade500,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Custom',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '$_targetWordCount words',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Specify any exact target length within configured boundaries (500 to 8,000 words).',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11.5),
                          ),
                          if (isCustom) ...[
                            const SizedBox(height: 8),
                            Slider(
                              value: _targetWordCount.toDouble().clamp(500, 8000),
                              min: 500,
                              max: 8000,
                              divisions: 15,
                              label: '$_targetWordCount words',
                              onChanged: (value) => setState(() => _targetWordCount = value.round()),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
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
    );
  }
}
