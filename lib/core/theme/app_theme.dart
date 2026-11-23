import 'package:flutter/material.dart';

/// Basic Material 3 look, built from the same navy as the login screens.
class AppTheme {
  AppTheme._();

  static const navy = Color(0xFF14213D);

  static ThemeData build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: navy, brightness: brightness);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      appBarTheme: const AppBarTheme(centerTitle: false),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
