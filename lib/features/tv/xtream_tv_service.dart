import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'tv_models.dart';

class TvSourceConfig {
  const TvSourceConfig({
    required this.server,
    required this.username,
    required this.password,
  });

  final String server;
  final String username;
  final String password;

  bool get isConfigured =>
      server.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      password.trim().isNotEmpty;

  static TvSourceConfig active = TvSourceConfig.fromEnvironment();

  factory TvSourceConfig.fromEnvironment() => const TvSourceConfig(
        server: String.fromEnvironment(
          'CINEMATY_TV_SERVER',
          defaultValue: 'http://ultramax.online:2052',
        ),
        username: String.fromEnvironment(
          'CINEMATY_TV_USERNAME',
          defaultValue: '17860075088178',
        ),
        password: String.fromEnvironment(
          'CINEMATY_TV_PASSWORD',
          defaultValue: '96904663972136',
        ),
      );
}

class XtreamTvService {
  XtreamTvService({TvSourceConfig? config, Dio? dio})
      : config = config ?? TvSourceConfig.active,
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 20),
                sendTimeout: const Duration(seconds: 12),
                responseType: ResponseType.json,
                headers: const {
                  'Accept': 'application/json, text/plain, */*',
                  'User-Agent': 'Cinematy/1.0',
                },
              ),
            );

  TvSourceConfig config;
  static const _activeServerKey = 'cinematy_active_tv_server_config';

  static Future<void> restoreActiveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activeServerKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final map = Map<String, dynamic>.from(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
      TvSourceConfig.active = TvSourceConfig(
        server: map['server'] as String? ?? TvSourceConfig.fromEnvironment().server,
        username: map['username'] as String? ?? '',
        password: map['password'] as String? ?? '',
      );
    } catch (_) {}
  }

  static Future<void> setActiveConfig(TvSourceConfig value) async {
    TvSourceConfig.active = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeServerKey, jsonEncode({
      'server': value.server, 'username': value.username, 'password': value.password,
    }));
  }
  final Dio _dio;

  String get _endpoint => '${config.server.replaceAll(RegExp(r'/+$'), '')}/player_api.php';

  Map<String, dynamic> _query(String action, [Map<String, dynamic>? extra]) => {
        'username': config.username,
        'password': config.password,
        'action': action,
        ...?extra,
      };

  Future<List<TvCategory>> getCategories() async {
    await _syncConfig();
    _ensureConfigured();
    final response = await _dio.get<dynamic>(
      _endpoint,
      queryParameters: _query('get_live_categories'),
    );
    final list = _asList(response.data);
    return list
        .whereType<Map>()
        .map((e) => TvCategory.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<TvChannel>> getChannels({String? categoryId}) async {
    await _syncConfig();
    _ensureConfigured();
    final response = await _dio.get<dynamic>(
      _endpoint,
      queryParameters: _query(
        'get_live_streams',
        categoryId == null || categoryId.isEmpty
            ? null
            : {'category_id': categoryId},
      ),
    );
    final list = _asList(response.data);
    return list
        .whereType<Map>()
        .map((e) => TvChannel.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.id > 0 && e.name.isNotEmpty)
        .toList(growable: false);
  }

  /// مكتبة المسلسلات من نفس Xtream المصدر المستخدم لقنوات التلفاز.
  Future<List<Map<String, dynamic>>> getSeriesCatalog() async {
    await _syncConfig();
    _ensureConfigured();
    final response = await _dio.get<dynamic>(
      _endpoint,
      queryParameters: _query('get_series'),
    );
    return _asList(response.data)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  /// تفاصيل مسلسل Xtream، وتشمل عادةً info + seasons + episodes.
  Future<Map<String, dynamic>> getSeriesInfo(String seriesId) async {
    await _syncConfig();
    _ensureConfigured();
    final response = await _dio.get<dynamic>(
      _endpoint,
      queryParameters: _query('get_series_info', {'series_id': seriesId}),
    );
    final data = response.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const <String, dynamic>{};
  }

  /// يحول أي مسار ترجمة/وسائط يعيده Xtream إلى رابط كامل على نفس السيرفر.
  String absoluteMediaUrl(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final base = config.server.replaceAll(RegExp(r'/+$'), '');
    if (raw.startsWith('/')) return '$base$raw';
    return '$base/$raw';
  }

  /// رابط تشغيل حلقة مسلسل من نفس حساب Xtream.
  String seriesEpisodeUrl({required String episodeId, String extension = 'mp4'}) {
    final ext = extension.trim().isEmpty ? 'mp4' : extension.trim().replaceFirst(RegExp(r'^\.'), '');
    return '${config.server.replaceAll(RegExp(r'/+$'), '')}/series/${Uri.encodeComponent(config.username)}/${Uri.encodeComponent(config.password)}/${Uri.encodeComponent(episodeId)}.$ext';
  }

  String streamUrl(TvChannel channel) =>
      '${config.server.replaceAll(RegExp(r'/+$'), '')}/live/${Uri.encodeComponent(config.username)}/${Uri.encodeComponent(config.password)}/${channel.id}.ts';

  static List<dynamic> _asList(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['data'] is List) return data['data'] as List;
    return const [];
  }

  Future<void> _syncConfig() async {
    await restoreActiveConfig();
    config = TvSourceConfig.active;
  }

  void _ensureConfigured() {
    if (!config.isConfigured) {
      throw StateError('TV_SOURCE_NOT_CONFIGURED');
    }
  }
}
