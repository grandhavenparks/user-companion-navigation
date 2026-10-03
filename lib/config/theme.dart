import 'package:flutter/material.dart';

/// Application theme - forest/field oriented colours.
class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2E7D32),
        brightness: Brightness.light,
        primary: const Color(0xFF2E7D32),
        secondary: const Color(0xFF558B2F),
      ),
      appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFF2E7D32),
        foregroundColor: Colors.white,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF66BB6A),
        brightness: Brightness.dark,
        primary: const Color(0xFF66BB6A),
        secondary: const Color(0xFF81C784),
      ),
      appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFF388E3C),
        foregroundColor: Colors.white,
      ),
    );
  }

  // Map colours. Points are not coloured by health classification.

  /// Unvisited point inside the selected park.
  static const Color pointColor = Color(0xFFEF6C00);

  /// The point you are being navigated to.
  static const Color targetColor = Color(0xFFC2185B);

  /// Point already marked visited.
  static const Color visitedColor = Color(0xFF2E7D32);

  /// Point outside the selected park (shown, never navigated).
  static const Color outsideColor = Color(0xFF9E9E9E);

  /// Unvisited cluster inside the selected park (same indigo as the old app).
  static const Color clusterColor = Color(0xFF3949AB);

  static const Color routeColor = Color(0xFF6A1B9A);
  static const Color userColor = Color(0xFF1E88E5);
  static const Color parkBorderColor = Color(0xFF2E7D32);
}
