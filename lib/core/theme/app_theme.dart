import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const background = Color.fromRGBO(7, 5, 5, 1);
  static const surface = Color(0xFF100D0D);
  static const surfaceHigh = Color(0xFF181313);
  static const card = Color(0xFF141010);
  static const red = Color(0xFFE12820);
  static const redBright = Color(0xFFFF473D);
  static const white = Color(0xFFF8F6F6);
  static const muted = Color(0xFFB9AAAA);
  static const hairline = Color(0x30FFFFFF);
  static const success = Color(0xFF5ED9A3);
}

class AppTheme {
  AppTheme._();

  static ThemeData dark([String fontFamily = 'Monadi']) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.red,
      brightness: Brightness.dark,
      surface: AppColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      colorScheme: scheme.copyWith(
        primary: AppColors.redBright,
        secondary: AppColors.red,
        surface: AppColors.surface,
      ),
      fontFamily: fontFamily,
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
        TargetPlatform.iOS: _CinematyOpaqueCupertinoTransitionsBuilder(),
        TargetPlatform.android: _CinematyOpaqueCupertinoTransitionsBuilder(),
      }),
    );
  }
}

/// Restores Cinematy's previous horizontal page motion while keeping every
/// frame of the incoming page completely opaque. There is deliberately no
/// FadeTransition here: opacity stays at 1.0 throughout push and pop.
class _CinematyOpaqueCupertinoTransitionsBuilder extends PageTransitionsBuilder {
  const _CinematyOpaqueCupertinoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final opaqueChild = Stack(
      fit: StackFit.expand,
      children: [
        const _RouteBackdrop(),
        child,
      ],
    );

    // Keep the same iOS-style horizontal slide on both platforms. This gives
    // the old enter/exit movement back without ever fading the page itself.
    return CupertinoPageTransition(
      primaryRouteAnimation: animation,
      secondaryRouteAnimation: secondaryAnimation,
      linearTransition: false,
      child: opaqueChild,
    );
  }
}

class _RouteBackdrop extends StatelessWidget {
  const _RouteBackdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B0808), AppColors.background],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -150,
            right: -130,
            child: _RouteGlow(size: 360, opacity: .035),
          ),
          Positioned(
            top: 330,
            left: -150,
            child: _RouteGlow(size: 320, opacity: .022),
          ),
        ],
      ),
    );
  }
}

class _RouteGlow extends StatelessWidget {
  const _RouteGlow({required this.size, required this.opacity});
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              AppColors.redBright.withOpacity(opacity),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}
