import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../data/local_project_repository.dart';
import '../../data/project_figure.dart';
import '../generation/generation_models.dart';

/// Comprehensive figure manager modal for academic manuscripts.
/// Allows previewing figures, editing captions/alt-text, changing placement mode,
/// section association, reordering, removing, and inserting markdown links.
class FigureManagerSheet extends StatefulWidget {
  const FigureManagerSheet({
    super.key,
    required this.projectId,
    required this.sections,
    required this.repository,
    required this.onFiguresUpdated,
    this.onInsertFigureIntoActiveSection,
  });

  final String projectId;
  final List<PaperSectionPayload> sections;
  final LocalProjectRepository repository;
  final VoidCallback onFiguresUpdated;
  final void Function(ProjectFigure figure)? onInsertFigureIntoActiveSection;

  static Future<void> show(
    BuildContext context, {
    required String projectId,
    required List<PaperSectionPayload> sections,
    required LocalProjectRepository repository,
    required VoidCallback onFiguresUpdated,
    void Function(ProjectFigure figure)? onInsertFigureIntoActiveSection,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FigureManagerSheet(
        projectId: projectId,
        sections: sections,
        repository: repository,
        onFiguresUpdated: onFiguresUpdated,
        onInsertFigureIntoActiveSection: onInsertFigureIntoActiveSection,
      ),
    );
  }

  @override
  State<FigureManagerSheet> createState() => _FigureManagerSheetState();
}

class _FigureManagerSheetState extends State<FigureManagerSheet> {
  late Future<List<ProjectFigure>> _figuresFuture;

  @override
  void initState() {
    super.initState();
    _reloadFigures();
  }

  void _reloadFigures() {
    setState(() {
      _figuresFuture = widget.repository.listProjectFigures(widget.projectId);
    });
  }

