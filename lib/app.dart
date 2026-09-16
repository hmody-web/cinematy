import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/activation/activation_gate.dart';
import 'features/shell/cinematy_shell.dart';
import 'providers.dart';
import 'widgets/cinematy_backdrop.dart';
import 'widgets/glass_navigation_bar.dart';

final _cinematyNavigatorKey = GlobalKey<NavigatorState>();

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
      navigatorKey: _cinematyNavigatorKey,
      navigatorObservers: [nativeIosTabBarRouteObserver],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        Widget content = Directionality(
          textDirection: TextDirection.rtl,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const CinematyBackdrop(),
              child ?? const SizedBox.shrink(),
            ],
          ),
        );

        if (!kIsWeb) return content;

        // Chrome is our isolated TV preview. Give every screen larger TV
        // typography and one global remote handler. Native Android/iOS never
        // enter this branch, so their layout and input behaviour are untouched.
        final media = MediaQuery.of(context);
        content = MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(1.12),
          ),
          child: content,
        );

        return FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              final key = event.logicalKey;
              final primary = FocusManager.instance.primaryFocus;
              final primaryContext = primary?.context;
              final isEditing = primaryContext?.widget is EditableText;

              if (key == LogicalKeyboardKey.escape ||
                  key == LogicalKeyboardKey.backspace ||
                  (key == LogicalKeyboardKey.arrowLeft &&
                      HardwareKeyboard.instance.isAltPressed)) {
                _cinematyNavigatorKey.currentState?.maybePop();
                return KeyEventResult.handled;
              }

              if (!isEditing) {
                if (key == LogicalKeyboardKey.arrowLeft) {
                  primary?.focusInDirection(TraversalDirection.left);
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowRight) {
                  primary?.focusInDirection(TraversalDirection.right);
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowUp) {
                  primary?.focusInDirection(TraversalDirection.up);
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowDown) {
                  primary?.focusInDirection(TraversalDirection.down);
                  return KeyEventResult.handled;
                }
              }

              // Enter/Select/Space are handled by Flutter's ActivateIntent on
              // the focused InkWell/Button, matching a TV remote OK button.
              return KeyEventResult.ignored;
            },
            child: content,
          ),
        );
      },
      home: const CinematyActivationGate(
        child: CinematyShell(),
      ),
    );
  }
}
