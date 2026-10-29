import 'package:flutter/material.dart';

/// Centralized design tokens and editorial academic theme for Resbud.
///
/// Implements a refined, high-contrast, distraction-free visual language
/// tailored for serious academic manuscript preparation, reviewing, and editing.
abstract final class ResbudDesignTokens {
  // Core Brand & Palette
  static const seedColor = Color(0xFF244840); // Deep Academic Pine / Forest Slate
  static const primaryLight = Color(0xFF1E3A34);
  static const primaryDark = Color(0xFF68C4AF);

  // Backgrounds & Surfaces (Light)
  static const backgroundLight = Color(0xFFF9FAF9); // Clean editorial parchment
  static const surfaceLight = Colors.white;
  static const surfaceSubtleLight = Color(0xFFF1F4F2);
  static const borderLight = Color(0xFFE0E5E2);
  static const borderSubtleLight = Color(0xFFECEFE8);

  // Backgrounds & Surfaces (Dark)
  static const backgroundDark = Color(0xFF131716); // Deep slate dark
  static const surfaceDark = Color(0xFF1A211F);
  static const surfaceSubtleDark = Color(0xFF222B29);
  static const borderDark = Color(0xFF2E3B37);
  static const borderSubtleDark = Color(0xFF25302D);

  // Semantic Status Colors (Light)
  static const warningTextLight = Color(0xFF92400E);
  static const warningBgLight = Color(0xFFFEF3C7);
  static const warningBorderLight = Color(0xFFFDE68A);

  static const errorTextLight = Color(0xFF9F1239);
  static const errorBgLight = Color(0xFFFFE4E6);
  static const errorBorderLight = Color(0xFFFECDD3);

  static const successTextLight = Color(0xFF065F46);
  static const successBgLight = Color(0xFFD1FAE5);
  static const successBorderLight = Color(0xFFA7F3D0);

  static const infoTextLight = Color(0xFF1E40AF);
  static const infoBgLight = Color(0xFFDBEAFE);
  static const infoBorderLight = Color(0xFFBFDBFE);

  // Semantic Status Colors (Dark)
  static const warningTextDark = Color(0xFFFCD34D);
  static const warningBgDark = Color(0xFF452207);
  static const warningBorderDark = Color(0xFF78350F);

  static const errorTextDark = Color(0xFFFDA4AF);
  static const errorBgDark = Color(0xFF4C0519);
  static const errorBorderDark = Color(0xFF881337);

  static const successTextDark = Color(0xFF6EE7B7);
  static const successBgDark = Color(0xFF064E3B);
  static const successBorderDark = Color(0xFF047857);

  static const infoTextDark = Color(0xFF93C5FD);
  static const infoBgDark = Color(0xFF172554);
  static const infoBorderDark = Color(0xFF1E40AF);

  // Spacing Scale
  static const spacing2 = 2.0;
  static const spacing4 = 4.0;
  static const spacing6 = 6.0;
  static const spacing8 = 8.0;
  static const spacing12 = 12.0;
  static const spacing16 = 16.0;
  static const spacing20 = 20.0;
  static const spacing24 = 24.0;
  static const spacing32 = 32.0;
  static const spacing40 = 40.0;
  static const spacing48 = 48.0;

  // Backward-compatible spacing aliases
  static const pagePadding = 20.0;
  static const contentSpacing = 16.0;
  static const cardRadius = 12.0;

  // Radii Scale (Restrained, professional)
  static const radiusSmall = 6.0;
  static const radiusMedium = 10.0;
  static const radiusLarge = 14.0;
  static const radiusFull = 999.0;

