import 'package:flutter/material.dart';

class AppColors {
  // Required Color System
  static const Color primary = Color(0xFF142B4A);      // Primary Dark Navy Blue (#142B4A)
  static const Color primaryDark = Color(0xFF0C1B30);  // Deep Midnight Navy
  static const Color primaryLight = Color(0xFFE8F2FF); // Soft Light Ice Blue (#E8F2FF)
  static const Color background = Color(0xFFF5F8FD);   // Clean Background with cool blue tone
  static const Color white = Color(0xFFFFFFFF);        // White
  static const Color surface = Color(0xFFFFFFFF);      // Card Surface
  static const Color textPrimary = Color(0xFF0F1E33);  // Primary Navy Text
  static const Color textSecondary = Color(0xFF566981);// Secondary Slate Text
  static const Color border = Color(0xFFD6E4F5);       // Thin light ice blue border
  static const Color danger = Color(0xFFEF4444);       // Error Red
  static const Color warning = Color(0xFFF59E0B);      // Warning Amber
  static const Color primarySubtle = Color(0xFFF0F6FF); // Very subtle ice blue tint
  static const Color primaryDeep = Color(0xFF142B4A);   // Deep primary alias
  static const Color textMuted = Color(0xFF566981);     // Muted secondary text alias

  // Helpers
  static const Color vegGreen = Color(0xFF22C55E);     // Veg dietary badge
  static const Color nonVegRed = Color(0xFFEF4444);    // Non-veg dietary badge
  static const Color cardShadow = Color(0x0A142B4A);   // Subtle navy shadow

  static List<BoxShadow> get subtleShadow => [
        const BoxShadow(
          color: Color(0x0A142B4A),
          blurRadius: 16,
          offset: Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get floatingShadow => [
        const BoxShadow(
          color: Color(0x14142B4A),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ];
}

/// Standardized Android App Font Typography System
/// - Default font: Roboto (System default)
/// - App title / Toolbar: Roboto Medium 20sp
/// - Page heading: Roboto Medium 20–24sp
/// - Subheading: Roboto Medium 16–18sp
/// - Body / Paragraph: Roboto Regular 14–16sp
/// - Button text: Roboto Medium 14sp
/// - Caption / Helper text: Roboto Regular 12sp
/// - Bottom navigation label: Roboto Medium 12sp
class AppTypography {
  static const String fontFamily = 'Roboto';

  // 1. App title / Toolbar: Roboto Medium 20sp
  static const TextStyle toolbarTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w500, // Roboto Medium
    color: AppColors.textPrimary,
  );

  // 2. Page heading: Roboto Medium 20–24sp
  static const TextStyle pageHeading = TextStyle(
    fontFamily: fontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w500, // Roboto Medium
    color: AppColors.textPrimary,
    letterSpacing: -0.3,
  );

  static const TextStyle screenHeading = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w500, // Roboto Medium
    color: AppColors.textPrimary,
    letterSpacing: -0.4,
  );

  // 3. Subheading: Roboto Medium 16–18sp
  static const TextStyle subheading = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w500, // Roboto Medium
    color: AppColors.textPrimary,
    letterSpacing: -0.2,
  );

  static const TextStyle sectionHeading = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w500, // Roboto Medium
    color: AppColors.textPrimary,
    letterSpacing: -0.2,
  );

  static const TextStyle cardTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w500, // Roboto Medium
    color: AppColors.textPrimary,
  );

  // 4. Body / Paragraph: Roboto Regular 14–16sp
  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400, // Roboto Regular
    color: AppColors.textPrimary,
    height: 1.4,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400, // Roboto Regular
    color: AppColors.textPrimary,
    height: 1.4,
  );

  // 5. Button text: Roboto Medium 14sp
  static const TextStyle buttonText = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500, // Roboto Medium
    letterSpacing: 0.1,
  );

  // 6. Caption / Helper text: Roboto Regular 12sp
  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400, // Roboto Regular
    color: AppColors.textSecondary,
  );

  static const TextStyle secondary = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400, // Roboto Regular
    color: AppColors.textSecondary,
  );

  static const TextStyle helperText = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400, // Roboto Regular
    color: AppColors.textSecondary,
  );

  // 7. Bottom navigation label: Roboto Medium 12sp
  static const TextStyle bottomNavLabel = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500, // Roboto Medium
  );

  static const TextStyle price = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w500, // Roboto Medium
    color: AppColors.textPrimary,
    letterSpacing: -0.2,
  );
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.primary,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.primaryDark,
        onSecondary: Colors.white,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.danger,
        onError: Colors.white,
      ),
      textTheme: const TextTheme(
        // Page heading: Roboto Medium 20-24sp
        headlineMedium: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 24,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
          letterSpacing: -0.4,
        ),
        headlineSmall: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
          letterSpacing: -0.3,
        ),
        // App title / Toolbar: Roboto Medium 20sp
        titleLarge: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
        // Subheading: Roboto Medium 16-18sp
        titleMedium: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 18,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
          letterSpacing: -0.2,
        ),
        titleSmall: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
        // Body / Paragraph: Roboto Regular 14-16sp
        bodyLarge: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
          height: 1.4,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
          height: 1.4,
        ),
        // Caption / Helper text: Roboto Regular 12sp
        bodySmall: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondary,
        ),
        // Button text: Roboto Medium 14sp
        labelLarge: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
        ),
        // Bottom navigation label: Roboto Medium 12sp
        labelMedium: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        labelSmall: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondary,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 20,
          fontWeight: FontWeight.w500, // Roboto Medium 20sp
          color: AppColors.textPrimary,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 14,
            fontWeight: FontWeight.w500, // Roboto Medium 14sp
            letterSpacing: 0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          side: const BorderSide(color: AppColors.border, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 14,
            fontWeight: FontWeight.w500, // Roboto Medium 14sp
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        labelStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 12,
          fontWeight: FontWeight.w400, // Roboto Regular 12sp
          color: AppColors.textSecondary,
        ),
        helperStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 12,
          fontWeight: FontWeight.w400, // Roboto Regular 12sp
          color: AppColors.textSecondary,
        ),
        hintStyle: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 14,
          fontWeight: FontWeight.w400, // Roboto Regular 14sp
          color: AppColors.textSecondary.withValues(alpha: 0.8),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        elevation: 8,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 12,
          fontWeight: FontWeight.w500, // Roboto Medium 12sp
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 12,
          fontWeight: FontWeight.w500, // Roboto Medium 12sp
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
