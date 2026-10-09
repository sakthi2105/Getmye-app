import 'package:flutter/material.dart';

class AdminColors {
  // Primary Green Palette
  static const Color primary = Color(0xFF10B981);       // Vibrant Emerald Green
  static const Color primaryDark = Color(0xFF047857);   // Deep Emerald
  static const Color primaryDeep = Color(0xFF064E3B);   // Dark Forest
  static const Color primaryLight = Color(0xFFECFDF5);  // Soft Mint Tint
  static const Color primarySubtle = Color(0xFFD1FAE5); // Mint Chip

  // Neutrals & Surfaces
  static const Color white = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF8FAFC);     // Clean Slate 50
  static const Color surface = Color(0xFFFFFFFF);
  static const Color cardBg = Color(0xFFFFFFFF);
  
  // Clean Typography
  static const Color textPrimary = Color(0xFF0F172A);   // Slate 900
  static const Color textSecondary = Color(0xFF475569); // Slate 600
  static const Color textMuted = Color(0xFF94A3B8);     // Slate 400

  // Borders & Lines
  static const Color border = Color(0xFFE2E8F0);        // Slate 200
  static const Color borderLight = Color(0xFFF1F5F9);   // Slate 100
  static const Color borderFocused = Color(0xFF10B981);

  // States
  static const Color success = Color(0xFF16A34A);
  static const Color danger = Color(0xFFEF4444);
  static const Color dangerLight = Color(0xFFFEE2E2);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningLight = Color(0xFFFEF3C7);
}

class AdminTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AdminColors.background,
      primaryColor: AdminColors.primary,
      colorScheme: const ColorScheme.light(
        primary: AdminColors.primary,
        onPrimary: Colors.white,
        secondary: AdminColors.primaryDark,
        surface: AdminColors.surface,
        onSurface: AdminColors.textPrimary,
        error: AdminColors.danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AdminColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AdminColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: AdminColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AdminColors.border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AdminColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AdminColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AdminColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AdminColors.primary, width: 2),
        ),
      ),
    );
  }
}
