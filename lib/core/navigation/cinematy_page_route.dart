import 'package:flutter/cupertino.dart';

/// A single route style for Cinematy that keeps Flutter's native interactive
/// Cupertino back gesture available on both iOS and Android. Because Cinematy
/// runs RTL, the back gesture starts at the right edge and moves to the left.
class CinematyPageRoute<T> extends CupertinoPageRoute<T> {
  CinematyPageRoute({
    required super.builder,
    super.settings,
    super.maintainState = true,
    super.fullscreenDialog = false,
  });

  @override
  Duration get transitionDuration => const Duration(milliseconds: 320);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 280);
}
