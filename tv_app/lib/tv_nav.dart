import 'package:flutter/material.dart';

import 'tv_ui_frame.dart';

Route<T> tvRoute<T>(Widget child) => PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => TvUiFrame(child: child),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );

/// Full-screen playback route. No virtual-resolution scaling is applied.
Route<T> tvVideoRoute<T>(Widget child) => PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => child,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
