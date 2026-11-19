import 'package:flutter/material.dart';
import '../generation/generation_models.dart';
import '../readiness/manuscript_readiness_service.dart';

/// Consolidated research-review panel for academic manuscripts.
/// Groups deterministic findings across:
/// - Missing research information
/// - Unverified references & citation issues
/// - Unsupported claims
/// - Missing figure placements
/// - Unresolved author metadata
/// - Unfinished sections
/// Every warning provides clear navigation to its relevant section without injecting editorial notes into prose.
class ManuscriptReviewPanel extends StatelessWidget {
  const ManuscriptReviewPanel({
    super.key,
    required this.paper,
    required this.projectContext,
    required this.includeReviewNotesAppendix,
    required this.onJumpToSection,
    required this.onToggleAppendix,
  });

  final PaperDraftPayload paper;
  final Map<String, Object?>? projectContext;
  final bool includeReviewNotesAppendix;
  final void Function(String sectionId) onJumpToSection;
  final void Function(bool value) onToggleAppendix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    const readinessService = ManuscriptReadinessService();
    final report = readinessService.evaluate(
      paper: paper,
      projectContext: projectContext,
    );

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Overall Readiness Summary Card
        Card(
          elevation: 0,
          color: isDark ? Colors.grey.shade900 : Colors.blueGrey.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      report.hasCriticalIssues
                          ? Icons.warning_amber_rounded
                          : (report.hasIssues ? Icons.info_outline : Icons.check_circle_outline),
                      color: report.hasCriticalIssues
                          ? Colors.red
                          : (report.hasIssues ? Colors.amber.shade800 : Colors.green),
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        report.hasCriticalIssues
                          ? 'Critical Manuscript Issues Identified'
                          : (report.hasIssues ? 'Review Findings & Academic Guidance' : 'Manuscript Structurally Complete'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Deterministic inspection evaluated ${report.sectionsCount} sections, ${report.referencesCount} references, and ~${report.totalWords} words.',
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _MetricChip(
                      label: '${report.criticalFindings.length} Critical',
                      color: Colors.red,
                    ),
                    _MetricChip(
                      label: '${report.warningFindings.length} Warnings',
                      color: Colors.amber.shade800,
                    ),
                    _MetricChip(
                      label: '${report.infoFindings.length} Info',
                      color: Colors.blueGrey,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Export Setting Card
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: SwitchListTile(
            dense: true,
            title: const Text(
              'Include Review Notes Appendix in Export',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Appends review warnings to DOCX/PDF export. Warnings are always preserved in this panel regardless of this switch.',
              style: TextStyle(fontSize: 11),
            ),
            value: includeReviewNotesAppendix,
            onChanged: onToggleAppendix,
          ),
        ),

        const SizedBox(height: 14),

        if (report.findings.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(Icons.verified_outlined, size: 40, color: Colors.green),
                  const SizedBox(height: 8),
                  const Text('No unresolved review warnings.', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('All sections, references, and headings satisfy structural checks.', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          )
        else ...[
          // Group 1: Critical Missing Info
          if (report.criticalFindings.isNotEmpty) ...[
            _buildSectionHeader('CRITICAL ISSUES (${report.criticalFindings.length})', Colors.red),
            for (final finding in report.criticalFindings)
              _buildFindingCard(context, finding),
            const SizedBox(height: 10),
          ],

          // Group 2: Research Completeness & Citations
          if (report.warningFindings.isNotEmpty) ...[
            _buildSectionHeader('RESEARCH INTEGRITY & CITATIONS (${report.warningFindings.length})', Colors.amber.shade800),
            for (final finding in report.warningFindings)
              _buildFindingCard(context, finding),
            const SizedBox(height: 10),
          ],

          // Group 3: Editorial & Formatting
          if (report.infoFindings.isNotEmpty) ...[
            _buildSectionHeader('EDITORIAL & FORMATTING (${report.infoFindings.length})', Colors.blueGrey),
            for (final finding in report.infoFindings)
              _buildFindingCard(context, finding),
          ],
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.6,
          color: color,
        ),
      ),
    );
  }

  Widget _buildFindingCard(BuildContext context, ReadinessFinding finding) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final badgeColor = switch (finding.severity) {
      ReadinessSeverity.critical => Colors.red,
      ReadinessSeverity.warning => Colors.amber.shade800,
      ReadinessSeverity.info => Colors.blueGrey,
    };

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: badgeColor.withValues(alpha: 0.4),
          width: 0.9,
        ),
      ),
      color: isDark ? Colors.grey.shade900 : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    finding.severity.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: badgeColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    finding.title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              finding.explanation,
              style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
            ),
            if (finding.suggestedAction != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lightbulb_outline, size: 14, color: Colors.amber),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Suggested: ${finding.suggestedAction!}',
                        style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: theme.colorScheme.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (finding.sectionId != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: ValueKey('review-jump-${finding.sectionId}'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  ),
                  icon: const Icon(Icons.arrow_forward, size: 14),
                  label: Text('Jump to ${finding.sectionHeading ?? 'section'}', style: const TextStyle(fontSize: 11)),
                  onPressed: () => onJumpToSection(finding.sectionId!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}
