import 'package:flutter/material.dart';

import '../../data/local_project_repository.dart';
import '../export/docx_export_client.dart';
import '../export/docx_file_saver.dart';
import '../generation/generation_api_client.dart';
import '../generation/generation_models.dart';
import '../../shared/design_tokens.dart';

enum _RegenerationReviewChoice { reject, accept }

class PaperEditorPage extends StatefulWidget {
  const PaperEditorPage({
    super.key,
    required this.repository,
    required this.generationApi,
    required this.project,
    required this.initialVersion,
    this.exportApi,
    this.fileSaver,
  });

  final LocalProjectRepository repository;
  final PaperGenerationApi generationApi;
  final LocalProject project;
  final PaperVersion initialVersion;
  final PaperExportApi? exportApi;
  final DocxFileSaver? fileSaver;

  @override
  State<PaperEditorPage> createState() => _PaperEditorPageState();
}

class _PaperEditorPageState extends State<PaperEditorPage> {
  final _scrollController = ScrollController();
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

  @override
  void initState() {
    super.initState();
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
                Text(
                  'Proposed replacement content:',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.teal.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: SingleChildScrollView(
                    child: Text(
                      replacement.content,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
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
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Paper draft',
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        _versionSubtitle(_currentVersion),
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: _isDirty ? Colors.amber.shade100 : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _isDirty ? 'Unsaved' : 'Saved',
                        key: const ValueKey('save-status-badge'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _isDirty ? Colors.amber.shade900 : Colors.green.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              IconButton(
                key: const ValueKey('button-compare-source'),
                icon: const Icon(Icons.source_outlined),
                tooltip: 'Compare source draft',
                onPressed: _compareSourceDraft,
              ),
              IconButton(
                key: const ValueKey('button-version-history'),
                icon: const Icon(Icons.history),
                tooltip: 'Version history',
                onPressed: _openVersionHistory,
              ),
              IconButton(
                key: const ValueKey('button-export-docx'),
                icon: _isExporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_download_outlined),
                tooltip: 'Export DOCX',
                onPressed: _isExporting ? null : _exportDocx,
              ),
              IconButton(
                key: const ValueKey('button-save-edits'),
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                tooltip: 'Save edits',
                onPressed: _isSaving ? null : _saveManualEdits,
              ),
            ],
          ),
          body: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(ResbudDesignTokens.pagePadding),
            children: [
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
            child: Text(
              'Paper sections (${_paper.sections.length})',
              style: Theme.of(context).textTheme.titleLarge,
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
            if (isNeedsInput) ...[
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
              maxLength: 30000,
              decoration: InputDecoration(
                labelText: 'Content (${section.heading})',
                hintText: isNotApplicable
                    ? 'Section marked not applicable.'
                    : 'Enter section content…',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!isNotApplicable)
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
