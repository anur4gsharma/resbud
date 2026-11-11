import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/local_project_repository.dart';
import '../docx_viewer/docx_document_canvas.dart';
import '../docx_viewer/docx_viewer.dart';
import '../export/docx_export_client.dart';
import '../export/docx_file_saver.dart';
import '../generation/generation_api_client.dart';
import '../generation/generation_models.dart';
import '../pdf_viewer/pdf_viewer.dart';
import '../readiness/manuscript_readiness_service.dart';
import '../readiness/manuscript_readiness_sheet.dart';
import '../../shared/design_tokens.dart';

enum _RegenerationReviewChoice { reject, accept }

enum PaperWorkspaceMode { document, pdf, editor }

class PaperEditorPage extends StatefulWidget {
  const PaperEditorPage({
    super.key,
    required this.repository,
    required this.generationApi,
    required this.project,
    required this.initialVersion,
    this.initialMode = PaperWorkspaceMode.editor,
    this.exportApi,
    this.fileSaver,
  });

  final LocalProjectRepository repository;
  final PaperGenerationApi generationApi;
  final LocalProject project;
  final PaperVersion initialVersion;
  final PaperWorkspaceMode initialMode;
  final PaperExportApi? exportApi;
  final DocxFileSaver? fileSaver;

  @override
  State<PaperEditorPage> createState() => _PaperEditorPageState();
}

class _PaperEditorPageState extends State<PaperEditorPage> {
  final _scrollController = ScrollController();
  late PaperWorkspaceMode _workspaceMode;
  late Future<List<PaperVersion>> _versionsFuture;
  late PaperVersion _currentVersion;
  late PaperDraftPayload _paper;
  late final TextEditingController _titleController;
  late final TextEditingController _abstractController;
  late final Map<String, TextEditingController> _sectionControllers;
  late final Map<String, GlobalKey> _sectionKeys;
  late final PaperExportApi _exportApi;
  late final DocxFileSaver _fileSaver;

  bool _isDirty = false;
  bool _isSaving = false;
  bool _isExporting = false;
  String? _activeRegeneratingSectionId;
  final Set<String> _previewingSectionIds = {};

  final _referencesKey = GlobalKey();
  final _abstractKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _workspaceMode = widget.initialMode;
    _versionsFuture = widget.repository.listPaperVersions(widget.project.id);
    _exportApi = widget.exportApi ?? DocxExportApiClient.fromEnvironment();
    _fileSaver = widget.fileSaver ?? LocalDocxFileSaver();
    _currentVersion = widget.initialVersion;
    _paper = PaperDraftPayload.fromJson(_currentVersion.paper);
    _titleController = TextEditingController(text: _paper.title);
    _abstractController = TextEditingController(text: _paper.abstractText);
    _sectionControllers = {
      for (final section in _paper.sections)
        section.id: TextEditingController(text: section.content),
    };
    _sectionKeys = {
      for (final section in _paper.sections) section.id: GlobalKey(),
    };

