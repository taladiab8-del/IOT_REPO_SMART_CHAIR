import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData mixedTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF0D47A1), // elegant deep blue
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: const Color(0xFFF2F5FA), // soft light gray
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF0D47A1), // dark header
      foregroundColor: Colors.white,
      centerTitle: true,
      elevation: 4,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    ),
  );
}
