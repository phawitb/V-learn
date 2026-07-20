import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Brand palette lifted from the Learn Anywhere – eggspace teardown:
/// blue gradient chrome, warm paper background, gold egg currency.
class AppColors {
  AppColors._();

  static const Color blueDark = Color(0xFF3F6BEA);
  static const Color blueMid = Color(0xFF4F8FF0);
  static const Color blueLight = Color(0xFF7FD0EE);

  static const Color background = Color(0xFFF6F3EC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSoft = Color(0xFFEFEADF);
  static const Color border = Color(0xFFE2DDD0);

  static const Color ink = Color(0xFF1C2333);
  static const Color inkSoft = Color(0xFF5B6172);
  static const Color inkFaint = Color(0xFF8B8F9C);

  static const Color gold = Color(0xFFDD9A13);
  static const Color goldSoft = Color(0xFFFBEECB);
  static const Color goldInk = Color(0xFF7A5300);

  static const Color red = Color(0xFFD64545);
  static const Color green = Color(0xFF3FA34D);

  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [blueDark, blueMid, blueLight],
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.blueDark,
        brightness: Brightness.light,
        primary: AppColors.blueDark,
        surface: AppColors.surface,
      ),
    );

    final textTheme = GoogleFonts.kanitTextTheme(base.textTheme).copyWith(
      titleLarge: GoogleFonts.kanit(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
        letterSpacing: -0.2,
      ),
      titleMedium: GoogleFonts.kanit(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      bodyLarge: GoogleFonts.sarabun(fontSize: 15, color: AppColors.ink),
      bodyMedium: GoogleFonts.sarabun(fontSize: 13.5, color: AppColors.inkSoft),
      bodySmall: GoogleFonts.sarabun(fontSize: 12, color: AppColors.inkFaint),
      labelLarge: GoogleFonts.kanit(fontWeight: FontWeight.w700),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleMedium,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.blueDark,
          foregroundColor: Colors.white,
          textStyle: GoogleFonts.kanit(fontWeight: FontWeight.w700, fontSize: 15),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.border),
          textStyle: GoogleFonts.kanit(fontWeight: FontWeight.w600, fontSize: 14),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.blueDark,
        linearTrackColor: AppColors.surfaceSoft,
      ),
    );
  }
}
