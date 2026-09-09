import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class TvSystemPip {
  TvSystemPip._();

  static const MethodChannel _channel = MethodChannel('cinematy/system_pip');
  static final StreamController<bool> _state = StreamController<bool>.broadcast();
  static bool _installed = false;

  static Stream<bool> get state {
    _install();
    return _state.stream;
  }

  static void _install() {
    if (_installed || !Platform.isAndroid) return;
    _installed = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged') {
        _state.add(call.arguments == true);
      }
    });
  }

  static Future<void> setActive(bool active) async {
    if (!Platform.isAndroid) return;
    _install();
    try {
      await _channel.invokeMethod<void>('setActive', active);
    } catch (_) {}
  }

  static Future<void> enter() async {
    if (!Platform.isAndroid) return;
    _install();
    try {
      await _channel.invokeMethod<void>('enter');
    } catch (_) {}
  }
}
