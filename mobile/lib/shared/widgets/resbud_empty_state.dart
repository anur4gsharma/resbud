import 'package:flutter/material.dart';
import '../design_tokens.dart';

/// Professional empty state component eliminating duplicate CTAs.
class ResbudEmptyState extends StatelessWidget {
  const ResbudEmptyState({
    super.key,
    required this.title,
    required this.description,
    this.icon = Icons.description_outlined,
    this.buttonLabel,
    this.onButtonPressed,
    this.buttonKey,
    this.extraWidget,
  });

  final String title;
  final String description;
  final IconData icon;
  final String? buttonLabel;
  final VoidCallback? onButtonPressed;
  final String? buttonKey;
  final Widget? extraWidget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(ResbudDesignTokens.pagePadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                description,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (buttonLabel != null && onButtonPressed != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                key: buttonKey != null ? ValueKey(buttonKey!) : null,
                onPressed: onButtonPressed,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  minimumSize: const Size(0, 38),
                ),
                icon: const Icon(Icons.add, size: 16),
                label: Text(
                  buttonLabel!,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
            if (extraWidget != null) ...[
              const SizedBox(height: 24),
              extraWidget!,
            ],
          ],
        ),
      ),
    );
  }
}
