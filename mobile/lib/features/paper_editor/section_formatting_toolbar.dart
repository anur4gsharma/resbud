import 'package:flutter/material.dart';
import '../generation/generation_models.dart';

/// Contextual formatting toolbar for academic manuscript section editing.
/// Compact, responsive, and specifically tuned for phone and tablet screens.
class SectionFormattingToolbar extends StatelessWidget {
  const SectionFormattingToolbar({
    super.key,
    required this.section,
    required this.references,
    required this.onInsertText,
    this.undoController,
  });

  final PaperSectionPayload section;
  final List<ReferencePayload> references;
  final void Function(String text, {int selectionOffset, int selectionLength}) onInsertText;
  final UndoHistoryController? undoController;

  void _showCitationPicker(BuildContext context) {
    if (references.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No references added yet. Add a reference below first.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.format_quote, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Insert In-Text Citation',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(sheetContext),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                itemCount: references.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final ref = references[i];
                  final citationMarker = '[${i + 1}]';
                  final refKey = ref.id.isNotEmpty ? ref.id : '${i + 1}';
                  return ListTile(
                    key: ValueKey('cite-ref-$refKey'),
                    leading: CircleAvatar(
                      radius: 13,
                      child: Text('${i + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    title: Text(
                      ref.text,
                      style: const TextStyle(fontSize: 12.5),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        onInsertText(' $citationMarker ');
                      },
                      child: Text('Insert $citationMarker', style: const TextStyle(fontSize: 11)),
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      onInsertText(' $citationMarker ');
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
          width: 0.8,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Undo / Redo
            if (undoController != null) ...[
              ValueListenableBuilder<UndoHistoryValue>(
                valueListenable: undoController!,
                builder: (context, value, _) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        icon: const Icon(Icons.undo, size: 16),
                        tooltip: 'Undo',
                        onPressed: value.canUndo ? () => undoController!.undo() : null,
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        icon: const Icon(Icons.redo, size: 16),
                        tooltip: 'Redo',
                        onPressed: value.canRedo ? () => undoController!.redo() : null,
                      ),
                      const SizedBox(height: 18, child: VerticalDivider(width: 8)),
                    ],
                  );
                },
              ),
            ],

            // Bold
            _ToolbarButton(
              icon: Icons.format_bold,
              tooltip: 'Bold (**text**)',
              onPressed: () => onInsertText('**bold text**', selectionOffset: -11, selectionLength: 9),
            ),

            // Italic
            _ToolbarButton(
              icon: Icons.format_italic,
              tooltip: 'Italic (*text*)',
              onPressed: () => onInsertText('*italic text*', selectionOffset: -12, selectionLength: 11),
            ),

            // Subheading
            _ToolbarButton(
              icon: Icons.title,
              tooltip: 'Subheading (### Heading)',
              onPressed: () => onInsertText('\n\n### Subheading Title\n', selectionOffset: -18, selectionLength: 16),
            ),

            // Bullet List
            _ToolbarButton(
              icon: Icons.format_list_bulleted,
              tooltip: 'Bulleted List',
              onPressed: () => onInsertText('\n- First point\n- Second point\n'),
            ),

            // Numbered List
            _ToolbarButton(
              icon: Icons.format_list_numbered,
              tooltip: 'Numbered List',
              onPressed: () => onInsertText('\n1. First step\n2. Second step\n'),
            ),

            // Table
            _ToolbarButton(
              icon: Icons.table_chart_outlined,
              tooltip: 'Insert Markdown Table',
              onPressed: () => onInsertText(
                '\n\n| Column 1 | Column 2 | Column 3 |\n| --- | --- | --- |\n| Data A | Data B | Data C |\n| Data D | Data E | Data F |\n\n',
              ),
            ),

            const SizedBox(height: 18, child: VerticalDivider(width: 8)),

            // Inline Math
            _ToolbarButton(
              icon: Icons.superscript,
              tooltip: 'Inline Math (\$x^2\$)',
              onPressed: () => onInsertText(r'$x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$'),
            ),

            // Block Equation
            _ToolbarButton(
              icon: Icons.functions,
              tooltip: 'Display Equation (\$\$...\$\$)',
              onPressed: () => onInsertText(
                '\n\n\$\$\n\\mathcal{L}_{total} = \\mathcal{L}_{task} + \\lambda \\mathcal{L}_{reg}\n\$\$\n\n',
              ),
            ),

            // In-text Citation
            _ToolbarButton(
              icon: Icons.format_quote,
              tooltip: 'Insert Citation [N]',
              onPressed: () => _showCitationPicker(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      icon: Icon(icon, size: 16),
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }
}
