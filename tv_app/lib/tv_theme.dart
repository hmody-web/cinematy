import 'package:flutter/material.dart';

class TvColors {
  static const background = Color(0xFF070505);
  static const surface = Color(0xFF121010);
  static const surface2 = Color(0xFF1A1616);
  static const red = Color(0xFFFF3B30);
  static const textMuted = Color(0xFFAAA2A2);
}

ThemeData buildTvTheme() => ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: TvColors.background,
      fontFamily: 'Monadi',
      colorScheme: const ColorScheme.dark(
        primary: TvColors.red,
        surface: TvColors.surface,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _NoTransitionsBuilder(),
        },
      ),
    );

class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