  /// Build cohesive Light Theme
  static ThemeData lightTheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
      surface: surfaceLight,
      surfaceContainerLowest: backgroundLight,
      surfaceContainerLow: surfaceSubtleLight,
      outline: borderLight,
      outlineVariant: borderSubtleLight,
    );

    return _buildTheme(
      scheme: scheme,
      scaffoldBg: backgroundLight,
      cardColor: surfaceLight,
      borderColor: borderLight,
      isDark: false,
    );
  }

  /// Build cohesive Dark Theme
  static ThemeData darkTheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
      surface: surfaceDark,
      surfaceContainerLowest: backgroundDark,
      surfaceContainerLow: surfaceSubtleDark,
      outline: borderDark,
      outlineVariant: borderSubtleDark,
    );

    return _buildTheme(
      scheme: scheme,
      scaffoldBg: backgroundDark,
      cardColor: surfaceDark,
      borderColor: borderDark,
      isDark: true,
    );
  }

  static ThemeData _buildTheme({
    required ColorScheme scheme,
    required Color scaffoldBg,
    required Color cardColor,
    required Color borderColor,
    required bool isDark,
  }) {
    final textTheme = _buildTextTheme(isDark);

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBg,
      useMaterial3: true,
      typography: Typography.material2021(),
      textTheme: textTheme,

      // App Bar: Restrained, clean hairline divider
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface, size: 22),
      ),

      // Card: Clean 1px border, 0 elevation
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: borderColor, width: 1.0),
        ),
      ),

      // Text Fields: Refined academic inputs
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1E2624) : surfaceLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: BorderSide(color: borderColor, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: BorderSide(color: borderColor, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: BorderSide(color: scheme.error, width: 1.0),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        labelStyle: TextStyle(
          color: isDark ? const Color(0xFF9EABA5) : const Color(0xFF55635E),
          fontSize: 14,
        ),
        helperStyle: TextStyle(
          color: isDark ? const Color(0xFF82908B) : const Color(0xFF6B7A75),
          fontSize: 12,
        ),
        errorStyle: TextStyle(
          color: scheme.error,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),

      // Buttons
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMedium)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          side: BorderSide(color: borderColor, width: 1.0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMedium)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),

      // Segmented Button
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          side: WidgetStatePropertyAll(BorderSide(color: borderColor, width: 1.0)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMedium)),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ),

      // Dialogs
      dialogTheme: DialogThemeData(
        backgroundColor: cardColor,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          side: BorderSide(color: borderColor, width: 1.0),
        ),
        titleTextStyle: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          letterSpacing: -0.2,
        ),
      ),

      // Chips
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? surfaceSubtleDark : surfaceSubtleLight,
        side: BorderSide(color: borderColor, width: 0.8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: scheme.onSurface,
        ),
      ),

      // Dividers
      dividerTheme: DividerThemeData(
        color: borderColor,
        thickness: 1.0,
        space: 1.0,
      ),

      // Tooltip
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? Colors.white : const Color(0xFF1E2624),
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
        textStyle: TextStyle(
          color: isDark ? const Color(0xFF1E2624) : Colors.white,
          fontSize: 12,
        ),
      ),
    );
  }

  static TextTheme _buildTextTheme(bool isDark) {
    final baseColor = isDark ? const Color(0xFFECEFE8) : const Color(0xFF1C2220);
    final secondaryColor = isDark ? const Color(0xFF9EABA5) : const Color(0xFF55635E);

    return TextTheme(
      // Headline (Academic titles & primary headers)
      headlineLarge: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        color: baseColor,
        height: 1.25,
      ),
      headlineMedium: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: baseColor,
        height: 1.3,
      ),
      headlineSmall: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: baseColor,
        height: 1.35,
      ),

      // Titles (Section headings, modal headers)
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: baseColor,
        height: 1.3,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: baseColor,
        height: 1.35,
      ),
      titleSmall: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: secondaryColor,
        height: 1.4,
      ),

      // Body (Reading manuscript text & forms)
      bodyLarge: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: baseColor,
        height: 1.55,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: baseColor,
        height: 1.5,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: secondaryColor,
        height: 1.4,
      ),

      // Labels (Buttons, badges, tags)
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: baseColor,
        letterSpacing: 0.1,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: secondaryColor,
        letterSpacing: 0.2,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: secondaryColor,
        letterSpacing: 0.2,
      ),
    );
  }
}