  Future<void> _editFigure(ProjectFigure fig, List<ProjectFigure> allFigures) async {
    final captionCtrl = TextEditingController(text: fig.caption);
    final altTextCtrl = TextEditingController(text: fig.altText);
    String? selectedSectionId = fig.sectionId;
    FigurePlacement selectedPlacement = fig.placement;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: Text('Edit Figure ${fig.figureNumber}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: captionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Figure Caption *',
                    hintText: 'e.g. Figure 1: Pipeline Architecture',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: altTextCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Accessibility Alt Text',
                    hintText: 'Describe visual elements for screen readers',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Associated Section:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                DropdownButton<String?>(
                  isExpanded: true,
                  value: widget.sections.any((s) => s.id == selectedSectionId)
                      ? selectedSectionId
                      : null,
                  hint: const Text('Global / Unassigned'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Global / Unassigned'),
                    ),
                    for (final sec in widget.sections)
                      DropdownMenuItem<String?>(
                        value: sec.id,
                        child: Text(sec.heading, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (val) => setDlgState(() => selectedSectionId = val),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Placement Width:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                SegmentedButton<FigurePlacement>(
                  segments: const [
                    ButtonSegment(
                      value: FigurePlacement.columnWidth,
                      label: Text('Column Width', style: TextStyle(fontSize: 11)),
                    ),
                    ButtonSegment(
                      value: FigurePlacement.fullWidth,
                      label: Text('Full Width', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                  selected: {selectedPlacement},
                  onSelectionChanged: (newSelection) {
                    setDlgState(() => selectedPlacement = newSelection.first);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(dlgCtx, true),
              child: const Text('Save Figure'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      final updated = fig.copyWith(
        caption: captionCtrl.text.trim(),
        altText: altTextCtrl.text.trim(),
        sectionId: selectedSectionId,
        placement: selectedPlacement,
      );
      final newFigures = allFigures.map((f) => f.id == fig.id ? updated : f).toList();
      await widget.repository.saveProjectFigures(widget.projectId, newFigures);
      widget.onFiguresUpdated();
      _reloadFigures();
    }
  }

  Future<void> _moveFigure(int index, int delta, List<ProjectFigure> figures) async {
    final targetIndex = index + delta;
    if (targetIndex < 0 || targetIndex >= figures.length) return;

    final list = List<ProjectFigure>.from(figures);
    final moved = list.removeAt(index);
    list.insert(targetIndex, moved);

    // Re-number figures sequentially
    final renumbered = <ProjectFigure>[];
    for (var i = 0; i < list.length; i++) {
      renumbered.add(list[i].copyWith(figureNumber: i + 1));
    }

    await widget.repository.saveProjectFigures(widget.projectId, renumbered);
    widget.onFiguresUpdated();
    _reloadFigures();
  }

  Future<void> _deleteFigure(ProjectFigure fig) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Text('Delete Figure ${fig.figureNumber}?'),
        content: Text('Are you sure you want to remove "${fig.filename}"? This will remove the figure asset.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.repository.deleteProjectFigure(widget.projectId, fig.id);
      widget.onFiguresUpdated();
      _reloadFigures();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manuscript Figures & Media', style: TextStyle(fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FutureBuilder<List<ProjectFigure>>(
        future: _figuresFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final figures = snapshot.data ?? [];
          if (figures.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.photo_library_outlined, size: 48, color: theme.colorScheme.outline),
                    const SizedBox(height: 12),
                    const Text(
                      'No figures attached to this project yet.',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Insert figures from the section toolbar or upload figures in Research Inputs.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: figures.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final fig = figures[i];
              final sectionHeading = widget.sections
                  .where((s) => s.id == fig.sectionId)
                  .map((s) => s.heading)
                  .firstOrNull;

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Thumbnail
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          width: 72,
                          height: 72,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: fig.cachedBytes != null
                              ? Image.memory(
                                  fig.cachedBytes!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 28),
                                )
                              : _AsyncThumbnail(
                                  storageKey: fig.storageKey,
                                  repository: widget.repository,
                                ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Metadata & Captions
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Fig. ${fig.figureNumber}',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    fig.filename,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              fig.caption.isNotEmpty ? fig.caption : 'No caption set',
                              style: const TextStyle(fontSize: 11.5),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              children: [
                                Text(
                                  sectionHeading != null ? 'Section: $sectionHeading' : 'Unassigned Section',
                                  style: TextStyle(fontSize: 10, color: theme.colorScheme.primary),
                                ),
                                Text(
                                  '• ${fig.placement == FigurePlacement.fullWidth ? 'Full width' : 'Column width'}',
                                  style: TextStyle(fontSize: 10, color: theme.colorScheme.outline),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Actions
                      Column(
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                icon: const Icon(Icons.arrow_upward, size: 15),
                                tooltip: 'Move up',
                                onPressed: i > 0 ? () => _moveFigure(i, -1, figures) : null,
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                icon: const Icon(Icons.arrow_downward, size: 15),
                                tooltip: 'Move down',
                                onPressed: i < figures.length - 1 ? () => _moveFigure(i, 1, figures) : null,
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                icon: const Icon(Icons.edit_outlined, size: 16),
                                tooltip: 'Edit figure',
                                onPressed: () => _editFigure(fig, figures),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                                tooltip: 'Delete figure',
                                onPressed: () => _deleteFigure(fig),
                              ),
                            ],
                          ),
                          if (widget.onInsertFigureIntoActiveSection != null)
                            TextButton(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                              ),
                              onPressed: () {
                                widget.onInsertFigureIntoActiveSection!(fig);
                                Navigator.pop(context);
                              },
                              child: const Text('Insert', style: TextStyle(fontSize: 10.5)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _AsyncThumbnail extends StatelessWidget {
  const _AsyncThumbnail({
    required this.storageKey,
    required this.repository,
  });

  final String storageKey;
  final LocalProjectRepository repository;

  @override
  Widget build(BuildContext context) {
    if (storageKey.isEmpty) {
      return const Icon(Icons.image, size: 24, color: Colors.grey);
    }

    return FutureBuilder<Uint8List?>(
      future: repository.getFigureBytes(storageKey),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Icon(Icons.photo_outlined, size: 24, color: Colors.grey),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return const Icon(Icons.image, size: 24, color: Colors.grey);
        }
        return Image.memory(bytes, fit: BoxFit.cover);
      },
    );
  }
}
