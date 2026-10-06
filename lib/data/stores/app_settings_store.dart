import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
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
  static const _remoteSourcesCacheKey = 'cinematy_remote_content_sources_v1';
  static const _remoteSourcesUpdatedAtKey = 'cinematy_remote_content_sources_updated_at';

  /// الملف المركزي الذي تعدله لوحة التحكم.
  static const remoteSourcesUrl =
      'https://scrptaty.com/pannel/cinematy_data/sources.json';

  static const fonts = <AppFontOption>[
    AppFontOption('Monadi', 'Monadi'),
    AppFontOption('ArabicUI', 'Arabic UI'),
    AppFontOption('Tajawal', 'Tajawal'),
    AppFontOption('NizarCocon', 'Nizar Cocon'),
  ];

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 12),
      sendTimeout: const Duration(seconds: 10),
      responseType: ResponseType.json,
      validateStatus: (status) => status != null && status >= 200 && status < 300,
    ),
  );

  Timer? _remoteSourcesTimer;

  String fontFamily = 'Monadi';
  int preferredVideoQuality = 1080;
  bool hideTvScoreboard = false;
  bool openTvOnLaunch = false;
  bool lowEndLiveOptimization = false;
  bool loaded = false;
  bool refreshingRemoteSources = false;
  DateTime? remoteSourcesUpdatedAt;
  String activeContentSourceId = 'cinemana';
  List<ContentSourceDefinition> customContentSources = const [];
  List<ContentSourceDefinition> _remoteContentSources = const [];

  List<ContentSourceDefinition> get contentSources {
    if (_remoteContentSources.isNotEmpty) {
      return List<ContentSourceDefinition>.unmodifiable(_remoteContentSources);
    }
    return builtInContentSources;
  }

  ContentSourceDefinition get activeContentSource => contentSources.firstWhere(
        (e) => e.id == activeContentSourceId,
        orElse: () => contentSources.first,
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

    // المصدر اليدوي القديم يبقى محفوظ للتوافق، لكن القائمة الفعلية تأتي من السيرفر.
    final customRaw = prefs.getString(_customContentSourcesKey);
    customContentSources = customRaw == null
        ? const []
        : ContentSourceDefinition.decodeList(customRaw);

    final cached = prefs.getString(_remoteSourcesCacheKey);
    if (cached != null && cached.trim().isNotEmpty) {
      final parsed = ContentSourceDefinition.decodeList(cached);
      if (parsed.isNotEmpty) {
        _remoteContentSources = _normalizeRemoteSources(parsed);
      }
    }
    final updatedMillis = prefs.getInt(_remoteSourcesUpdatedAtKey);
    if (updatedMillis != null && updatedMillis > 0) {
      remoteSourcesUpdatedAt = DateTime.fromMillisecondsSinceEpoch(updatedMillis);
    }

    final sourceId = prefs.getString(_activeContentSourceKey) ?? 'cinemana';
    activeContentSourceId = contentSources.any((e) => e.id == sourceId)
        ? sourceId
        : 'cinemana';

    loaded = true;
    notifyListeners();

    // لا نؤخر فتح التطبيق بانتظار السيرفر؛ نعرض الكاش فوراً ثم نحدث بالخلفية.
    unawaited(refreshRemoteSources());
    _remoteSourcesTimer?.cancel();
    _remoteSourcesTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(refreshRemoteSources()),
    );
  }

  List<ContentSourceDefinition> _normalizeRemoteSources(
    List<ContentSourceDefinition> incoming,
  ) {
    final byId = <String, ContentSourceDefinition>{};

    for (final source in incoming) {
      if (source.id.trim().isEmpty || !source.enabled) continue;
      var normalized = source;

      // سينمانا مصدر أساسي محمي؛ إذا ترك الرابط فارغاً في اللوحة نستخدم الرابط المدمج.
      if (source.id == 'cinemana') {
        final builtIn = builtInContentSources.first;
        normalized = source.copyWith(
          baseUrl: source.baseUrl.trim().isEmpty ? builtIn.baseUrl : source.baseUrl,
          kind: ContentSourceKind.cinemana,
          builtIn: true,
          description: source.description.isEmpty
              ? builtIn.description
              : source.description,
        );
      }

      // أكوام يبقى على الـparser الخاص به حتى لو عدلت دومينه من اللوحة.
      if (source.id == 'akwam') {
        final builtIn = builtInContentSources[1];
        normalized = normalized.copyWith(
          baseUrl: normalized.baseUrl.trim().isEmpty
              ? builtIn.baseUrl
              : normalized.baseUrl,
          kind: ContentSourceKind.website,
          builtIn: true,
          description: normalized.description.isEmpty
              ? builtIn.description
              : normalized.description,
        );
      }

      byId[normalized.id] = normalized;
    }

    // حتى لو انحذف سينمانا بالغلط من JSON، لا نخلي التطبيق بدون مصدر رئيسي.
    byId.putIfAbsent('cinemana', () => builtInContentSources.first);

    final result = byId.values.toList()
      ..sort((a, b) {
        final order = a.sortOrder.compareTo(b.sortOrder);
        if (order != 0) return order;
        return a.name.compareTo(b.name);
      });
    return result;
  }

  Future<void> refreshRemoteSources() async {
    if (refreshingRemoteSources) return;
    refreshingRemoteSources = true;
    try {
      final response = await _dio.get<dynamic>(
        remoteSourcesUrl,
        options: Options(
          headers: const {
            'Accept': 'application/json',
            'Cache-Control': 'no-cache',
          },
          extra: const {'withCredentials': false},
        ),
        queryParameters: <String, dynamic>{
          // يمنع CDN/browser من إبقاء نسخة قديمة وقت التعديل من اللوحة.
          '_': DateTime.now().millisecondsSinceEpoch,
        },
      );

      dynamic data = response.data;
      if (data is String) data = jsonDecode(data);
      final list = data is Map ? data['sources'] : data;
      if (list is! List) throw const FormatException('sources list missing');

      final parsed = list
          .whereType<Map>()
          .map((e) => ContentSourceDefinition.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.id.isNotEmpty)
          .toList();

      final normalized = _normalizeRemoteSources(parsed);
      if (normalized.isEmpty) return;

      _remoteContentSources = normalized;
      remoteSourcesUpdatedAt = DateTime.now();

      if (!contentSources.any((e) => e.id == activeContentSourceId)) {
        activeContentSourceId = 'cinemana';
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _remoteSourcesCacheKey,
        ContentSourceDefinition.encodeList(_remoteContentSources),
      );
      await prefs.setInt(
        _remoteSourcesUpdatedAtKey,
        remoteSourcesUpdatedAt!.millisecondsSinceEpoch,
      );
      await prefs.setString(_activeContentSourceKey, activeContentSourceId);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SOURCES] remote refresh failed: $e');
      }
      // نحتفظ بالكاش السابق أو المصادر المدمجة بدون تعطيل التطبيق.
    } finally {
      refreshingRemoteSources = false;
    }
  }

  Future<void> setActiveContentSource(String id) async {
    if (!contentSources.any((e) => e.id == id) || activeContentSourceId == id) {
      return;
    }
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
    await prefs.setString(
      _customContentSourcesKey,
      ContentSourceDefinition.encodeList(customContentSources),
    );
  }

  Future<void> removeCustomContentSource(String id) async {
    customContentSources = customContentSources.where((e) => e.id != id).toList();
    if (activeContentSourceId == id) activeContentSourceId = 'cinemana';
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _customContentSourcesKey,
      ContentSourceDefinition.encodeList(customContentSources),
    );
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

  @override
  void dispose() {
    _remoteSourcesTimer?.cancel();
    _dio.close(force: true);
    super.dispose();
  }
}
