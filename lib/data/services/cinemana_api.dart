import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_cache.dart';
import '../../core/utils/json_utils.dart';
import '../models/category.dart';
import '../models/content_details.dart';
import '../models/episode.dart';
import '../models/media_item.dart';
import '../models/video_source.dart';

class CinemanaApi {
  CinemanaApi();

  // نجرب .cc أولاً، وإذا فشل الطلب نجرب .com تلقائياً.
  static const List<String> _contentBases = <String>[
    'https://cinemana.shabakaty.cc',
    'https://cinemana.shabakaty.com',
  ];

  static const List<String> _recommendationBases = <String>[
    'https://recommend.shabakaty.cc',
    'https://recommend.shabakaty.com',
  ];

  final ApiDiskCache _cache = ApiDiskCache();

  Dio _dioFor(String baseUrl) => Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: AppConfig.requestTimeout,
          receiveTimeout: AppConfig.requestTimeout,
          sendTimeout: AppConfig.requestTimeout,
          headers: const {
            'Accept': 'application/json, text/plain, */*',
            'Accept-Language': 'ar-IQ,ar;q=0.9,en;q=0.4',
            'User-Agent': 'Cinematy/1.0 (Flutter; Android/iOS)',
            'Cache-Control': 'no-cache',
          },
          // بعض نسخ المصدر ترجع JSON مع Content-Type غير صحيح.
          responseType: ResponseType.plain,
        ),
      );

  Future<dynamic> _get(
    String path, {
    Map<String, dynamic>? query,
    Duration ttl = AppConfig.apiCacheTtl,
    bool refresh = false,
    bool requireNonEmpty = false,
  }) async {
    // v3 يمنع استعمال أي Cache قديم فارغ تم حفظه من النسخة السابقة.
    final key = 'cinemana-v3|$path?${jsonEncode(query ?? const {})}';

    if (!refresh) {
      final cached = await _cache.get(key, ttl);
      if (cached != null && (!requireNonEmpty || _hasUsefulData(cached))) {
        _debug('CACHE', path, 200, cached);
        return cached;
      }
    }

    Object? lastError;

    for (final base in _contentBases) {
      try {
        final response = await _dioFor(base).get<dynamic>(
          path,
          queryParameters: query,
        );
        final data = _decodeResponse(response.data);
        _debug('GET', '$base$path', response.statusCode ?? 0, data);

        if (requireNonEmpty && !_hasUsefulData(data)) {
          lastError = StateError('المصدر أعاد استجابة فارغة من $base$path');
          continue;
        }

        await _cache.put(key, data);
        return data;
      } on DioException catch (error) {
        lastError = error;
        _debugError('GET', '$base$path', error);
      } catch (error) {
        lastError = error;
        if (kDebugMode) {
          debugPrint('[Cinematy API] GET $base$path -> $error');
        }
      }
    }

    throw StateError(
      'فشل الاتصال بمصدر سينمانا عبر .cc و .com. آخر خطأ: ${_shortError(lastError)}',
    );
  }

  Future<dynamic> _post(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    Object? lastError;
    for (final base in _contentBases) {
      try {
        final response = await _dioFor(base).post<dynamic>(path, data: data);
        final decoded = _decodeResponse(response.data);
        _debug('POST', '$base$path', response.statusCode ?? 0, decoded);
        return decoded;
      } on DioException catch (error) {
        lastError = error;
        _debugError('POST', '$base$path', error);
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError('فشل POST على مصدر سينمانا: ${_shortError(lastError)}');
  }

  Future<List<MediaItem>> homeHighlights({bool refresh = false}) async {
    final candidates = <MediaItem>[];
    final errors = <Object>[];

    for (final request in <Future<dynamic> Function()>[
      () => _get(CinemanaRoutes.banner(0), refresh: refresh, requireNonEmpty: true),
      () => _get(CinemanaRoutes.newlyVideos(0), refresh: refresh, requireNonEmpty: false),
    ]) {
      try {
        final raw = await request();
        candidates.addAll(_mediaList(raw));
        if (candidates.length >= 5) break;
      } catch (error) {
        errors.add(error);
        if (kDebugMode) debugPrint('[Cinematy API] homeHighlights: $error');
      }
    }

    if (candidates.isEmpty && errors.length == 2) {
      throw StateError('تعذر تحميل واجهة سينمانا: ${_shortError(errors.last)}');
    }

    return _unique(candidates).take(8).toList();
  }

  Future<List<MediaItem>> newlyAdded({bool refresh = false}) async {
    final raw = await _get(
      CinemanaRoutes.newlyVideos(0),
      refresh: refresh,
      // هذا المسار يرجع [] حالياً من سينمانا رغم أن الاتصال ناجح.
      // لذلك لا نعتبر القائمة الفارغة خطأ شبكة.
      requireNonEmpty: false,
    );
    final items = _mediaList(raw);
    if (items.isNotEmpty) return items;

    // fallback عملي: اجلب أحدث/مختارات الصفحة من videoGroups إذا newlyVideos فارغ.
    final sections = await homeSections(refresh: refresh);
    return _unique(sections.expand((e) => e.items).toList()).take(30).toList();
  }

  Future<List<MediaSection>> homeSections({bool refresh = false}) async {
    final raw = await _get(
      CinemanaRoutes.videoGroups(AppConfig.language),
      refresh: refresh,
      requireNonEmpty: true,
    );

    final top = JsonUtils.list(raw, candidateKeys: const ['groups', 'videoGroups']);
    final sections = <MediaSection>[];

    for (final item in top) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final nested = JsonUtils.list(
        map,
        candidateKeys: const ['content', 'videos', 'items', 'videoList'],
      );
      final media = nested
          .whereType<Map>()
          .map((e) => MediaItem.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.id.isNotEmpty)
          .toList();
      if (media.isEmpty) continue;

      sections.add(
        MediaSection(
          id: JsonUtils.string(
            map,
            ['id', 'groupID', 'groupId', 'catNb'],
            fallback: '${sections.length}',
          ),
          title: JsonUtils.string(
            map,
            ['lang_ar_title', 'ar_title', 'title', 'name'],
            fallback: 'مختارات',
          ),
          items: _unique(media),
        ),
      );
    }

    if (sections.isEmpty) {
      final flat = _mediaList(raw);
      if (flat.isNotEmpty) {
        sections.add(MediaSection(id: 'all', title: 'مختارات', items: flat));
      }
    }

    return sections;
  }

  Future<List<MediaItem>> videoGroups({bool refresh = false}) async {
    final sections = await homeSections(refresh: refresh);
    return _unique(sections.expand((e) => e.items).toList());
  }

  Future<List<MediaCategory>> categories({bool refresh = false}) async {
    dynamic raw;
    try {
      raw = await _get(
        CinemanaRoutes.categories,
        refresh: refresh,
        ttl: const Duration(hours: 2),
        requireNonEmpty: true,
      );
    } catch (_) {
      raw = await _get(
        CinemanaRoutes.category,
        refresh: refresh,
        ttl: const Duration(hours: 2),
        requireNonEmpty: true,
      );
    }

    return JsonUtils.list(raw, candidateKeys: const ['categories'])
        .whereType<Map>()
        .map((e) => MediaCategory.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.id.isNotEmpty || e.title.isNotEmpty)
        .toList();
  }

  Future<List<MediaItem>> groupVideos(
    String groupId, {
    int page = 1,
    String query = '',
  }) async {
    final raw = await _get(
      CinemanaRoutes.groupPage(groupId),
      query: {
        'pageNumber': page,
        'page': page,
        if (query.isNotEmpty) 'query': query,
      },
      ttl: const Duration(minutes: 5),
    );
    return _mediaList(raw);
  }

  Future<List<MediaItem>> search(
    String query, {
    int page = 1,
    String category = '',
    String type = '',
    int? fromYear,
    int? toYear,
    String star = '',
  }) async {
    final q = query.trim();
    final wantsMovies = type != 'series';
    final wantsSeries = type != 'movie';

    // SearchRequest في تطبيق Cinemana الأصلي يحمل هذه المفاتيح صراحة:
    // page/currentPage + moviesDataRequest + seriesDataRequest + staffTitle/category/star.
    // نرسلها كلها حتى يكون البحث مطابقاً أكثر للتطبيق الرسمي.
    Map<String, dynamic> base(String title) => <String, dynamic>{
      'videoTitle': title,
      'page': page,
      'currentPage': page,
      'moviesDataRequest': wantsMovies,
      'seriesDataRequest': wantsSeries,
      if (category.isNotEmpty) 'category': category,
      if (star.isNotEmpty) ...{'staffTitle': star, 'star': star},
      if (fromYear != null) 'fromYear': fromYear,
      if (toYear != null) 'toYear': toYear,
    };

    final variants = <String>[q];
    // بعض فهارس Cinemana تحتوي تهجئات غير دقيقة مثل From -> Frome.
    // لا نستبدل استعلام المستخدم؛ نجرب تهجئة إضافية فقط عند الحاجة.
    if (q.isNotEmpty && RegExp(r'^[A-Za-z0-9 ._-]+$').hasMatch(q)) {
      if (!q.toLowerCase().endsWith('e')) variants.add('${q}e');
      if (q.toLowerCase().endsWith('e') && q.length > 2) variants.add(q.substring(0, q.length - 1));
    }

    final collected = <MediaItem>[];
    Object? lastError;

    for (final title in variants) {
      final params = base(title);
      for (final attempt in <Future<dynamic> Function()>[
        () => _get(CinemanaRoutes.advancedSearch, query: params, ttl: const Duration(minutes: 2)),
        () => _post(CinemanaRoutes.advancedSearch, data: params),
        // بعض إصدارات الـAPI تتعامل مع 1/0 بدل true/false.
        () => _get(CinemanaRoutes.advancedSearch, query: {
          ...params,
          'moviesDataRequest': wantsMovies ? 1 : 0,
          'seriesDataRequest': wantsSeries ? 1 : 0,
        }, ttl: const Duration(minutes: 2)),
      ]) {
        try {
          final raw = await attempt();
          final items = _mediaList(raw);
          collected.addAll(items);
          if (items.isNotEmpty) break;
        } catch (error) {
          lastError = error;
        }
      }
    }

    var result = _unique(collected);
    if (type == 'movie') result = result.where((e) => !e.isSeries).toList();
    if (type == 'series') result = result.where((e) => e.isSeries).toList();

    if (result.isEmpty && lastError != null && kDebugMode) {
      debugPrint('[Cinematy API] search exhausted: $lastError');
    }
    return _rankSearch(result, q);
  }

  Future<List<MediaItem>> searchAll(String query, {int page = 1}) async {
    // نجمع الطلب العام + طلب الأفلام + طلب المسلسلات دائماً. بعض نسخ Cinemana
    // ترجع نوعاً واحداً فقط في البحث العام، وهذا كان يخفي مسلسلات معروفة.
    final results = await Future.wait<List<MediaItem>>([
      search(query, page: page),
      search(query, page: page, type: 'movie'),
      search(query, page: page, type: 'series'),
    ]);
    return _rankSearch(_unique([...results[0], ...results[1], ...results[2]]), query);
  }

  Future<List<MediaItem>> categoryVideos(String categoryId, {int page = 1}) async {
    final collected = <MediaItem>[];
    for (final params in <Map<String, dynamic>>[
      {
        'category': categoryId,
        'page': page,
        'currentPage': page,
        'moviesDataRequest': true,
        'seriesDataRequest': true,
      },
      {'categoryID': categoryId, 'page': page, 'currentPage': page},
      {'categoryNb': categoryId, 'page': page, 'currentPage': page},
    ]) {
      for (final attempt in <Future<dynamic> Function()>[
        () => _get(CinemanaRoutes.advancedSearch, query: params, ttl: const Duration(minutes: 5)),
        () => _post(CinemanaRoutes.advancedSearch, data: params),
      ]) {
        try {
          final raw = await attempt();
          final items = _mediaList(raw);
          collected.addAll(items);
          if (items.isNotEmpty) break;
        } catch (_) {}
      }
      if (collected.isNotEmpty) break;
    }
    return _unique(collected);
  }

  Future<List<MediaItem>> personWorks(Person person) async {
    final collected = <MediaItem>[];
    if (person.id.isNotEmpty) {
      try {
        final raw = await _get(CinemanaRoutes.staff(person.id), ttl: const Duration(hours: 1));
        collected.addAll(_mediaList(raw));
        for (final map in _flattenMaps(raw)) {
          final item = MediaItem.fromJson(map);
          if (item.id.isNotEmpty && (map.containsKey('kind') || map.containsKey('videoUploadDate'))) {
            collected.add(item);
          }
        }
      } catch (_) {}
    }
    for (final name in <String>[person.name, if (person.id.isNotEmpty) person.id]) {
      if (name.trim().isEmpty) continue;
      try {
        collected.addAll(await search('', star: name));
      } catch (_) {}
    }
    return _unique(collected);
  }

  List<MediaItem> _rankSearch(List<MediaItem> items, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return items;
    int score(MediaItem item) {
      final title = item.title.toLowerCase();
      final en = (item.raw['en_title'] ?? '').toString().toLowerCase();
      final other = (item.raw['other_title'] ?? '').toString().toLowerCase();
      if (title == q || en == q || other == q) return 100;
      if (title.startsWith(q) || en.startsWith(q) || other.startsWith(q)) return 70;
      if (title.contains(q) || en.contains(q) || other.contains(q)) return 50;
      return 0;
    }
    final copy = [...items]..sort((a, b) => score(b).compareTo(score(a)));
    return copy;
  }

  Future<ContentDetails> details(String id, {bool refresh = false}) async {
    final raw = await _get(
      CinemanaRoutes.videoInfo(id),
      ttl: AppConfig.detailsCacheTtl,
      refresh: refresh,
      requireNonEmpty: true,
    );
    final map = _firstMap(raw, keys: const ['videoInfo', 'data', 'video']);
    return ContentDetails.fromJson(map);
  }

  Future<List<SeasonGroup>> seasons(String id) async {
    final raw = await _get(
      CinemanaRoutes.seasons(id),
      ttl: const Duration(minutes: 12),
      refresh: true,
    );
    // الاستجابة الأصلية عبارة عن List من الحلقات وتحمل nb كمعرّف الحلقة.
    final maps = _flattenMaps(raw).where((map) {
      final hasEpisode = map.containsKey('episodeNummer') || map.containsKey('episodeNumber') || map.containsKey('episode');
      final hasId = map.containsKey('nb') || map.containsKey('videoId') || map.containsKey('videoID') || map.containsKey('id');
      return hasEpisode && hasId;
    });
    final episodes = maps.map(Episode.fromJson).where((e) => e.id.isNotEmpty).toList();
    final grouped = <int, List<Episode>>{};
    for (final episode in episodes) {
      (grouped[episode.seasonNumber <= 0 ? 1 : episode.seasonNumber] ??= []).add(episode);
    }
    final keys = grouped.keys.toList()..sort();
    return keys.map((key) {
      final values = grouped[key]!
        ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
      return SeasonGroup(key, values);
    }).toList();
  }

  Future<List<SeasonGroup>> seasonsFor(MediaItem media, {Map<String, dynamic> detailsRaw = const {}}) async {
    final ids = <String>{
      media.id,
      for (final key in const ['rootSeries', 'rootSeriesNb', 'seriesNb', 'parentNb', 'parentId', 'seriesID'])
        if ((detailsRaw[key] ?? media.raw[key])?.toString().trim().isNotEmpty == true)
          (detailsRaw[key] ?? media.raw[key]).toString().trim(),
    }..removeWhere((e) => e.isEmpty || e == '0');

    Object? lastError;
    for (final id in ids) {
      try {
        final result = await seasons(id);
        if (result.isNotEmpty) return result;
      } catch (e) {
        lastError = e;
      }
    }
    if (kDebugMode && lastError != null) debugPrint('[Cinematy API] seasonsFor: $lastError');
    return const [];
  }

  Future<List<VideoSource>> videoSources(String id) async {
    final raw = await _get(
      CinemanaRoutes.transcodes(id),
      ttl: const Duration(minutes: 10),
    );
    final maps = _flattenMaps(raw).where(
      (map) =>
          map.containsKey('videoUrl') ||
          map.containsKey('transcoddedFileName') ||
          map.containsKey('resolution') ||
          map.containsKey('quality'),
    );
    final result = maps
        .map(VideoSource.fromJson)
        .where((e) => e.url.isNotEmpty)
        .toList();
    final seen = <String>{};
    return result.where((e) => seen.add(e.url)).toList();
  }

  Future<List<SubtitleSource>> subtitles(String id) async {
    final raw = await _get(
      CinemanaRoutes.translations(id),
      ttl: const Duration(minutes: 20),
    );
    final result = <SubtitleSource>[];
    for (final map in _flattenMaps(raw)) {
      final ar = (map['arTranslationFilePath'] ?? map['arTranslationFile'] ?? '').toString().trim();
      final en = (map['enTranslationFilePath'] ?? map['enTranslationFile'] ?? '').toString().trim();
      if (ar.isNotEmpty) {
        result.add(SubtitleSource(url: normalizeMediaUrl(ar), language: 'ar', label: 'العربية'));
      }
      if (en.isNotEmpty) {
        result.add(SubtitleSource(url: normalizeMediaUrl(en), language: 'en', label: 'الإنجليزية'));
      }
      final generic = SubtitleSource.fromJson(map);
      if (generic.url.isNotEmpty && generic.url != normalizeMediaUrl(ar) && generic.url != normalizeMediaUrl(en)) {
        result.add(generic);
      }
    }
    final seen = <String>{};
    return result.where((e) => e.url.isNotEmpty && seen.add(e.url)).toList();
  }

  Future<Person?> person(String id) async {
    final raw = await _get(
      CinemanaRoutes.staff(id),
      ttl: const Duration(hours: 1),
    );
    final map = _firstMap(raw, keys: const ['staff', 'actor', 'data']);
    return map.isEmpty ? null : Person.fromJson(map);
  }

  Future<List<MediaItem>> recommendations(String id) async {
    Object? lastError;

    for (final base in _recommendationBases) {
      try {
        final response = await _dioFor(base).get<dynamic>(
          '/api/recommendation/recommend',
          queryParameters: {
            'MovieId': id,
            'ReProcessIfExpired': 'true',
          },
        );
        final data = _decodeResponse(response.data);
        _debug('GET', '$base/api/recommendation/recommend', response.statusCode ?? 0, data);
        return _mediaList(data);
      } on DioException catch (error) {
        lastError = error;
        _debugError('GET', '$base/api/recommendation/recommend', error);
      }
    }

    if (kDebugMode) {
      debugPrint('[Cinematy API] recommendations unavailable: ${_shortError(lastError)}');
    }
    return const [];
  }

  Future<void> clearApiCache() => _cache.clear();

  dynamic _decodeResponse(dynamic raw) {
    if (raw is! String) return raw;
    final value = raw.trim();
    if (value.isEmpty) return const <dynamic>[];
    try {
      return jsonDecode(value);
    } catch (_) {
      // إذا وصل HTML بدل JSON، نخليه نص حتى يظهر بالتشخيص ولا ينحفظ كمحتوى صالح.
      return value;
    }
  }

  bool _hasUsefulData(dynamic value) {
    if (value == null) return false;
    if (value is String) {
      final text = value.trim().toLowerCase();
      if (text.isEmpty) return false;
      if (text.startsWith('<!doctype html') || text.startsWith('<html')) return false;
      return true;
    }
    if (value is List) return value.isNotEmpty;
    if (value is Map) {
      if (value.isEmpty) return false;
      for (final entry in value.values) {
        if (_hasUsefulData(entry)) return true;
      }
      return false;
    }
    return true;
  }

  void _debug(String method, String target, int status, dynamic data) {
    if (!kDebugMode) return;
    var body = _safeJson(data);
    if (body.length > 1200) body = '${body.substring(0, 1200)}…';
    debugPrint('[Cinematy API] $method $target -> $status');
    debugPrint('[Cinematy API] RESPONSE: $body');
  }

  void _debugError(String method, String target, DioException error) {
    if (!kDebugMode) return;
    final status = error.response?.statusCode;
    final data = _decodeResponse(error.response?.data);
    var body = _safeJson(data);
    if (body.length > 800) body = '${body.substring(0, 800)}…';
    debugPrint('[Cinematy API] $method $target -> ERROR ${status ?? '-'}');
    debugPrint('[Cinematy API] ${error.type}: ${error.message}');
    if (body.isNotEmpty && body != 'null') {
      debugPrint('[Cinematy API] ERROR RESPONSE: $body');
    }
  }

  String _safeJson(dynamic value) {
    try {
      return jsonEncode(value);
    } catch (_) {
      return value?.toString() ?? 'null';
    }
  }

  String _shortError(Object? error) {
    if (error == null) return 'غير معروف';
    if (error is DioException) {
      final code = error.response?.statusCode;
      return code == null ? '${error.type}: ${error.message}' : 'HTTP $code: ${error.message}';
    }
    return error.toString();
  }

  List<MediaItem> _mediaList(dynamic raw) => JsonUtils.list(
        raw,
        candidateKeys: const [
          'videos',
          'videoList',
          'items',
          'movies',
          'series',
          'recommendations',
          'banners',
          'data',
          'results',
          'content',
        ],
      )
          .whereType<Map>()
          .map((e) => MediaItem.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.id.isNotEmpty)
          .toList();

  Map<String, dynamic> _firstMap(dynamic raw, {List<String> keys = const []}) {
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      for (final key in keys) {
        final value = map[key];
        if (value is Map) return Map<String, dynamic>.from(value);
        if (value is List && value.isNotEmpty && value.first is Map) {
          return Map<String, dynamic>.from(value.first as Map);
        }
      }
      return map;
    }
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      return Map<String, dynamic>.from(raw.first as Map);
    }
    return const {};
  }

  Iterable<Map<String, dynamic>> _flattenMaps(dynamic raw) sync* {
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      yield map;
      for (final value in map.values) {
        if (value is Map || value is List) yield* _flattenMaps(value);
      }
      return;
    }
    if (raw is List) {
      for (final value in raw) {
        if (value is Map || value is List) yield* _flattenMaps(value);
      }
    }
  }

  List<MediaItem> _unique(List<MediaItem> input) {
    final seen = <String>{};
    return input.where((e) => seen.add(e.id)).toList();
  }
}
