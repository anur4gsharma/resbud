import 'package:flutter/material.dart';

abstract final class ResbudDesignTokens {
  static const seedColor = Color(0xFF315B57);
  static const pagePadding = 20.0;
  static const contentSpacing = 16.0;
  static const cardRadius = 16.0;

  static ThemeData lightTheme() {
    final scheme = ColorScheme.fromSeed(seedColor: seedColor);
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF7F8F6),
      useMaterial3: true,
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