    _titleController.addListener(_markDirty);
    _abstractController.addListener(_markDirty);
    for (final controller in _sectionControllers.values) {
      controller.addListener(_markDirty);
    }
  }

  void _markDirty() {
    if (!_isDirty && mounted) {
      setState(() => _isDirty = true);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _titleController.dispose();
    _abstractController.dispose();
    for (final controller in _sectionControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _jumpToSection(String sectionId) {
    if (sectionId == 'abstract' || sectionId == 'title') {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
      return;
    }
    if (sectionId == 'references') {
      if (_referencesKey.currentContext != null) {
        Scrollable.ensureVisible(
          _referencesKey.currentContext!,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
          alignment: 0.1,
        );
      }
      return;
    }
    final key = _sectionKeys[sectionId];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        alignment: 0.1,
      );
    }
  }

  Future<void> _saveManualEdits() async {
    if (_isSaving) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showFeedback('Paper title cannot be blank.', isError: true);
      return;
    }

    setState(() => _isSaving = true);

    final updatedSections = _paper.sections.map((section) {
      final controller = _sectionControllers[section.id];
      final newContent = controller?.text ?? section.content;
      return section.copyWith(content: newContent);
    }).toList(growable: false);

    final updatedPaper = _paper.copyWith(
      title: title,
      abstractText: _abstractController.text.trim(),
      sections: updatedSections,
    );

    try {
      final savedVersion = await widget.repository.savePaperVersion(
        projectId: widget.project.id,
        schemaVersion: updatedPaper.schemaVersion,
        paper: updatedPaper.toJson(),
        origin: PaperVersionOrigin.manualEdit,
        metadata: {
          'source_version_number': _currentVersion.versionNumber,
        },
      );
      if (!mounted) return;
      setState(() {
        _currentVersion = savedVersion;
        _paper = updatedPaper;
        _versionsFuture = widget.repository.listPaperVersions(widget.project.id);
        _isDirty = false;
        _isSaving = false;
      });
      _showFeedback('Version ${savedVersion.versionNumber} saved.');
    } on Object {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showFeedback(
        'Could not save your changes. Your unsaved edits are preserved in the editor.',
        isError: true,
      );
    }
  }

  Future<void> _compareSourceDraft() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(ResbudDesignTokens.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Original source material',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Authoritative material used to draft this paper (${widget.project.sourceDraft.length} characters):',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: SelectableText(
                    widget.project.sourceDraft.isEmpty
                        ? '[No source draft text recorded]'
                        : widget.project.sourceDraft,
                    style: const TextStyle(fontFamily: 'monospace', height: 1.4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startSectionRegeneration(PaperSectionPayload section) async {
    if (_activeRegeneratingSectionId != null) return;

    final instruction = await showDialog<String>(
      context: context,
      builder: (context) => _RegenerationPromptDialog(section: section),
    );

    if (instruction == null || !mounted) return;

    setState(() => _activeRegeneratingSectionId = section.id);

    try {
      final latestProject =
          await widget.repository.getProject(widget.project.id) ?? widget.project;
      final genRequest = GenerationRequest.fromInputs(
        project: latestProject.projectContext,
        sourceDraft: latestProject.sourceDraft,
      );

      final regenRequest = SectionRegenerationRequest.create(
        generationRequest: genRequest,
        currentPaper: _paper,
        sectionId: section.id,
        userInstruction: instruction,
      );

      final result = await widget.generationApi.regenerateSection(regenRequest);
      if (!mounted) return;

      setState(() => _activeRegeneratingSectionId = null);
      await _showRegenerationPreview(section, result);
    } on GenerationApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _activeRegeneratingSectionId = null);
      _showFeedback(failure.supportDetail, isError: true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _activeRegeneratingSectionId = null);
      _showFeedback('Regeneration failed: $error', isError: true);
    }
  }

  Future<void> _showRegenerationPreview(
    PaperSectionPayload currentSection,
    SectionRegenerationResult result,
  ) async {
    final replacement = result.response.section;

    final choice = await showDialog<_RegenerationReviewChoice>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Review replacement for ${currentSection.heading}'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current content:',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 6),
                          Container(
                            key: const ValueKey('regen-current-content'),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(80),
                              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            constraints: const BoxConstraints(maxHeight: 220),
                            child: SingleChildScrollView(
                              child: Text(
                                currentSection.content.isEmpty
                                    ? '[Section had no content]'
                                    : currentSection.content,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Proposed replacement content:',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Colors.teal.shade800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            key: const ValueKey('regen-proposed-content'),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.teal.withAlpha(25),
                              border: Border.all(color: Colors.teal.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            constraints: const BoxConstraints(maxHeight: 220),
                            child: SingleChildScrollView(
                              child: Text(
                                replacement.content,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (result.response.reviewWarnings.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Section warnings (${result.response.reviewWarnings.length}):',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  for (final warning in result.response.reviewWarnings)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '• [${warning.severity.toUpperCase()}] ${warning.message}',
                        style: TextStyle(
                          color: warning.severity == 'critical'
                              ? Colors.red.shade700
                              : Colors.amber.shade900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Accepting this proposal replaces ONLY this section. All other sections, references, title, and keywords remain strictly unchanged.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, _RegenerationReviewChoice.reject),
            child: const Text('Reject proposal'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, _RegenerationReviewChoice.accept),
            icon: const Icon(Icons.check),
            label: const Text('Accept replacement'),
          ),
        ],
      ),
    );

    if (!mounted || choice != _RegenerationReviewChoice.accept) {
      return;
    }

    final updatedSections = _paper.sections.map((s) {
      if (s.id == currentSection.id) {
        return replacement;
      }
      return s;
    }).toList(growable: false);

    final updatedWarnings = [
      ..._paper.reviewWarnings.where((w) => w.sectionId != currentSection.id),
      ...result.response.reviewWarnings,
    ];

    final updatedPaper = _paper.copyWith(
      sections: updatedSections,
      reviewWarnings: updatedWarnings,
    );

    try {
      final savedVersion = await widget.repository.savePaperVersion(
        projectId: widget.project.id,
        schemaVersion: updatedPaper.schemaVersion,
        paper: updatedPaper.toJson(),
        origin: PaperVersionOrigin.sectionAcceptance,
        metadata: {
          'regenerated_section_id': currentSection.id,
          if (result.requestId != null) 'request_id': result.requestId,
        },
      );
      if (!mounted) return;
      setState(() {
        _currentVersion = savedVersion;
        _paper = updatedPaper;
        _versionsFuture = widget.repository.listPaperVersions(widget.project.id);
        _sectionControllers[currentSection.id]?.text = replacement.content;
        _isDirty = false;
      });
      _showFeedback(
        'Accepted replacement for ${currentSection.heading}. Saved as Version ${savedVersion.versionNumber}.',
      );
    } on Object {
      if (!mounted) return;
      _showFeedback(
        'Failed to save replacement. Your previous draft version remains active.',
        isError: true,
      );
    }
  }

  void _showFeedback(String message, {bool isError = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  void _revertSection(PaperSectionPayload section) {
    final controller = _sectionControllers[section.id];
    if (controller != null && controller.text != section.content) {
      controller.text = section.content;
      _showFeedback('Reverted "${section.heading}" to version snapshot.');
      setState(() {});
    } else {
      _showFeedback('"${section.heading}" has not been modified.');
    }
  }

  Future<void> _pickAndInsertFigure(PaperSectionPayload section) async {
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

      final controller = _sectionControllers[section.id];
      if (controller == null) return;

      final buffer = StringBuffer();
      int count = 0;
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
        final cleanName = file.name
            .replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '')
            .replaceAll('_', ' ');
        final b64 = 'data:$mediaType;base64,${base64Encode(bytes)}';

        buffer.writeln();
        buffer.writeln('![Figure: $cleanName]($b64)');
        buffer.writeln();
        count++;
      }

      if (count > 0) {
        final currentText = controller.text;
        final newText = currentText.isEmpty
            ? buffer.toString().trim()
            : '$currentText\n${buffer.toString()}';
        controller.text = newText;
        _saveManualEdits();
        _showFeedback('Inserted $count image${count == 1 ? '' : 's'} into ${section.heading}');
      }
    } catch (e) {
      _showFeedback('Failed to insert image: $e', isError: true);
    }
  }

  void _openReadinessReview() {
    final updatedSections = _paper.sections.map((section) {
      final controller = _sectionControllers[section.id];
      final newContent = controller?.text ?? section.content;
      return section.copyWith(content: newContent);
    }).toList(growable: false);

    final currentPaper = _paper.copyWith(
      title: _titleController.text.trim(),
      abstractText: _abstractController.text.trim(),
      sections: updatedSections,
    );

    final report = const ManuscriptReadinessService().evaluate(
      paper: currentPaper,
      projectContext: widget.project.projectContext,
    );

    ManuscriptReadinessSheet.show(
      context: context,
      report: report,
      onNavigateToSection: _jumpToSection,
    );
  }

  void _openOutlineSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(ResbudDesignTokens.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Manuscript Outline',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(sheetContext),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('button-readiness-sheet-shortcut'),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _openReadinessReview();
                  },
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('Open Readiness Review'),
                ),
              ),
              const Divider(),
              Expanded(
                child: _buildOutlineList(
                  scrollController: scrollController,
                  onSelect: () => Navigator.pop(sheetContext),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOutlineRail(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow.withAlpha(80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.menu_book_outlined, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Manuscript Outline',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: InkWell(
              key: const ValueKey('button-readiness-rail'),
              onTap: _openReadinessReview,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.primary.withAlpha(50)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.fact_check_outlined, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Readiness Review',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Checklist & findings',
                            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 16),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _buildOutlineList(),
          ),
        ],
      ),
    );
  }

  Widget _buildOutlineList({
    ScrollController? scrollController,
    VoidCallback? onSelect,
  }) {
    final theme = Theme.of(context);

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        ListTile(
          dense: true,
          leading: const Icon(Icons.article_outlined, size: 18),
          title: const Text('Title & Abstract', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          onTap: () {
            _jumpToSection('abstract');
            onSelect?.call();
          },
        ),
        for (final section in _paper.sections) ...[
          Builder(builder: (context) {
            final hasWarning = _paper.reviewWarnings.any((w) => w.sectionId == section.id);
            final isNeedsInput = section.state == 'needs_input';
            final isNotApplicable = section.state == 'not_applicable';
            final controller = _sectionControllers[section.id];
            final isEdited = controller != null && controller.text != section.content;

            final iconColor = hasWarning || isNeedsInput
                ? Colors.amber.shade800
                : (isNotApplicable ? Colors.grey.shade500 : theme.colorScheme.primary);

            return ListTile(
              dense: true,
              leading: Icon(
                hasWarning || isNeedsInput
                    ? Icons.warning_amber_rounded
                    : (isNotApplicable ? Icons.remove_circle_outline : Icons.subject),
                size: 18,
                color: iconColor,
              ),
              title: Text(
                section.heading,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: hasWarning || isNeedsInput ? FontWeight.bold : FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: isEdited
                  ? const Text('Edited · Unsaved', style: TextStyle(fontSize: 10, color: Colors.blue))
                  : (isNeedsInput
                      ? Text('Needs input', style: TextStyle(fontSize: 10, color: Colors.amber.shade900))
                      : null),
              onTap: () {
                _jumpToSection(section.id);
                onSelect?.call();
              },
            );
          }),
        ],
        ListTile(
          dense: true,
          leading: const Icon(Icons.format_list_numbered, size: 18),
          title: Text(
            'References (${_paper.references.length})',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          onTap: () {
            _jumpToSection('references');
            onSelect?.call();
          },
        ),
      ],
    );
  }

  Future<void> _openVersionHistory() async {
    final versions = await widget.repository.listPaperVersions(widget.project.id);
    if (!mounted) return;

    final selectedToRestore = await showModalBottomSheet<PaperVersion>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(ResbudDesignTokens.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Version history',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${versions.length} immutable snapshots recorded',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(sheetContext),
                  ),
                ],
              ),
              const Divider(height: 16),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: versions.length,
                  itemBuilder: (context, index) {
                    final version = versions.reversed.toList()[index];
                    final isCurrent = version.id == _currentVersion.id;
                    final restoredFrom = version.metadata?['restored_from_version_number'];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: isCurrent ? Colors.teal.shade50 : null,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Version ${version.versionNumber}',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    if (isCurrent) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.teal.shade700,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'Active in editor',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                Text(
                                  _formatDateTime(version.createdAt),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Origin: ${_originLabel(version.origin)}${restoredFrom != null ? ' (restored from v$restoredFrom)' : ''}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (version.paper['title'] != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Title: ${version.paper['title']}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  key: ValueKey('button-restore-v${version.versionNumber}'),
                                  onPressed: () => Navigator.pop(sheetContext, version),
                                  icon: const Icon(Icons.restore, size: 16),
                                  label: Text(isCurrent ? 'Revert to snapshot' : 'Restore this version'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (selectedToRestore == null || !mounted) return;
    await _confirmAndRestoreVersion(selectedToRestore);
  }

  Future<void> _confirmAndRestoreVersion(PaperVersion targetVersion) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Restore Version ${targetVersion.versionNumber}?'),
        content: Text(
          'Restoring Version ${targetVersion.versionNumber} will create a new version containing its content. '
          'All prior versions and history are preserved.\n\n'
          '${_isDirty ? 'Warning: You have unsaved edits in the editor which will be replaced.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-restore-button'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restore version'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final restored = await widget.repository.restorePaperVersion(
        projectId: widget.project.id,
        targetVersionId: targetVersion.id,
      );
      if (!mounted) return;
      setState(() {
        _versionsFuture = widget.repository.listPaperVersions(widget.project.id);
      });
      _loadVersion(restored);
      _showFeedback(
        'Restored Version ${targetVersion.versionNumber} as Version ${restored.versionNumber}.',
      );
    } on Object catch (error) {
      if (!mounted) return;
      _showFeedback('Failed to restore version: $error', isError: true);
    }
  }

  void _loadVersion(PaperVersion version) {
    _currentVersion = version;
    _paper = PaperDraftPayload.fromJson(version.paper);

    _titleController.removeListener(_markDirty);
    _titleController.text = _paper.title;
    _titleController.addListener(_markDirty);

    _abstractController.removeListener(_markDirty);
    _abstractController.text = _paper.abstractText;
    _abstractController.addListener(_markDirty);

    for (final section in _paper.sections) {
      final controller = _sectionControllers[section.id];
      if (controller != null) {
        controller.removeListener(_markDirty);
        controller.text = section.content;
        controller.addListener(_markDirty);
      } else {
        final newController = TextEditingController(text: section.content);
        newController.addListener(_markDirty);
        _sectionControllers[section.id] = newController;
        _sectionKeys[section.id] = GlobalKey();
      }
    }
    _isDirty = false;
    setState(() {});
  }

  Future<void> _switchVersion(PaperVersion targetVersion) async {
    if (targetVersion.id == _currentVersion.id) return;

    if (_isDirty) {
      final choice = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Unsaved edits'),
          content: Text(
            'You have unsaved edits in Version ${_currentVersion.versionNumber}. '
            'Switching to Version ${targetVersion.versionNumber} will discard unsaved edits unless you save them first.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(dialogContext, 'discard'),
              child: const Text('Discard edits'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'save'),
              child: const Text('Save first'),
            ),
          ],
        ),
      );

      if (!mounted || choice == null || choice == 'cancel') return;
      if (choice == 'save') {
        await _saveManualEdits();
        if (_isDirty || !mounted) return;
      }
    }

    setState(() {
      _loadVersion(targetVersion);
      _isDirty = false;
    });

    _showFeedback('Viewing Version ${targetVersion.versionNumber}');
  }

  int _computeTotalWords() {
    int words = 0;
    words += _titleController.text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    words += _abstractController.text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    for (final controller in _sectionControllers.values) {
      words += controller.text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    }
    return words;
  }

  Widget _buildCompletionStatusBanner() {
    final meta = _currentVersion.metadata;
    final preferences = widget.project.projectContext['preferences'] as Map?;
    final int requestedWords = (meta?['requested_words'] as int?) ??
        (preferences?['target_word_count'] as int?) ??
        5000;
    final int actualWords = (meta?['generated_words'] as int?) ?? _computeTotalWords();
    final String completionStatus = (meta?['completion_status'] as String?) ??
        (actualWords >= (requestedWords * 0.75) ? 'completed' : 'under_generated');
    final double pct = ((actualWords / requestedWords) * 100).clamp(0, 500);

    Color cardColor;
    Color iconColor;
    Color textColor;
    IconData icon;
    String titleText;
    String descText;

    if (completionStatus == 'completed' || (actualWords >= (requestedWords * 0.75))) {
      cardColor = Colors.green.shade50;
      iconColor = Colors.green.shade800;
      textColor = Colors.green.shade900;
      icon = Icons.check_circle_outline;
      titleText = 'Manuscript Completed: $actualWords / $requestedWords words (${pct.toStringAsFixed(0)}%)';
      descText = 'The draft satisfies requested length requirements within academic depth tolerances.';
    } else if (completionStatus == 'evidence_constrained') {
      cardColor = Colors.blue.shade50;
      iconColor = Colors.blue.shade800;
      textColor = Colors.blue.shade900;
      icon = Icons.info_outline;
      titleText = 'Evidence-Constrained Manuscript: $actualWords / $requestedWords words (${pct.toStringAsFixed(0)}%)';
      descText = 'Generation was capped by missing empirical results or source material to prevent fabrication.';
    } else {
      cardColor = Colors.amber.shade50;
      iconColor = Colors.amber.shade900;
      textColor = Colors.amber.shade900;
      icon = Icons.warning_amber_outlined;
      titleText = 'Under-Generated Manuscript: $actualWords / $requestedWords words (${pct.toStringAsFixed(0)}%)';
      descText = 'This draft fell short of your requested target length. Inspect individual section depths.';
    }

    return Card(
      key: const ValueKey('manuscript-completion-banner'),
      color: cardColor,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _showManuscriptCompletionDialog,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleText,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      descText,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: textColor.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: iconColor),
            ],
          ),
        ),
      ),
    );
  }

  void _showManuscriptCompletionDialog() {
    final meta = _currentVersion.metadata;
    final preferences = widget.project.projectContext['preferences'] as Map?;
    final int requestedWords = (meta?['requested_words'] as int?) ??
        (preferences?['target_word_count'] as int?) ??
        5000;
    final int actualWords = (meta?['generated_words'] as int?) ?? _computeTotalWords();
    final String completionStatus = (meta?['completion_status'] as String?) ??
        (actualWords >= (requestedWords * 0.75) ? 'completed' : 'under_generated');
    final Map<String, dynamic>? wordsPerSection = meta?['words_per_section'] is Map
        ? (meta!['words_per_section'] as Map).cast<String, dynamic>()
        : null;
    final List<dynamic>? restrictions = meta?['evidence_restrictions'] as List<dynamic>?;
    final List<dynamic>? missingSections = meta?['missing_sections'] as List<dynamic>?;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: ListView(
                controller: scrollController,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            completionStatus == 'completed'
                                ? Icons.verified_outlined
                                : (completionStatus == 'evidence_constrained'
                                    ? Icons.info_outline
                                    : Icons.warning_amber_rounded),
                            color: completionStatus == 'completed'
                                ? Colors.green.shade700
                                : (completionStatus == 'evidence_constrained'
                                    ? Colors.blue.shade700
                                    : Colors.orange.shade800),
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Length & Depth Report',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Length Fulfillment',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              '$actualWords / $requestedWords words (${((actualWords / requestedWords) * 100).toStringAsFixed(0)}%)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: actualWords >= (requestedWords * 0.75) ? Colors.green.shade700 : Colors.orange.shade800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (actualWords / requestedWords).clamp(0.0, 1.0),
                            minHeight: 6,
                            backgroundColor: Colors.grey.shade300,
                            color: actualWords >= (requestedWords * 0.75) ? Colors.green : Colors.orange,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Status: ${completionStatus.replaceAll('_', ' ').toUpperCase()}',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Section Word Distribution',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  for (final section in _paper.sections) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              section.heading,
                              style: const TextStyle(fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${wordsPerSection?[section.id] ?? _sectionControllers[section.id]?.text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length ?? 0} words',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (restrictions != null && restrictions.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Evidence Restrictions & Limitations',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                    ),
                    const SizedBox(height: 6),
                    for (final r in restrictions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                            Expanded(child: Text(r.toString(), style: const TextStyle(fontSize: 12))),
                          ],
                        ),
                      ),
                  ],
                  if (missingSections != null && missingSections.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Missing / Incomplete Sections',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.orange.shade900),
                    ),
                    const SizedBox(height: 6),
                    for (final s in missingSections)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                            Expanded(child: Text('Section requires input: $s', style: const TextStyle(fontSize: 12))),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCompactVersionSelector() {
    return FutureBuilder<List<PaperVersion>>(
      future: _versionsFuture,
      builder: (context, snapshot) {
        final versions = snapshot.data ?? [_currentVersion];

        return PopupMenuButton<PaperVersion>(
          key: const ValueKey('compact-version-selector'),
          tooltip: 'Select document version',
          offset: const Offset(0, 36),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.grey.shade400),
          ),
          onSelected: _switchVersion,
          itemBuilder: (context) {
            return [
              for (final v in versions.reversed)
                PopupMenuItem<PaperVersion>(
                  key: ValueKey('version-selector-item-${v.versionNumber}'),
                  value: v,
                  child: Row(
                    children: [
                      Icon(
                        v.id == _currentVersion.id ? Icons.check_circle : Icons.circle_outlined,
                        size: 16,
                        color: v.id == _currentVersion.id ? Colors.teal : Colors.grey.shade500,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Version ${v.versionNumber}${v.id == versions.last.id ? ' (Latest)' : ''}',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: v.id == _currentVersion.id ? FontWeight.bold : FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _formatDateTime(v.createdAt),
                                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                            Text(
                              _originLabel(v.origin),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ];
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _versionSubtitle(_currentVersion),
                  key: const ValueKey('current-version-label'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const Icon(Icons.arrow_drop_down, size: 14),
            ],
          ),
        );
      },
    );
  }

  Future<void> _exportDocx() async {
    if (_isExporting) return;

    PaperDraftPayload paperToExport = _paper;

    if (_isDirty) {
      final choice = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Unsaved edits'),
          content: Text(
            'You have unsaved changes in the editor. Save your changes before exporting, '
            'or export the currently saved Version ${_currentVersion.versionNumber}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              key: const ValueKey('export-saved-button'),
              onPressed: () => Navigator.pop(dialogContext, 'export_saved'),
              child: Text('Export saved (v${_currentVersion.versionNumber})'),
            ),
            FilledButton(
              key: const ValueKey('save-and-export-button'),
              onPressed: () => Navigator.pop(dialogContext, 'save_and_export'),
              child: const Text('Save & export'),
            ),
          ],
        ),
      );

      if (!mounted || choice == null || choice == 'cancel') return;

      if (choice == 'save_and_export') {
        await _saveManualEdits();
        if (_isDirty || !mounted) {
          // Save failed or was cancelled
          return;
        }
        paperToExport = _paper;
      } else if (choice == 'export_saved') {
        paperToExport = PaperDraftPayload.fromJson(_currentVersion.paper);
      }
    }

    // Validate paper content before sending to export API
    if (paperToExport.title.trim().isEmpty) {
      _showFeedback('Cannot export: Paper title cannot be blank.', isError: true);
      return;
    }
    if (paperToExport.sections.isEmpty) {
      _showFeedback('Cannot export: Paper must contain at least one section.', isError: true);
      return;
    }

    setState(() => _isExporting = true);

    try {
      final result = await _exportApi.exportDocx(paperToExport);
      final savedPath = await _fileSaver.saveDocx(
        bytes: result.bytes,
        suggestedFilename: result.suggestedFilename,
      );
      if (!mounted) return;
      setState(() => _isExporting = false);
      _showFeedback('Exported DOCX: $savedPath');
    } on DocxExportFailure catch (failure) {
      if (!mounted) return;
      setState(() => _isExporting = false);
      _showFeedback(failure.supportDetail, isError: true);
    } on DocxFileSaverException catch (saverError) {
      if (!mounted) return;
      setState(() => _isExporting = false);
      _showFeedback('File save error: ${saverError.message}', isError: true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _isExporting = false);
      _showFeedback('Export failed: $error', isError: true);
    }
  }

  Future<void> _exportPdf() async {
    if (_isExporting) return;

    PaperDraftPayload paperToExport = _paper;

    if (_isDirty) {
      final choice = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Unsaved edits'),
          content: Text(
            'You have unsaved changes in the editor. Save your changes before exporting, '
            'or export the currently saved Version ${_currentVersion.versionNumber}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              key: const ValueKey('export-saved-pdf-button'),
              onPressed: () => Navigator.pop(dialogContext, 'export_saved'),
              child: Text('Export saved (v${_currentVersion.versionNumber})'),
            ),
            FilledButton(
              key: const ValueKey('save-and-export-pdf-button'),
              onPressed: () => Navigator.pop(dialogContext, 'save_and_export'),
              child: const Text('Save & export'),
            ),
          ],
        ),
      );

      if (!mounted || choice == null || choice == 'cancel') return;

      if (choice == 'save_and_export') {
        await _saveManualEdits();
        if (_isDirty || !mounted) {
          return;
        }
        paperToExport = _paper;
      } else if (choice == 'export_saved') {
        paperToExport = PaperDraftPayload.fromJson(_currentVersion.paper);
      }
    }

    if (paperToExport.title.trim().isEmpty) {
      _showFeedback('Cannot export: Paper title cannot be blank.', isError: true);
      return;
    }
    if (paperToExport.sections.isEmpty) {
      _showFeedback('Cannot export: Paper must contain at least one section.', isError: true);
      return;
    }

    setState(() => _isExporting = true);

    try {
      final result = await _exportApi.exportPdf(paperToExport);
      final savedPath = await _fileSaver.savePdf(
        bytes: result.bytes,
        suggestedFilename: result.suggestedFilename,
      );
      if (!mounted) return;
      setState(() => _isExporting = false);
      _showFeedback('Exported PDF: $savedPath');
    } on DocxExportFailure catch (failure) {
      if (!mounted) return;
      setState(() => _isExporting = false);
      _showFeedback(failure.supportDetail, isError: true);
    } on DocxFileSaverException catch (saverError) {
      if (!mounted) return;
      setState(() => _isExporting = false);
      _showFeedback('File save error: ${saverError.message}', isError: true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _isExporting = false);
      _showFeedback('Export failed: $error', isError: true);
    }
  }

  static String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year;
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  Future<void> _handleBack() async {
    if (!_isDirty) {
      Navigator.pop(context);
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved edits'),
        content: const Text(
          'You have unsaved changes in this paper draft. Save your edits or discard them?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'stay'),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Discard edits'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Save & leave'),
          ),
        ],
      ),
    );

    if (!mounted || choice == null || choice == 'stay') return;
    if (choice == 'discard') {
      Navigator.pop(context);
    } else if (choice == 'save') {
      await _saveManualEdits();
      if (!_isDirty && mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _handleBack();
        },
        child: Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            leadingWidth: 36,
            leading: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back',
              onPressed: _handleBack,
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Paper draft',
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Expanded(
                      child: _buildCompactVersionSelector(),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: _isSaving
                            ? Colors.blue.shade50
                            : (_isDirty ? Colors.amber.shade100 : Colors.green.shade50),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _isSaving ? 'Saving…' : (_isDirty ? 'Unsaved' : 'Saved'),
                        key: const ValueKey('save-status-badge'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _isSaving
                              ? Colors.blue.shade800
                              : (_isDirty ? Colors.amber.shade900 : Colors.green.shade800),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(38),
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(vertical: 3),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SegmentedButton<PaperWorkspaceMode>(
                    key: const ValueKey('segmented-workspace-mode'),
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: WidgetStateProperty.all(
                        const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                    segments: const [
                      ButtonSegment(
                        value: PaperWorkspaceMode.document,
                        label: Text('Read (DOCX)', style: TextStyle(fontSize: 12)),
                        icon: Icon(Icons.article_outlined, size: 16),
                      ),
                      ButtonSegment(
                        value: PaperWorkspaceMode.pdf,
                        label: Text('View as PDF', style: TextStyle(fontSize: 12)),
                        icon: Icon(Icons.picture_as_pdf_outlined, size: 16),
                      ),
                      ButtonSegment(
                        value: PaperWorkspaceMode.editor,
                        label: Text('Edit & Outline', style: TextStyle(fontSize: 12)),
                        icon: Icon(Icons.edit_note, size: 16),
                      ),
                    ],
                    selected: {_workspaceMode},
                    onSelectionChanged: (newSelection) {
                      setState(() => _workspaceMode = newSelection.first);
                    },
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                key: const ValueKey('button-readiness-review'),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: const Icon(Icons.fact_check_outlined, size: 19),
                tooltip: 'Manuscript readiness review',
                onPressed: _openReadinessReview,
              ),
              IconButton(
                key: const ValueKey('button-compare-source'),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: const Icon(Icons.source_outlined, size: 19),
                tooltip: 'Compare source draft',
                onPressed: _compareSourceDraft,
              ),
              IconButton(
                key: const ValueKey('button-version-history'),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: const Icon(Icons.history, size: 19),
                tooltip: 'Version history',
                onPressed: _openVersionHistory,
              ),
              IconButton(
                key: const ValueKey('button-export-docx'),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: _isExporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_download_outlined, size: 19),
                tooltip: 'Export DOCX',
                onPressed: _isExporting ? null : _exportDocx,
              ),
              IconButton(
                key: const ValueKey('button-export-pdf'),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: _isExporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined, size: 19),
                tooltip: 'Export PDF',
                onPressed: _isExporting ? null : _exportPdf,
              ),
              IconButton(
                key: const ValueKey('button-save-edits'),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 19),
                tooltip: 'Save edits',
                onPressed: _isSaving ? null : _saveManualEdits,
              ),
            ],
          ),
          body: IndexedStack(
            key: const ValueKey('workspace-indexed-stack'),
            index: _workspaceMode == PaperWorkspaceMode.editor
                ? 0
                : (_workspaceMode == PaperWorkspaceMode.pdf ? 2 : 1),
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 960;
                  final editorContent = Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 840),
                      child: ListView(
                        controller: _scrollController,
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.all(ResbudDesignTokens.pagePadding),
                        children: [
                          _buildCompletionStatusBanner(),
                          _buildIntegrityBanner(),
                          const SizedBox(height: ResbudDesignTokens.contentSpacing),
                          _buildReviewWarningsSummary(),
                          const SizedBox(height: ResbudDesignTokens.contentSpacing),
                          _buildPaperHeaderCard(),
                          const SizedBox(height: ResbudDesignTokens.contentSpacing),
                          _buildSectionsList(),
                          const SizedBox(height: ResbudDesignTokens.contentSpacing),
                          _buildReferencesCard(),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  );

                  if (isWide) {
                    return Row(
                      children: [
                        SizedBox(
                          width: 250,
                          child: _buildOutlineRail(context),
                        ),
                        const VerticalDivider(width: 1, thickness: 1),
                        Expanded(child: editorContent),
                      ],
                    );
                  }

                  return editorContent;
                },
              ),
              DocxViewer(
                key: ValueKey('docx-viewer-${_currentVersion.id}'),
                paper: _paper,
                exportApi: _exportApi,
                fileSaver: _fileSaver,
                onDownload: _exportDocx,
                onDownloadPdf: _exportPdf,
                onSwitchToPdf: () => setState(() => _workspaceMode = PaperWorkspaceMode.pdf),
                onSwitchToEdit: () => setState(() => _workspaceMode = PaperWorkspaceMode.editor),
              ),
              PdfViewer(
                key: ValueKey('pdf-viewer-${_currentVersion.id}'),
                paper: _paper,
                exportApi: _exportApi,
                fileSaver: _fileSaver,
                onDownload: _exportDocx,
                onDownloadPdf: _exportPdf,
                onSwitchToDocx: () => setState(() => _workspaceMode = PaperWorkspaceMode.document),
                onSwitchToEdit: () => setState(() => _workspaceMode = PaperWorkspaceMode.editor),
              ),
            ],
          ),
        ),
      );

  Widget _buildIntegrityBanner() => Card(
        color: Colors.blueGrey.shade50,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.shield_outlined, color: Colors.blueGrey.shade700),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Resbud highlights structural gaps and missing evidence from your input. It does not perform automated citation verification, plagiarism checks, or proof of scientific correctness. Verify all claims independently.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.blueGrey.shade900,
                      ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildReviewWarningsSummary() {
    final warnings = _paper.reviewWarnings;
    return Card(
      key: const ValueKey('review-warnings-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  warnings.isEmpty ? Icons.check_circle_outline : Icons.warning_amber_outlined,
                  color: warnings.isEmpty ? Colors.green : Colors.amber.shade800,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    warnings.isEmpty
                        ? 'No review warnings'
                        : 'Review warnings (${warnings.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final warning in warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _severityBadge(warning.severity),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              warning.message,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                      if (warning.sectionId != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            key: ValueKey('jump-${warning.sectionId}'),
                            onPressed: () => _jumpToSection(warning.sectionId!),
                            icon: const Icon(Icons.arrow_downward, size: 14),
                            label: const Text('Go to section'),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _severityBadge(String severity) {
    final color = switch (severity) {
      'critical' => Colors.red.shade700,
      'warning' => Colors.amber.shade900,
      _ => Colors.blue.shade700,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Text(
        severity.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildPaperHeaderCard() => Card(
        key: _abstractKey,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                key: const ValueKey('paper-title-input'),
                controller: _titleController,
                maxLength: 300,
                decoration: const InputDecoration(
                  labelText: 'Paper title',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('paper-abstract-input'),
                controller: _abstractController,
                maxLength: 6000,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Abstract',
                ),
              ),
              if (_paper.keywords.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Keywords', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final kw in _paper.keywords)
                      Chip(
                        label: Text(kw),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );

  Widget _buildSectionsList() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  'Paper sections (${_paper.sections.length})',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                TextButton.icon(
                  key: const ValueKey('button-manuscript-outline'),
                  onPressed: () => _openOutlineSheet(context),
                  icon: const Icon(Icons.list_alt, size: 18),
                  label: const Text('Outline / Jump'),
                ),
              ],
            ),
          ),
          for (final section in _paper.sections) _buildSectionCard(section),
        ],
      );

  Widget _buildSectionCard(PaperSectionPayload section) {
    final isRegenerating = _activeRegeneratingSectionId == section.id;
    final controller = _sectionControllers[section.id];
    final isNeedsInput = section.state == 'needs_input';
    final isNotApplicable = section.state == 'not_applicable';
    final isEdited = controller != null && controller.text != section.content;
    final sectionWarnings = _paper.reviewWarnings.where((w) => w.sectionId == section.id).toList();

    return Card(
      key: _sectionKeys[section.id],
      margin: const EdgeInsets.only(bottom: 16),
      color: isNeedsInput ? const Color(0xFFFFFBEB) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    section.heading,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                if (isEdited) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.withAlpha(30),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Edited',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                  ),
                ],
                _sectionStateBadge(section.state),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'ID: ${section.id}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
            if (sectionWarnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (var wIdx = 0; wIdx < sectionWarnings.length; wIdx++)
                Container(
                  key: wIdx == 0
                      ? ValueKey('inline-warning-${section.id}')
                      : ValueKey('inline-warning-${section.id}-$wIdx'),
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: sectionWarnings[wIdx].severity == 'critical'
                        ? Colors.red.withAlpha(20)
                        : Colors.amber.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: sectionWarnings[wIdx].severity == 'critical'
                          ? Colors.red.shade300
                          : Colors.amber.shade400,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: sectionWarnings[wIdx].severity == 'critical'
                                ? Colors.red.shade800
                                : Colors.amber.shade900,
                          ),
                          const SizedBox(width: 6),
                          _severityBadge(sectionWarnings[wIdx].severity),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              sectionWarnings[wIdx].message,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                color: sectionWarnings[wIdx].severity == 'critical'
                                    ? Colors.red.shade900
                                    : Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Academic Guidance: Supply verifiable methodology or experimental results from your study. Resbud will never fabricate ungrounded measurements.',
                        style: TextStyle(
                          fontSize: 11,
                          color: sectionWarnings[wIdx].severity == 'critical'
                              ? Colors.red.shade800
                              : Colors.amber.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (isNeedsInput && sectionWarnings.isEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.amber.shade900),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This section is flagged as needing additional input or evidence.',
                        style: TextStyle(color: Colors.amber.shade900, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              key: ValueKey('section-content-${section.id}'),
              controller: controller,
              minLines: 4,
              maxLines: null,
              maxLength: 25000000,
              buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
              decoration: InputDecoration(
                labelText: 'Content (${section.heading})',
                hintText: isNotApplicable
                    ? 'Section marked not applicable.'
                    : 'Enter section content…',
                alignLabelWithHint: true,
              ),
            ),
            if (_previewingSectionIds.contains(section.id)) ...[
              Container(
                key: ValueKey('section-preview-${section.id}'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.preview, size: 14, color: Colors.blueGrey),
                        const SizedBox(width: 6),
                        Text(
                          'Rendered Mathematics & Formatting Preview',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey.shade700,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 12),
                    DocxDocumentCanvas(
                      paper: _paper.copyWith(
                        sections: [
                          section.copyWith(
                            content: controller?.text ?? section.content,
                          ),
                        ],
                      ),
                      zoom: 1.0,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 6,
              children: [
                if (!isNotApplicable) ...[
                  TextButton.icon(
                    key: ValueKey('button-preview-math-${section.id}'),
                    onPressed: () {
                      setState(() {
                        if (_previewingSectionIds.contains(section.id)) {
                          _previewingSectionIds.remove(section.id);
                        } else {
                          _previewingSectionIds.add(section.id);
                        }
                      });
                    },
                    icon: Icon(
                      _previewingSectionIds.contains(section.id)
                          ? Icons.edit_note
                          : Icons.functions,
                      size: 16,
                    ),
                    label: Text(
                      _previewingSectionIds.contains(section.id)
                          ? 'Hide Preview'
                          : 'Preview Equations',
                    ),
                  ),
                  TextButton.icon(
                    key: ValueKey('button-insert-figure-${section.id}'),
                    onPressed: () => _pickAndInsertFigure(section),
                    icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
                    label: const Text('Insert Figure'),
                  ),
                  TextButton.icon(
                    key: ValueKey('button-revert-${section.id}'),
                    onPressed: () => _revertSection(section),
                    icon: const Icon(Icons.undo, size: 16),
                    label: const Text('Revert to saved'),
                  ),
                  FilledButton.tonalIcon(
                    key: ValueKey('button-regen-${section.id}'),
                    onPressed: isRegenerating
                        ? null
                        : () => _startSectionRegeneration(section),
                    icon: isRegenerating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    label: Text(
                      isRegenerating ? 'Regenerating…' : 'Regenerate section',
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionStateBadge(String state) {
    final (label, color) = switch (state) {
      'needs_input' => ('Needs input', Colors.amber.shade900),
      'not_applicable' => ('Not applicable', Colors.grey.shade700),
      _ => ('Draft', Colors.blue.shade700),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildReferencesCard() => Card(
        key: _referencesKey,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'References (${_paper.references.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Supplied references are authoritative and preserved across section updates.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (_paper.references.isEmpty)
                const Text('No references recorded for this draft.')
              else
                for (final ref in _paper.references)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '[${ref.id}] ',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Expanded(
                          child: SelectableText(ref.text),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      );

  static String _versionSubtitle(PaperVersion version) {
    final restoredFrom = version.metadata?['restored_from_version_number'];
    final origin = _originLabel(version.origin);
    if (restoredFrom != null) {
      return 'v${version.versionNumber} · $origin (restored from v$restoredFrom)';
    }
    return 'v${version.versionNumber} · $origin';
  }

  static String _originLabel(PaperVersionOrigin origin) => switch (origin) {
        PaperVersionOrigin.generation => 'Full Generation',
        PaperVersionOrigin.sectionAcceptance => 'Section Regeneration',
        PaperVersionOrigin.manualEdit => 'Manual Edit',
        PaperVersionOrigin.import => 'Imported',
      };
}

class _RegenerationPromptDialog extends StatefulWidget {
  const _RegenerationPromptDialog({required this.section});

  final PaperSectionPayload section;

  @override
  State<_RegenerationPromptDialog> createState() => _RegenerationPromptDialogState();
}

class _RegenerationPromptDialogState extends State<_RegenerationPromptDialog> {
  late final TextEditingController _instructionController;

  @override
  void initState() {
    super.initState();
    _instructionController = TextEditingController();
  }

  @override
  void dispose() {
    _instructionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Regenerate ${widget.section.heading}'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Current section content:',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: SingleChildScrollView(
                    child: Text(
                      widget.section.content.trim().isEmpty
                          ? '[Section has no content]'
                          : widget.section.content,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('regeneration-instructions'),
                  controller: _instructionController,
                  maxLength: 2000,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Specific instructions (optional)',
                    hintText: 'e.g. Expand methodology details, focus on constraints',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Generation creates a proposal. Non-target sections and references will remain unchanged unless you accept.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(
              context,
              _instructionController.text.trim(),
            ),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Generate proposal'),
          ),
        ],
      );
}
