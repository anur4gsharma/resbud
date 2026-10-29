import 'package:flutter/material.dart';
import 'manuscript_readiness_service.dart';

/// Modal bottom sheet or responsive dialog displaying deterministic manuscript readiness.
class ManuscriptReadinessSheet extends StatefulWidget {
  const ManuscriptReadinessSheet({
    super.key,
    required this.report,
    required this.onNavigateToSection,
  });

  final ReadinessReport report;
  final void Function(String sectionId) onNavigateToSection;

  static Future<void> show({
    required BuildContext context,
    required ReadinessReport report,
    required void Function(String sectionId) onNavigateToSection,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => ManuscriptReadinessSheet(
          report: report,
          onNavigateToSection: onNavigateToSection,
        ),
      );

  @override
  State<ManuscriptReadinessSheet> createState() => _ManuscriptReadinessSheetState();
}

class _ManuscriptReadinessSheetState extends State<ManuscriptReadinessSheet> {
  ReadinessCategory? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final report = widget.report;

    final displayedFindings = _selectedCategory == null
        ? report.findings
        : report.byCategory(_selectedCategory!);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 16,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Sheet handle
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.fact_check_outlined,
                    color: report.hasCriticalIssues
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Manuscript Readiness Review',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Structural Checklist: ${report.structuralChecklistPercentage}% complete (${report.completedStructuralItems}/${report.totalStructuralItems} core elements)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('button-close-readiness-sheet'),
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Integrity disclaimer banner
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blueGrey.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined, size: 18, color: Colors.blueGrey.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Deterministic structural review. Does not assert peer-review approval, experimental correctness, or publication readiness.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.blueGrey.shade900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Category filter chips
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  FilterChip(
                    key: const ValueKey('chip-category-all'),
                    label: Text('All (${report.findings.length})'),
                    selected: _selectedCategory == null,
                    onSelected: (_) => setState(() => _selectedCategory = null),
                  ),
                  FilterChip(
                    key: const ValueKey('chip-category-critical'),
                    label: Text('Critical (${report.byCategory(ReadinessCategory.criticalMissing).length})'),
                    selected: _selectedCategory == ReadinessCategory.criticalMissing,
                    selectedColor: Colors.red.shade100,
                    onSelected: (_) => setState(() => _selectedCategory = ReadinessCategory.criticalMissing),
                  ),
                  FilterChip(
                    key: const ValueKey('chip-category-completeness'),
                    label: Text('Completeness (${report.byCategory(ReadinessCategory.researchCompleteness).length})'),
                    selected: _selectedCategory == ReadinessCategory.researchCompleteness,
                    selectedColor: Colors.orange.shade100,
                    onSelected: (_) => setState(() => _selectedCategory = ReadinessCategory.researchCompleteness),
                  ),
                  FilterChip(
                    key: const ValueKey('chip-category-citations'),
                    label: Text('Citations (${report.byCategory(ReadinessCategory.citationAndReferences).length})'),
                    selected: _selectedCategory == ReadinessCategory.citationAndReferences,
                    selectedColor: Colors.blue.shade100,
                    onSelected: (_) => setState(() => _selectedCategory = ReadinessCategory.citationAndReferences),
                  ),
                  FilterChip(
                    key: const ValueKey('chip-category-editorial'),
                    label: Text('Editorial (${report.byCategory(ReadinessCategory.editorialReview).length})'),
                    selected: _selectedCategory == ReadinessCategory.editorialReview,
                    selectedColor: Colors.purple.shade100,
                    onSelected: (_) => setState(() => _selectedCategory = ReadinessCategory.editorialReview),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Findings list
            Expanded(
              child: displayedFindings.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_outline, color: Colors.green, size: 48),
                            const SizedBox(height: 12),
                            Text(
                              'No outstanding issues in this category',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'All evaluated structural and grounding rules have been satisfied.',
                              style: theme.textTheme.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: displayedFindings.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final finding = displayedFindings[index];
                        return _buildFindingCard(context, finding);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFindingCard(BuildContext context, ReadinessFinding finding) {
    final theme = Theme.of(context);

    final (badgeBg, badgeFg, badgeText) = switch (finding.severity) {
      ReadinessSeverity.critical => (Colors.red.shade100, Colors.red.shade900, 'CRITICAL'),
      ReadinessSeverity.warning => (Colors.amber.shade100, Colors.amber.shade900, 'WARNING'),
      ReadinessSeverity.info => (Colors.blue.shade100, Colors.blue.shade900, 'INFO'),
    };

    return Card(
      key: ValueKey('readiness-card-${finding.id}'),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: finding.severity == ReadinessSeverity.critical
              ? Colors.red.shade300
              : Colors.grey.shade300,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: badgeFg,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  finding.code,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (finding.sectionHeading != null)
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        finding.sectionHeading!,
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              finding.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              finding.explanation,
              style: theme.textTheme.bodyMedium,
            ),
            if (finding.suggestedAction != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lightbulb_outline, size: 16, color: Colors.amber),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Remedy: ${finding.suggestedAction}',
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (finding.sectionId != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: ValueKey('button-jump-${finding.id}'),
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onNavigateToSection(finding.sectionId!);
                  },
                  icon: const Icon(Icons.arrow_downward, size: 16),
                  label: Text('Jump to "${finding.sectionHeading ?? 'section'}"'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
