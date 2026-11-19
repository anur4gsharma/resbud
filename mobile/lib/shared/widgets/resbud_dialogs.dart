import 'package:flutter/material.dart';

/// Reusable confirmation dialog adhering to design tokens and keyboard-safe insets.
class ResbudConfirmationDialog extends StatelessWidget {
  const ResbudConfirmationDialog({
    super.key,
    required this.title,
    required this.content,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.isDestructive = false,
    this.confirmKey,
    this.cancelKey,
  });

  final String title;
  final String content;
  final String confirmLabel;
  final String cancelLabel;
  final bool isDestructive;
  final String? confirmKey;
  final String? cancelKey;

  static Future<bool?> show({
    required BuildContext context,
    required String title,
    required String content,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool isDestructive = false,
    String? confirmKey,
    String? cancelKey,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => ResbudConfirmationDialog(
        title: title,
        content: content,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        isDestructive: isDestructive,
        confirmKey: confirmKey,
        cancelKey: cancelKey,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
      content: Text(
        content,
        style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13, height: 1.4),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      actions: [
        TextButton(
          key: cancelKey != null ? ValueKey(cancelKey!) : null,
          onPressed: () => Navigator.pop(context, false),
          child: Text(cancelLabel, style: const TextStyle(fontSize: 12.5)),
        ),
        FilledButton(
          key: confirmKey != null ? ValueKey(confirmKey!) : null,
          style: FilledButton.styleFrom(
            backgroundColor: isDestructive ? theme.colorScheme.error : null,
            foregroundColor: isDestructive ? Colors.white : null,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            minimumSize: const Size(0, 36),
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
