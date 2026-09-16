import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'features/activation/tv_activation_gate.dart';
import 'tv_theme.dart';
import 'tv_ui_frame.dart';

final GlobalKey<NavigatorState> tvNavigatorKey = GlobalKey<NavigatorState>();

class CinematyTvApp extends StatelessWidget {
  const CinematyTvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: tvNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'سينماتي TV',
      theme: buildTvTheme(),
      locale: const Locale('ar'),
      builder: (context, child) {
        return ColoredBox(
          color: Colors.black,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(),
              child: Focus(
                autofocus: true,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;
                  final primary = FocusManager.instance.primaryFocus;
                  final editable = primary?.context?.widget is EditableText;

                  if (key == LogicalKeyboardKey.escape ||
                      key == LogicalKeyboardKey.backspace ||
                      key == LogicalKeyboardKey.browserBack) {
                    final nav = tvNavigatorKey.currentState;
                    if (nav != null && nav.canPop()) {
                      nav.maybePop();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  }

                  if (!editable) {
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
                    if (key == LogicalKeyboardKey.enter ||
                        key == LogicalKeyboardKey.numpadEnter ||
                        key == LogicalKeyboardKey.select ||
                        key == LogicalKeyboardKey.space) {
                      final focusContext = primary?.context;
                      if (focusContext != null) {
                        Actions.invoke(focusContext, const ActivateIntent());
                        return KeyEventResult.handled;
                      }
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        );
      },
      home: const TvActivationGate(),
    );
  }
}
