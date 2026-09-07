import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/shell/cinematy_shell.dart';
import 'providers.dart';
import 'widgets/glass_navigation_bar.dart';

class CinematyApp extends ConsumerWidget {
  const CinematyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'سينماتي',
      theme: AppTheme.dark(settings.fontFamily),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      navigatorObservers: [nativeIosTabBarRouteObserver],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const CinematyShell(),
    );
  }
}
