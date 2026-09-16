import 'package:dio/dio.dart';

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

  factory TvSourceConfig.fromEnvironment() => const TvSourceConfig(
        server: String.fromEnvironment(
          'CINEMATY_TV_SERVER',
          defaultValue: 'http://ultramax.online:2052',
        ),
        username: String.fromEnvironment(
          'CINEMATY_TV_USERNAME',
          defaultValue: '66336441047385',
        ),
        password: String.fromEnvironment(
          'CINEMATY_TV_PASSWORD',
          defaultValue: '10832140210652',
        ),
      );
}

class XtreamTvService {
  XtreamTvService({TvSourceConfig? config, Dio? dio})
      : config = config ?? TvSourceConfig.fromEnvironment(),
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

  final TvSourceConfig config;
  final Dio _dio;

  String get _endpoint => '${config.server.replaceAll(RegExp(r'/+$'), '')}/player_api.php';

  Map<String, dynamic> _query(String action, [Map<String, dynamic>? extra]) => {
        'username': config.username,
        'password': config.password,
        'action': action,
        ...?extra,
      };

  Future<List<TvCategory>> getCategories() async {
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

  String streamUrl(TvChannel channel) =>
      '${config.server.replaceAll(RegExp(r'/+$'), '')}/live/${Uri.encodeComponent(config.username)}/${Uri.encodeComponent(config.password)}/${channel.id}.ts';

  static List<dynamic> _asList(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['data'] is List) return data['data'] as List;
    return const [];
  }

  void _ensureConfigured() {
    if (!config.isConfigured) {
      throw StateError('TV_SOURCE_NOT_CONFIGURED');
    }
  }
}
