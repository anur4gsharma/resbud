import 'package:flutter/material.dart';

/// Standardized, compact text input field with clear labeling and error states.
class ResbudTextField extends StatelessWidget {
  const ResbudTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hintText,
    this.helperText,
    this.errorText,
    this.maxLength,
    this.minLines = 1,
    this.maxLines,
    this.requiredField = false,
    this.readOnly = false,
    this.prefixIcon,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.keyName,
  });

  final TextEditingController controller;
  final String label;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final int? maxLength;
  final int minLines;
  final int? maxLines;
  final bool requiredField;
  final bool readOnly;
  final IconData? prefixIcon;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? keyName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final key = keyName != null ? ValueKey(keyName!) : null;

    final effectiveMaxLines = maxLines ?? (minLines > 1 ? minLines + 2 : 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          key: key,
          controller: controller,
          readOnly: readOnly,
          minLines: minLines,
          maxLines: effectiveMaxLines,
          maxLength: maxLength,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 13,
            height: 1.4,
          ),
          decoration: InputDecoration(
            isDense: true,
            labelText: requiredField ? '$label *' : label,
            hintText: hintText,
            helperText: helperText,
            errorText: errorText,
            prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 18) : null,
            suffix: suffix,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            counterStyle: const TextStyle(fontSize: 10),
          ),
        ),
      ],
    );
  }
}
