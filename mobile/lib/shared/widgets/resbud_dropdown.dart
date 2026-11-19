import 'package:flutter/material.dart';

/// Standardized dropdown field component preventing horizontal overflow.
class ResbudDropdown<T> extends StatelessWidget {
  const ResbudDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.label,
    this.prefixIcon,
    this.keyName,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String label;
  final IconData? prefixIcon;
  final String? keyName;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      key: keyName != null ? ValueKey(keyName!) : null,
      initialValue: value,
      items: items,
      onChanged: onChanged,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 18) : null,
      ),
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: 13,
      ),
    );
  }
}
