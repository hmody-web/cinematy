import 'package:flutter/services.dart';

import 'tv_platform_ui.dart';

class TvWindowController {
  TvWindowController._();

  static const MethodChannel _channel = MethodChannel('cinematy/window');

  static Future<void> setFullscreen(bool fullscreen) async {
    if (!tvIsWindowsDesktop) return;
    try {
      await _channel.invokeMethod<void>(
        fullscreen ? 'setFullscreen' : 'setWindowedBorderless',
      );
    } on PlatformException {
      // Keep the preference saved even if Windows rejects a transient resize.
    } on MissingPluginException {
      // Older builds can still open; the next Windows build will apply it.
    }
  }
}
