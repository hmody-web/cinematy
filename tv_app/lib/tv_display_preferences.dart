import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tv_platform_ui.dart';
import 'tv_window_controller.dart';

class TvDisplayPreferences extends ChangeNotifier {
  static const _hideScoreboardKey = 'tv_hide_scoreboard';
  static const _startInLiveTvKey = 'tv_start_in_live_tv';
  static const _windowsFullscreenKey = 'tv_windows_fullscreen';
  static const _lowEndLiveOptimizationKey = 'tv_low_end_live_optimization';

  bool _hideScoreboard = false;
  bool _startInLiveTv = false;
  bool _windowsFullscreen = true;
  bool _lowEndLiveOptimization = false;

  bool get hideScoreboard => _hideScoreboard;
  bool get startInLiveTv => _startInLiveTv;
  bool get windowsFullscreen => _windowsFullscreen;
  bool get lowEndLiveOptimization => _lowEndLiveOptimization;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _hideScoreboard = prefs.getBool(_hideScoreboardKey) ?? false;
    _startInLiveTv = prefs.getBool(_startInLiveTvKey) ?? false;
    _windowsFullscreen = prefs.getBool(_windowsFullscreenKey) ?? true;
    _lowEndLiveOptimization = prefs.getBool(_lowEndLiveOptimizationKey) ?? false;
  }

  Future<void> setHideScoreboard(bool value) async {
    if (_hideScoreboard == value) return;
    _hideScoreboard = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hideScoreboardKey, value);
  }

  Future<void> setStartInLiveTv(bool value) async {
    if (_startInLiveTv == value) return;
    _startInLiveTv = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_startInLiveTvKey, value);
  }


  Future<void> setLowEndLiveOptimization(bool value) async {
    if (_lowEndLiveOptimization == value) return;
    _lowEndLiveOptimization = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_lowEndLiveOptimizationKey, value);
  }

  Future<void> setWindowsFullscreen(bool value) async {
    if (_windowsFullscreen != value) {
      _windowsFullscreen = value;
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_windowsFullscreenKey, value);
    }
    await TvWindowController.setFullscreen(value);
  }

  Future<void> applyWindowMode() async {
    if (!tvIsWindowsDesktop) return;
    await TvWindowController.setFullscreen(_windowsFullscreen);
  }
}
