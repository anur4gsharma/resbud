import 'package:flutter/material.dart';
import '../design_tokens.dart';

enum ResbudStatusType { saved, unsaved, saving, active, warning, neutral, info }

/// Reusable status chip/badge for displaying save states, draft status, and system phases.
class ResbudStatusBadge extends StatelessWidget {
  const ResbudStatusBadge({
    super.key,
    required this.label,
    this.type = ResbudStatusType.neutral,
    this.icon,
    this.keyName,
  });

  final String label;
  final ResbudStatusType type;
  final IconData? icon;
  final String? keyName;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final (bg, border, fg) = switch (type) {
      ResbudStatusType.saved => isDark
          ? (ResbudDesignTokens.successBgDark, ResbudDesignTokens.successBorderDark, ResbudDesignTokens.successTextDark)
          : (ResbudDesignTokens.successBgLight, ResbudDesignTokens.successBorderLight, ResbudDesignTokens.successTextLight),
      ResbudStatusType.unsaved => isDark
          ? (ResbudDesignTokens.warningBgDark, ResbudDesignTokens.warningBorderDark, ResbudDesignTokens.warningTextDark)
          : (ResbudDesignTokens.warningBgLight, ResbudDesignTokens.warningBorderLight, ResbudDesignTokens.warningTextLight),
      ResbudStatusType.saving => isDark
          ? (ResbudDesignTokens.infoBgDark, ResbudDesignTokens.infoBorderDark, ResbudDesignTokens.infoTextDark)
          : (ResbudDesignTokens.infoBgLight, ResbudDesignTokens.infoBorderLight, ResbudDesignTokens.infoTextLight),
      ResbudStatusType.active => isDark
          ? (ResbudDesignTokens.successBgDark, ResbudDesignTokens.successBorderDark, ResbudDesignTokens.successTextDark)
          : (ResbudDesignTokens.successBgLight, ResbudDesignTokens.successBorderLight, ResbudDesignTokens.successTextLight),
      ResbudStatusType.warning => isDark
          ? (ResbudDesignTokens.warningBgDark, ResbudDesignTokens.warningBorderDark, ResbudDesignTokens.warningTextDark)
          : (ResbudDesignTokens.warningBgLight, ResbudDesignTokens.warningBorderLight, ResbudDesignTokens.warningTextLight),
      ResbudStatusType.neutral => isDark
          ? (ResbudDesignTokens.surfaceSubtleDark, ResbudDesignTokens.borderDark, const Color(0xFFC4D0CC))
          : (ResbudDesignTokens.surfaceSubtleLight, ResbudDesignTokens.borderLight, const Color(0xFF4A5551)),
      ResbudStatusType.info => isDark
          ? (ResbudDesignTokens.infoBgDark, ResbudDesignTokens.infoBorderDark, ResbudDesignTokens.infoTextDark)
          : (ResbudDesignTokens.infoBgLight, ResbudDesignTokens.infoBorderLight, ResbudDesignTokens.infoTextLight),
    };

    return Container(
      key: keyName != null ? ValueKey(keyName!) : null,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(ResbudDesignTokens.radiusSmall),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: fg,
                letterSpacing: 0.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
