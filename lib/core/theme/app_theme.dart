import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const background = Color.fromRGBO(13, 0, 0, 1);
  static const surface = Color(0xFF170505);
  static const surfaceHigh = Color(0xFF220909);
  static const card = Color(0xFF1B0808);
  static const red = Color(0xFFE12820);
  static const redBright = Color(0xFFFF473D);
  static const white = Color(0xFFF8F6F6);
  static const muted = Color(0xFFB9AAAA);
  static const hairline = Color(0x30FFFFFF);
  static const success = Color(0xFF5ED9A3);
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.red,
      brightness: Brightness.dark,
      surface: AppColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: scheme.copyWith(
        primary: AppColors.redBright,
        secondary: AppColors.red,
        surface: AppColors.surface,
      ),
      fontFamily: 'Monadi',
      fontFamilyFallback: const ['SF Arabic', 'Noto Sans Arabic', 'Arial'],
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.4),
        headlineMedium: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3),
        titleLarge: TextStyle(fontWeight: FontWeight.w800),
        titleMedium: TextStyle(fontWeight: FontWeight.w700),
        bodyLarge: TextStyle(height: 1.45),
        bodyMedium: TextStyle(height: 1.45),
      ).apply(bodyColor: AppColors.white, displayColor: AppColors.white),
      splashFactory: InkSparkle.splashFactory,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withOpacity(.055),
        hintStyle: TextStyle(color: Colors.white.withOpacity(.42)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: Colors.white.withOpacity(.06)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: AppColors.redBright.withOpacity(.65)),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: Colors.white.withOpacity(.08)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
        backgroundColor: Colors.white.withOpacity(.055),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      }),
    );
  }
}
