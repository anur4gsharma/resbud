import 'package:flutter/material.dart';
import '../generation/generation_models.dart';

/// Interactive manuscript outline navigator and structural organizer.
/// Displays actual document hierarchy: Title, Abstract, Sections, Subsections,
/// embedded Figures, Tables, and References with reordering, renaming, and state indicators.
class ManuscriptOutlineView extends StatelessWidget {
  const ManuscriptOutlineView({
    super.key,
    required this.paper,
    required this.editedSectionIds,
    required this.onSelectSection,
    required this.onMoveSection,
    required this.onRenameSection,
    required this.onAddSection,
    required this.onDeleteSection,
    this.scrollController,
    this.compact = false,
  });

  final PaperDraftPayload paper;
  final Set<String> editedSectionIds;
  final void Function(String sectionId) onSelectSection;
  final void Function(int index, int delta) onMoveSection;
  final void Function(int index, String newHeading) onRenameSection;
  final void Function(String heading) onAddSection;
  final void Function(int index) onDeleteSection;
  final ScrollController? scrollController;
  final bool compact;

  void _showAddSectionDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Add Manuscript Section'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Section Heading *',
            hintText: 'e.g. Experimental Setup & Baseline Models',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Cancel')),
          FilledButton(
            key: const ValueKey('confirm-add-section-button'),
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                Navigator.pop(dlgCtx);
                onAddSection(text);
              }
            },
            child: const Text('Add Section'),
          ),
        ],
      ),
    );
  }

  void _showRenameSectionDialog(BuildContext context, int index, String currentHeading) {
    final controller = TextEditingController(text: currentHeading);
    showDialog<void>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Rename Section Heading'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'New Section Heading *',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty && text != currentHeading) {
                Navigator.pop(dlgCtx);
                onRenameSection(index, text);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSection(BuildContext context, int index, String heading) {
    showDialog<void>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Text('Delete Section "$heading"?'),
        content: const Text(
          'This will remove the section and its contents from the manuscript draft. Unsaved changes to this section will be discarded.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(dlgCtx);
              onDeleteSection(index);
            },
            child: const Text('Delete Section'),
          ),
        ],
      ),
    );
  }

  List<String> _extractSubsections(String content) {
    final lines = content.split('\n');
    final subs = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('### ') || trimmed.startsWith('## ')) {
        final heading = trimmed.replaceFirst(RegExp(r'^#+\s*'), '').trim();
        if (heading.isNotEmpty) {
          subs.add(heading);
        }
      }
    }
    return subs;
  }

  int _countTables(String content) {
    final matches = RegExp(r'\|[^\n]+\|\n\|[\s:-|]+\|').allMatches(content);
    return matches.length;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      children: [
        // Title & Abstract item
        Card(
          elevation: 0,
          color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: ListTile(
            dense: true,
            leading: Icon(Icons.article_outlined, size: 20, color: theme.colorScheme.primary),
            title: const Text(
              'Title & Abstract',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            subtitle: Text(
              paper.title.isNotEmpty ? paper.title : 'Untitled Manuscript',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => onSelectSection('abstract'),
          ),
        ),

        const SizedBox(height: 8),

        // Section header with "+ Add Section" button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'SECTIONS (${paper.sections.length})',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                    color: theme.colorScheme.primary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                key: const ValueKey('button-add-section'),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: const Icon(Icons.add, size: 18),
                tooltip: 'Add Section',
                onPressed: () => _showAddSectionDialog(context),
              ),
            ],
          ),
        ),

        // Sections List
        for (var i = 0; i < paper.sections.length; i++) ...[
          Builder(builder: (context) {
            final section = paper.sections[i];
            final hasWarning = paper.reviewWarnings.any((w) => w.sectionId == section.id);
            final isNeedsInput = section.state == 'needs_input';
            final isNotApplicable = section.state == 'not_applicable';
            final isEdited = editedSectionIds.contains(section.id);
            final subsections = _extractSubsections(section.content);
            final tablesCount = _countTables(section.content);

            final iconColor = hasWarning || isNeedsInput
                ? Colors.amber.shade800
                : (isNotApplicable ? Colors.grey.shade500 : theme.colorScheme.primary);

            return Card(
              elevation: 0,
              margin: const EdgeInsets.symmetric(vertical: 3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: isEdited
                      ? theme.colorScheme.primary.withValues(alpha: 0.6)
                      : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: isEdited ? 1.2 : 0.8,
                ),
              ),
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: CircleAvatar(
                  radius: 12,
                  backgroundColor: iconColor.withValues(alpha: 0.12),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: iconColor,
                    ),
                  ),
                ),
                title: Text(
                  section.heading,
                  key: ValueKey('outline-section-${section.id}'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: hasWarning || isNeedsInput ? FontWeight.bold : FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 4,
                      children: [
                        if (isEdited)
                          const Text('Edited', style: TextStyle(fontSize: 9.5, color: Colors.blue, fontWeight: FontWeight.bold)),
                        if (isNeedsInput)
                          Text('Needs input', style: TextStyle(fontSize: 9.5, color: Colors.amber.shade900)),
                        if (isNotApplicable)
                          const Text('N/A', style: TextStyle(fontSize: 9.5, color: Colors.grey)),
                        if (hasWarning)
                          Text('Review issue', style: TextStyle(fontSize: 9.5, color: Colors.red.shade800, fontWeight: FontWeight.bold)),
                        if (tablesCount > 0)
                          Text('• $tablesCount table${tablesCount == 1 ? '' : 's'}', style: const TextStyle(fontSize: 9.5, color: Colors.grey)),
                      ],
                    ),
                    if (subsections.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Subsections: ${subsections.join(", ")}',
                          style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
                trailing: PopupMenuButton<String>(
                  key: ValueKey('outline-menu-${section.id}'),
                  icon: const Icon(Icons.more_vert, size: 18),
                  padding: EdgeInsets.zero,
                  itemBuilder: (ctx) => [
                    if (i > 0)
                      const PopupMenuItem(
                        value: 'up',
                        child: Row(children: [Icon(Icons.arrow_upward, size: 16), SizedBox(width: 8), Text('Move up')]),
                      ),
                    if (i < paper.sections.length - 1)
                      const PopupMenuItem(
                        value: 'down',
                        child: Row(children: [Icon(Icons.arrow_downward, size: 16), SizedBox(width: 8), Text('Move down')]),
                      ),
                    const PopupMenuItem(
                      value: 'rename',
                      child: Row(children: [Icon(Icons.edit_outlined, size: 16), SizedBox(width: 8), Text('Rename heading')]),
                    ),
                    if (paper.sections.length > 1)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [Icon(Icons.delete_outline, size: 16, color: Colors.red), SizedBox(width: 8), Text('Delete section', style: TextStyle(color: Colors.red))]),
                      ),
                  ],
                  onSelected: (val) {
                    if (val == 'up') onMoveSection(i, -1);
                    if (val == 'down') onMoveSection(i, 1);
                    if (val == 'rename') _showRenameSectionDialog(context, i, section.heading);
                    if (val == 'delete') _confirmDeleteSection(context, i, section.heading);
                  },
                ),
                onTap: () => onSelectSection(section.id),
              ),
            );
          }),
        ],

        const SizedBox(height: 12),

        // References item
        Card(
          elevation: 0,
          color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: ListTile(
            dense: true,
            leading: Icon(Icons.format_list_numbered, size: 20, color: theme.colorScheme.primary),
            title: Text(
              'References (${paper.references.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            subtitle: Text(
              paper.references.isNotEmpty
                  ? '${paper.references.first.text.split('.').first} et al.'
                  : 'No references added yet',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => onSelectSection('references'),
          ),
        ),
      ],
    );
  }
}
