import 'package:flutter/cupertino.dart';

import '../theme/app_theme.dart';

/// The shared page route used across Cinematy.
///
/// It keeps Flutter's native interactive Cupertino back gesture on iOS and
/// Android, while giving every pushed route its own fully opaque background.
/// This is important because most Cinematy screens intentionally use a
/// transparent [Scaffold] so the app backdrop can be seen. Without an opaque
/// route layer, the previous page becomes visible through the current page
/// while pushing or interactively swiping back.
class CinematyPageRoute<T> extends CupertinoPageRoute<T> {
  CinematyPageRoute({
    required WidgetBuilder builder,
    super.settings,
    super.maintainState = true,
    super.fullscreenDialog = false,
  }) : super(
          builder: (context) => ColoredBox(
            color: AppColors.background,
            child: builder(context),
          ),
        );

  @override
  Duration get transitionDuration => const Duration(milliseconds: 320);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 280);
}
