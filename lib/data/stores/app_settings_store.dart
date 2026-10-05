import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/content_source.dart';

class AppFontOption {
  const AppFontOption(this.family, this.label);
  final String family;
  final String label;
}

class AppSettingsStore extends ChangeNotifier {
  static const _fontKey = 'cinematy_app_font';
  static const _videoQualityKey = 'cinematy_default_video_quality';
  static const _hideTvScoreboardKey = 'cinematy_hide_tv_scoreboard';
  static const _openTvOnLaunchKey = 'cinematy_open_tv_on_launch';
  static const _lowEndLiveOptimizationKey = 'cinematy_low_end_live_optimization';
  static const _activeContentSourceKey = 'cinematy_active_content_source';
  static const _customContentSourcesKey = 'cinematy_custom_content_sources';

  static const fonts = <AppFontOption>[
    AppFontOption('Monadi', 'Monadi'),
    AppFontOption('ArabicUI', 'Arabic UI'),
    AppFontOption('Tajawal', 'Tajawal'),
    AppFontOption('NizarCocon', 'Nizar Cocon'),
  ];

  String fontFamily = 'Monadi';
  int preferredVideoQuality = 1080;
  bool hideTvScoreboard = false;
  bool openTvOnLaunch = false;
  bool lowEndLiveOptimization = false;
  bool loaded = false;
  String activeContentSourceId = 'cinemana';
  List<ContentSourceDefinition> customContentSources = const [];

  List<ContentSourceDefinition> get contentSources => builtInContentSources;

  ContentSourceDefinition get activeContentSource => contentSources.firstWhere(
        (e) => e.id == activeContentSourceId,
        orElse: () => builtInContentSources.first,
      );

  Future<void> load() async {
    if (loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_fontKey);
    if (saved != null && fonts.any((e) => e.family == saved)) {
      fontFamily = saved;
    }
    preferredVideoQuality = prefs.getInt(_videoQualityKey) ?? 1080;
    hideTvScoreboard = prefs.getBool(_hideTvScoreboardKey) ?? false;
    openTvOnLaunch = prefs.getBool(_openTvOnLaunchKey) ?? false;
    lowEndLiveOptimization = prefs.getBool(_lowEndLiveOptimizationKey) ?? false;
    // Custom sources are intentionally disabled for now; only Cinemana and Akwam are exposed.
    customContentSources = const [];
    final sourceId = prefs.getString(_activeContentSourceKey) ?? 'cinemana';
    activeContentSourceId = contentSources.any((e) => e.id == sourceId) ? sourceId : 'cinemana';
    loaded = true;
    notifyListeners();
  }


  Future<void> setActiveContentSource(String id) async {
    if (!contentSources.any((e) => e.id == id) || activeContentSourceId == id) return;
    activeContentSourceId = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeContentSourceKey, id);
  }

  Future<void> addCustomContentSource(ContentSourceDefinition source) async {
    customContentSources = <ContentSourceDefinition>[
      ...customContentSources.where((e) => e.id != source.id),
      source,
    ];
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customContentSourcesKey, ContentSourceDefinition.encodeList(customContentSources));
  }

  Future<void> removeCustomContentSource(String id) async {
    customContentSources = customContentSources.where((e) => e.id != id).toList();
    if (activeContentSourceId == id) activeContentSourceId = 'cinemana';
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customContentSourcesKey, ContentSourceDefinition.encodeList(customContentSources));
    await prefs.setString(_activeContentSourceKey, activeContentSourceId);
  }

  Future<void> setPreferredVideoQuality(int value) async {
    if (![2160, 1440, 1080, 720, 480, 360].contains(value) ||
        preferredVideoQuality == value) {
      return;
    }
    preferredVideoQuality = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_videoQualityKey, value);
  }

  Future<void> setFontFamily(String value) async {
    if (!fonts.any((e) => e.family == value) || fontFamily == value) return;
    fontFamily = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fontKey, value);
  }

  Future<void> setHideTvScoreboard(bool value) async {
    if (hideTvScoreboard == value) return;
    hideTvScoreboard = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hideTvScoreboardKey, value);
  }

  Future<void> setOpenTvOnLaunch(bool value) async {
    if (openTvOnLaunch == value) return;
    openTvOnLaunch = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_openTvOnLaunchKey, value);
  }

  Future<void> setLowEndLiveOptimization(bool value) async {
    if (lowEndLiveOptimization == value) return;
    lowEndLiveOptimization = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_lowEndLiveOptimizationKey, value);
  }
}
