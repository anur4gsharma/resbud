import 'package:flutter/material.dart';
import '../../features/generation/generation_models.dart';
import '../../features/project_input/author_affiliation_validator.dart';
import '../design_tokens.dart';

/// Responsive author and affiliation management widget supporting IEEE attribution.
/// Guarantees zero horizontal overflow across 320px–430px mobile viewports.
/// Fully dynamic: supports arbitrary author counts (1, 2, 3, 5, 8, 12+), automatic superscript numbering,
/// reordering, inline affiliation assignment, and comprehensive validation.
class ResbudAuthorSection extends StatelessWidget {
  const ResbudAuthorSection({
    super.key,
    required this.authors,
    required this.affiliations,
    required this.onAddAuthor,
    required this.onAddAffiliation,
    required this.onRemoveAuthor,
    required this.onRemoveAffiliation,
    this.onEditAuthor,
    this.onEditAffiliation,
    this.onMoveAuthor,
    required this.onPrefillAuthors,
    this.validationReport,
    this.addAuthorKey = 'button-add-author',
    this.addAffiliationKey = 'button-add-affiliation',
    this.prefillKey = 'button-prefill-ieee-authors',
  });

  final List<AuthorMetadataPayload> authors;
  final List<AuthorAffiliationPayload> affiliations;
  final VoidCallback onAddAuthor;
  final VoidCallback onAddAffiliation;
  final void Function(int index) onRemoveAuthor;
  final void Function(int index) onRemoveAffiliation;
  final void Function(int index)? onEditAuthor;
  final void Function(int index)? onEditAffiliation;
  final void Function(int index, int delta)? onMoveAuthor;
  final VoidCallback onPrefillAuthors;
  final AuthorAffiliationValidationReport? validationReport;
  final String addAuthorKey;
  final String addAffiliationKey;
  final String prefillKey;

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
            // Responsive Header
            Row(
              children: [
                Icon(Icons.people_alt_outlined, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Authors & Affiliations',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${authors.length} author${authors.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Configure IEEE conference authors, affiliation superscripts, and contact info.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),

            // Validation report feedback
            if (validationReport != null && validationReport!.issues.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildValidationBanner(context, validationReport!),
            ],

            const SizedBox(height: 10),

            // Action Buttons Wrap (No horizontal overflow)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  key: ValueKey(addAuthorKey),
                  onPressed: onAddAuthor,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: const Size(0, 32),
                  ),
                  icon: const Icon(Icons.person_add, size: 15),
                  label: const Text('+ Add Author', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                OutlinedButton.icon(
                  key: ValueKey(addAffiliationKey),
                  onPressed: onAddAffiliation,
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: const Size(0, 32),
                  ),
                  icon: const Icon(Icons.account_balance_outlined, size: 15),
                  label: const Text('+ Add Affiliation', style: TextStyle(fontSize: 12)),
                ),
                TextButton.icon(
                  key: ValueKey(prefillKey),
                  onPressed: onPrefillAuthors,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    minimumSize: const Size(0, 32),
                  ),
                  icon: const Icon(Icons.playlist_add_check, size: 15),
                  label: const Text('Load example author configuration', style: TextStyle(fontSize: 11.5)),
                ),
              ],
            ),

            // Affiliations Section
            if (affiliations.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    'AFFILIATIONS (${affiliations.length})',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '• superscripts automatically numbered',
                    style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              for (var i = 0; i < affiliations.length; i++) ...[
                _buildAffiliationCard(context, i),
                if (i < affiliations.length - 1) const SizedBox(height: 6),
              ],
            ],

            // Authors Section
            const SizedBox(height: 14),
            Text(
              'AUTHORS (${authors.length})',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 6),

            if (authors.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? ResbudDesignTokens.warningBgDark : ResbudDesignTokens.warningBgLight,
                  borderRadius: BorderRadius.circular(ResbudDesignTokens.radiusSmall),
                  border: Border.all(
                    color: isDark ? ResbudDesignTokens.warningBorderDark : ResbudDesignTokens.warningBorderLight,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: isDark ? ResbudDesignTokens.warningTextDark : ResbudDesignTokens.warningTextLight,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No authors added yet. Tap "+ Add Author" or "Load example author configuration" to configure attribution.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? ResbudDesignTokens.warningTextDark : ResbudDesignTokens.warningTextLight,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: authors.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _buildAuthorCard(context, i),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildValidationBanner(BuildContext context, AuthorAffiliationValidationReport report) {
    final theme = Theme.of(context);
    final hasErrors = report.errors.isNotEmpty;
    final color = hasErrors ? theme.colorScheme.error : Colors.amber.shade800;
    final bgColor = hasErrors
        ? theme.colorScheme.errorContainer.withValues(alpha: 0.25)
        : Colors.amber.shade100.withValues(alpha: 0.35);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(ResbudDesignTokens.radiusSmall),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(hasErrors ? Icons.error_outline : Icons.warning_amber_outlined, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                hasErrors ? 'Author Validation Issues' : 'Author Configuration Notices',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final issue in report.issues)
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 2),
              child: Text(
                '• ${issue.message}',
                style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAffiliationCard(BuildContext context, int index) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final aff = affiliations[index];

    // Find authors using this affiliation
    final users = authors.where((a) => a.affiliationIds.contains(aff.id)).map((a) => a.name.trim()).toList();

    final locationParts = [
      if (aff.city != null && aff.city!.trim().isNotEmpty) aff.city!.trim(),
      if (aff.state != null && aff.state!.trim().isNotEmpty) aff.state!.trim(),
      if (aff.country != null && aff.country!.trim().isNotEmpty) aff.country!.trim(),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? ResbudDesignTokens.surfaceSubtleDark : ResbudDesignTokens.surfaceSubtleLight,
        borderRadius: BorderRadius.circular(ResbudDesignTokens.radiusSmall),
        border: Border.all(
          color: isDark ? ResbudDesignTokens.borderDark : ResbudDesignTokens.borderLight,
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '[${index + 1}]',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  aff.institution,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
                if (aff.department != null && aff.department!.trim().isNotEmpty)
                  Text(
                    aff.department!.trim(),
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, fontStyle: FontStyle.italic),
                    overflow: TextOverflow.ellipsis,
                  ),
                if (locationParts.isNotEmpty)
                  Text(
                    locationParts.join(', '),
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 10.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 2),
                Text(
                  users.isNotEmpty
                      ? 'Used by: ${users.join(', ')}'
                      : 'Unassigned (not referenced by any author)',
                  style: TextStyle(
                    fontSize: 10,
                    color: users.isNotEmpty ? theme.colorScheme.primary : theme.colorScheme.outline,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (onEditAffiliation != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: const Icon(Icons.edit_outlined, size: 16),
              tooltip: 'Edit affiliation',
              onPressed: () => onEditAffiliation!(index),
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
            tooltip: 'Remove affiliation',
            onPressed: () => onRemoveAffiliation(index),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthorCard(BuildContext context, int index) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final author = authors[index];

    // Compute automatic superscript notation
    String superscriptStr = '';
    if (affiliations.length > 1 && author.affiliationIds.isNotEmpty) {
      final numbers = author.affiliationIds
          .map((id) {
            final affIdx = affiliations.indexWhere((a) => a.id == id);
            return affIdx >= 0 ? '${affIdx + 1}' : '';
          })
          .where((s) => s.isNotEmpty)
          .join(',');
      if (numbers.isNotEmpty) {
        superscriptStr = toSuperscriptDigits(numbers);
      }
    }
    if (author.isCorresponding) {
      superscriptStr += '*';
    }

    // Affiliation labels
    final affLabels = author.affiliationIds
        .map((id) {
          final affIdx = affiliations.indexWhere((a) => a.id == id);
          if (affIdx >= 0) {
            final aff = affiliations[affIdx];
            final dept = aff.department?.trim();
            return '[${affIdx + 1}] ${dept != null && dept.isNotEmpty ? '$dept, ' : ''}${aff.institution}';
          }
          return '[$id]';
        })
        .toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? ResbudDesignTokens.surfaceSubtleDark : ResbudDesignTokens.surfaceSubtleLight,
        borderRadius: BorderRadius.circular(ResbudDesignTokens.radiusSmall),
        border: Border.all(
          color: isDark ? ResbudDesignTokens.borderDark : ResbudDesignTokens.borderLight,
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 11,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text.rich(
                        TextSpan(
                          text: author.name,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          children: [
                            if (superscriptStr.isNotEmpty)
                              TextSpan(
                                text: superscriptStr,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                          ],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (author.isCorresponding) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: Text(
                          '* Corresponding',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Reorder controls
              if (onMoveAuthor != null) ...[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  icon: const Icon(Icons.arrow_upward, size: 15),
                  tooltip: 'Move author up',
                  onPressed: index > 0 ? () => onMoveAuthor!(index, -1) : null,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  icon: const Icon(Icons.arrow_downward, size: 15),
                  tooltip: 'Move author down',
                  onPressed: index < authors.length - 1 ? () => onMoveAuthor!(index, 1) : null,
                ),
              ],
              if (onEditAuthor != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  tooltip: 'Edit author',
                  onPressed: () => onEditAuthor!(index),
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                tooltip: 'Remove author',
                onPressed: () => onRemoveAuthor(index),
              ),
            ],
          ),
          if (author.roleOrTitle != null && author.roleOrTitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              author.roleOrTitle!.trim(),
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, fontStyle: FontStyle.italic),
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (affLabels.isNotEmpty) ...[
            const SizedBox(height: 2),
            for (final label in affLabels)
              Text(
                label,
                style: TextStyle(fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
          ],
          if ((author.email != null && author.email!.trim().isNotEmpty) ||
              (author.orcid != null && author.orcid!.trim().isNotEmpty)) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                if (author.email != null && author.email!.trim().isNotEmpty)
                  Expanded(
                    child: Text(
                      author.email!.trim(),
                      style: TextStyle(fontSize: 10.5, color: theme.colorScheme.primary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (author.orcid != null && author.orcid!.trim().isNotEmpty) ...[
                  if (author.email != null && author.email!.trim().isNotEmpty) const SizedBox(width: 8),
                  Text(
                    'ORCID: ${author.orcid!.trim()}',
                    style: TextStyle(fontSize: 10, color: theme.colorScheme.outline),
                  ),
                ],
              ],
            ),
          ],
          if (author.fundingAcknowledgment != null && author.fundingAcknowledgment!.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Funding: ${author.fundingAcknowledgment!.trim()}',
              style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: theme.colorScheme.outline),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
