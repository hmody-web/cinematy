import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Desktop-only presentation helpers.
/// Android TV and Web keep their existing layout and behavior.
bool get tvIsWindowsDesktop =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

double tvWindowsScale(BuildContext context) {
  if (!tvIsWindowsDesktop) return 1.0;
  final size = MediaQuery.sizeOf(context);
  final widthScale = size.width / 1920.0;
  final heightScale = size.height / 1080.0;
  return ((widthScale + heightScale) / 2).clamp(.86, 1.18);
}

double tvDesktopValue(
  BuildContext context, {
  required double tv,
  required double windows,
}) {
  if (!tvIsWindowsDesktop) return tv;
  return windows * tvWindowsScale(context);
}
