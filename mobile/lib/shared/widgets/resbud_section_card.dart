import 'package:flutter/material.dart';
import '../design_tokens.dart';

/// Reusable section container for structured multi-section mobile interfaces.
/// Supports collapsibility, responsive headers, badges, and trailing actions without overflow.
class ResbudSectionCard extends StatefulWidget {
  const ResbudSectionCard({
    super.key,
    required this.title,
    required this.children,
    this.sectionNumber,
    this.subtitle,
    this.icon,
    this.badge,
    this.actions,
    this.isCollapsible = false,
    this.initiallyExpanded = true,
    this.keyName,
  });

  final String title;
  final List<Widget> children;
  final String? sectionNumber;
  final String? subtitle;
  final IconData? icon;
  final Widget? badge;
  final List<Widget>? actions;
  final bool isCollapsible;
  final bool initiallyExpanded;
  final String? keyName;

  @override
  State<ResbudSectionCard> createState() => _ResbudSectionCardState();
}

class _ResbudSectionCardState extends State<ResbudSectionCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  void _toggleExpanded() {
    if (!widget.isCollapsible) return;
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      key: widget.keyName != null ? ValueKey(widget.keyName!) : null,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ResbudDesignTokens.cardRadius),
        side: BorderSide(
          color: isDark ? ResbudDesignTokens.borderDark : ResbudDesignTokens.borderLight,
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Area
          InkWell(
            onTap: widget.isCollapsible ? _toggleExpanded : null,
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(ResbudDesignTokens.cardRadius),
              bottom: _expanded ? Radius.zero : const Radius.circular(ResbudDesignTokens.cardRadius),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (widget.sectionNumber != null) ...[
                        Container(
                          width: 20,
                          height: 20,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            widget.sectionNumber!,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ] else if (widget.icon != null) ...[
                        Icon(widget.icon, size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          widget.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            letterSpacing: -0.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.badge != null) ...[
                        const SizedBox(width: 6),
                        widget.badge!,
                      ],
                      if (widget.isCollapsible) ...[
                        const SizedBox(width: 4),
                        Icon(
                          _expanded ? Icons.expand_less : Icons.expand_more,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ],
                  ),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (widget.actions != null && widget.actions!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: widget.actions!,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(
              height: 1,
              thickness: 1,
              color: isDark ? ResbudDesignTokens.borderSubtleDark : ResbudDesignTokens.borderSubtleLight,
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: widget.children,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
