import 'package:flutter/material.dart';
import '../design_tokens.dart';

enum ResbudButtonVariant { primary, tonal, outlined, text, danger }

/// Consistent, compact button component adhering to Resbud's mobile design system.
class ResbudButton extends StatelessWidget {
  const ResbudButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = ResbudButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.isFullWidth = false,
    this.compact = false,
    this.keyName,
  });

  final String label;
  final VoidCallback? onPressed;
  final ResbudButtonVariant variant;
  final IconData? icon;
  final bool isLoading;
  final bool isFullWidth;
  final bool compact;
  final String? keyName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final key = keyName != null ? ValueKey(keyName!) : null;

    final padding = compact
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
        : const EdgeInsets.symmetric(horizontal: 14, vertical: 10);
    final fontSize = compact ? 12.0 : 13.0;

    Widget childContent;
    if (isLoading) {
      childContent = SizedBox(
        width: compact ? 13 : 16,
        height: compact ? 13 : 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: variant == ResbudButtonVariant.primary
              ? Colors.white
              : theme.colorScheme.primary,
        ),
      );
    } else if (icon != null) {
      childContent = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: compact ? 14 : 16),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600)),
        ],
      );
    } else {
      childContent = Text(label, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600));
    }

    Widget button;
    switch (variant) {
      case ResbudButtonVariant.primary:
        button = FilledButton(
          key: key,
          onPressed: isLoading ? null : onPressed,
          style: FilledButton.styleFrom(
            padding: padding,
            minimumSize: Size(compact ? 36 : 40, compact ? 32 : 38),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ResbudDesignTokens.radiusMedium),
            ),
          ),
          child: childContent,
        );
        break;

      case ResbudButtonVariant.tonal:
        button = FilledButton.tonal(
          key: key,
          onPressed: isLoading ? null : onPressed,
          style: FilledButton.styleFrom(
            padding: padding,
            minimumSize: Size(compact ? 36 : 40, compact ? 32 : 38),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ResbudDesignTokens.radiusMedium),
            ),
          ),
          child: childContent,
        );
        break;

      case ResbudButtonVariant.outlined:
        button = OutlinedButton(
          key: key,
          onPressed: isLoading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            padding: padding,
            minimumSize: Size(compact ? 36 : 40, compact ? 32 : 38),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ResbudDesignTokens.radiusMedium),
            ),
          ),
          child: childContent,
        );
        break;

      case ResbudButtonVariant.text:
        button = TextButton(
          key: key,
          onPressed: isLoading ? null : onPressed,
          style: TextButton.styleFrom(
            padding: padding,
            minimumSize: Size(compact ? 32 : 36, compact ? 28 : 32),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ResbudDesignTokens.radiusSmall),
            ),
          ),
          child: childContent,
        );
        break;

      case ResbudButtonVariant.danger:
        button = OutlinedButton(
          key: key,
          onPressed: isLoading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
            side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5)),
            padding: padding,
            minimumSize: Size(compact ? 36 : 40, compact ? 32 : 38),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ResbudDesignTokens.radiusMedium),
            ),
          ),
          child: childContent,
        );
        break;
    }

    if (isFullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}
