import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../design_tokens.dart';

/// Responsive figure management and multimodal image placement widget.
/// Solves header clipping and cramped 3-column mobile layouts.
class ResbudFigureSection extends StatelessWidget {
  const ResbudFigureSection({
    super.key,
    required this.figures,
    required this.sections,
    required this.onAddFigure,
    required this.onAutoPlan,
    required this.onRemoveFigure,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onUpdateFigure,
    this.addFigureKey = 'button-upload-figure',
    this.planFiguresKey = 'button-plan-figures',
  });

  final List<Map<String, dynamic>> figures;
  final List<String> sections;
  final VoidCallback onAddFigure;
  final VoidCallback onAutoPlan;
  final void Function(int index) onRemoveFigure;
  final void Function(int index) onMoveUp;
  final void Function(int index) onMoveDown;
  final void Function(int index, String key, dynamic value) onUpdateFigure;
  final String addFigureKey;
  final String planFiguresKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ResbudDesignTokens.cardRadius),
        side: BorderSide(
          color: isDark ? ResbudDesignTokens.borderDark : ResbudDesignTokens.borderLight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Responsive Header (Title row)
            Row(
              children: [
                Icon(Icons.photo_library_outlined, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Figures & Visual Assets',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${figures.length} figure${figures.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Upload diagrams, benchmark graphs, or schematics. The AI will weave references and discuss them directly in the text.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),

            // Action Buttons Wrap (Guaranteed zero clipping)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  key: ValueKey(addFigureKey),
                  onPressed: onAddFigure,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: const Size(0, 32),
                  ),
                  icon: const Icon(Icons.add_photo_alternate, size: 15),
                  label: const Text('Add Figure', style: TextStyle(fontSize: 12)),
                ),
                if (figures.isNotEmpty)
                  OutlinedButton.icon(
                    key: ValueKey(planFiguresKey),
                    onPressed: onAutoPlan,
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: const Size(0, 32),
                    ),
                    icon: const Icon(Icons.alt_route, size: 15),
                    label: const Text('Auto-Plan Placement', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),

            if (figures.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (var i = 0; i < figures.length; i++) ...[
                _buildFigureCard(context, i, theme, isDark),
                if (i < figures.length - 1) const SizedBox(height: 10),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFigureCard(BuildContext context, int index, ThemeData theme, bool isDark) {
    final fig = figures[index];

    // Decode image bytes if available
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
        color: isDark ? ResbudDesignTokens.surfaceSubtleDark : ResbudDesignTokens.surfaceSubtleLight,
        borderRadius: BorderRadius.circular(ResbudDesignTokens.radiusMedium),
        border: Border.all(
          color: isDark ? ResbudDesignTokens.borderDark : ResbudDesignTokens.borderLight,
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: Thumbnail + Figure Name / Header + Reordering Actions
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: bytes != null
                    ? Image.memory(bytes, width: 44, height: 44, fit: BoxFit.cover)
                    : Container(
                        width: 44,
                        height: 44,
                        color: Colors.grey.shade300,
                        child: const Icon(Icons.image, size: 22, color: Colors.grey),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Figure ${index + 1}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    if (fig['name'] != null)
                      Text(
                        fig['name'] as String,
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                icon: const Icon(Icons.arrow_upward, size: 16),
                tooltip: 'Move Up',
                onPressed: index > 0 ? () => onMoveUp(index) : null,
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                icon: const Icon(Icons.arrow_downward, size: 16),
                tooltip: 'Move Down',
                onPressed: index < figures.length - 1 ? () => onMoveDown(index) : null,
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                tooltip: 'Remove figure',
                onPressed: () => onRemoveFigure(index),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Inputs Area (Full card width for responsive comfort)
          TextFormField(
            initialValue: fig['caption'] as String? ?? '',
            style: const TextStyle(fontSize: 12.5),
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Figure Caption',
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            onChanged: (val) => onUpdateFigure(index, 'caption', val),
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: fig['description'] as String? ?? '',
            style: const TextStyle(fontSize: 12.5),
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Key Takeaways / Description (for AI)',
              hintText: 'e.g. Highlights the convergence speedup...',
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            onChanged: (val) => onUpdateFigure(index, 'description', val),
          ),
          const SizedBox(height: 8),

          // Metadata Controls Wrap
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Section Dropdown
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Section: ', style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
                  DropdownButton<String>(
                    value: (fig['section_id'] as String?) ?? 'auto',
                    isDense: true,
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5),
                    items: [
                      const DropdownMenuItem(value: 'auto', child: Text('Auto (AI planned)')),
                      for (final s in sections)
                        DropdownMenuItem(value: s, child: Text(s.replaceAll('_', ' '))),
                    ],
                    onChanged: (val) => onUpdateFigure(index, 'section_id', val == 'auto' ? null : val),
                  ),
                ],
              ),

              // Layout Dropdown
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Layout: ', style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
                  DropdownButton<String>(
                    value: fig['placement'] as String? ?? 'column_width',
                    isDense: true,
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5),
                    items: const [
                      DropdownMenuItem(value: 'column_width', child: Text('Column Width')),
                      DropdownMenuItem(value: 'full_width', child: Text('Full Page Width')),
                    ],
                    onChanged: (val) {
                      if (val != null) onUpdateFigure(index, 'placement', val);
                    },
                  ),
                ],
              ),

              // Placement Status Chip
              FilterChip(
                visualDensity: VisualDensity.compact,
                label: Text(
                  (fig['placement_status'] == 'approved') ? 'Placement Approved' : 'Review Plan',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: (fig['placement_status'] == 'approved')
                        ? Colors.green.shade900
                        : Colors.blue.shade900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                selected: fig['placement_status'] == 'approved',
                selectedColor: Colors.green.shade100,
                backgroundColor: Colors.blue.shade50,
                checkmarkColor: Colors.green.shade900,
                onSelected: (selected) {
                  onUpdateFigure(index, 'placement_status', selected ? 'approved' : 'assigned');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
