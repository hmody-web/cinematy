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
import '../models/network_access_state.dart';
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
  final Map<String, String> _categoryFingerprints = <String, String>{};
  final Map<String, bool> _categoryFilterIgnoredCache = <String, bool>{};

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

    final normalizedType = type.trim().toLowerCase();
    Map<String, dynamic> base(String title) => <String, dynamic>{
          'videoTitle': title,
          'page': page,
          'currentPage': page,
          // AdvancedSearch القديم يعتمد type=movie/series صراحةً، بينما
          // بعض نسخ الـ API الأحدث تفهم moviesDataRequest/seriesDataRequest.
          // نرسل الاثنين معاً لزيادة التوافق وعدم اختفاء المسلسلات.
          if (normalizedType == 'movie' || normalizedType == 'series')
            'type': normalizedType,
          'moviesDataRequest': wantsMovies,
          'seriesDataRequest': wantsSeries,
          if (category.isNotEmpty) 'category': category,
          if (star.isNotEmpty) ...{'staffTitle': star, 'star': star},
          if (fromYear != null) 'fromYear': fromYear,
          if (toYear != null) 'toYear': toYear,
        };

    final variants = _searchVariants(q);
    final collected = <MediaItem>[];
    Object? lastError;

    for (final title in variants) {
      final params = base(title);
      final attempts = <Future<dynamic> Function()>[
        () => _get(
              CinemanaRoutes.advancedSearch,
              query: params,
              ttl: const Duration(minutes: 2),
            ),
        () => _post(CinemanaRoutes.advancedSearch, data: params),
        () => _get(
              CinemanaRoutes.advancedSearch,
              query: {
                ...params,
                'moviesDataRequest': wantsMovies ? 1 : 0,
                'seriesDataRequest': wantsSeries ? 1 : 0,
              },
              ttl: const Duration(minutes: 2),
            ),
      ];

      for (final attempt in attempts) {
        try {
          final raw = await attempt();
          final items = _mediaList(raw);
          collected.addAll(items);
          if (items.isNotEmpty) break;
        } catch (error) {
          lastError = error;
        }
      }

      // لا نوسّع الشبكة بلا داعٍ إذا حصلنا على كمية جيدة من أول استعلام.
      if (collected.length >= 24) break;
    }

    // بعض نسخ API تفصل البحث بالممثل عن عنوان الفيديو.
    if (q.isNotEmpty && collected.length < 8 && star.isEmpty) {
      try {
        final raw = await _get(
          CinemanaRoutes.advancedSearch,
          query: {
            'staffTitle': q,
            'page': page,
            'currentPage': page,
            if (normalizedType == 'movie' || normalizedType == 'series')
              'type': normalizedType,
            'moviesDataRequest': wantsMovies,
            'seriesDataRequest': wantsSeries,
          },
          ttl: const Duration(minutes: 2),
        );
        collected.addAll(_mediaList(raw));
      } catch (_) {}
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
    final q = query.trim();
    if (q.isEmpty) return const <MediaItem>[];

    final collected = <MediaItem>[];
    try {
      collected.addAll(await search(q, page: page));
    } catch (_) {}

    if (collected.length < 12) {
      final typed = await Future.wait<List<MediaItem>>([
        search(q, page: page, type: 'movie').catchError((_) => <MediaItem>[]),
        search(q, page: page, type: 'series').catchError((_) => <MediaItem>[]),
      ]);
      collected.addAll(typed.expand((e) => e));
    }

    // fallback مهم لمسلسلات مثل From / Manifest / Lucifer: نفحص فهرس المجموعات
    // ونطلب البحث داخل المجموعات عندما تكون نتائج AdvancedSearch ناقصة.
    if (collected.length < 10) {
      try {
        final sections = await homeSections();
        final local = sections.expand((e) => e.items).where(
              (item) => _searchScore(item, q) >= 250,
            );
        collected.addAll(local);

        if (collected.length < 10) {
          final requests = sections.take(10).map((section) async {
            try {
              return await groupVideos(section.id, page: page, query: q);
            } catch (_) {
              return <MediaItem>[];
            }
          });
          final grouped = await Future.wait(requests);
          collected.addAll(grouped.expand((e) => e));
        }
      } catch (_) {}
    }

    return _rankSearch(_unique(collected), q);
  }

  Future<List<MediaItem>> categoryVideos(
    String categoryId, {
    String categoryTitle = '',
    int page = 1,
  }) async {
    final key = '$categoryId|$categoryTitle|$page';
    final id = categoryId.trim();
    final title = categoryTitle.trim();
    final filters = <({String field, String value})>[
      if (id.isNotEmpty) (field: 'category', value: id),
      if (title.isNotEmpty) (field: 'category', value: title),
      if (id.isNotEmpty) (field: 'categoryID', value: id),
      if (id.isNotEmpty) (field: 'categoryId', value: id),
      if (id.isNotEmpty) (field: 'category_id', value: id),
      if (id.isNotEmpty) (field: 'categoryNb', value: id),
      if (id.isNotEmpty) (field: 'catNb', value: id),
    ];

    final accepted = <MediaItem>[];

    // AdvancedSearch القديم يعتمد type=movie/series. لذلك نبحث في النوعين
    // بشكل منفصل ثم ندمج النتائج، بدلاً من طلب عام قد يتجاهل التصنيف.
    for (final mediaType in const <String>['movie', 'series']) {
      var foundForType = false;
      for (final filter in filters) {
        final params = <String, dynamic>{
          filter.field: filter.value,
          'type': mediaType,
          'page': page,
          'currentPage': page,
          'moviesDataRequest': mediaType == 'movie',
          'seriesDataRequest': mediaType == 'series',
        };

        for (final request in <Future<dynamic> Function()>[
          () => _get(
                CinemanaRoutes.advancedSearch,
                query: params,
                ttl: const Duration(minutes: 5),
              ),
          () => _post(CinemanaRoutes.advancedSearch, data: params),
        ]) {
          try {
            final raw = await request();
            final items = _unique(_mediaList(raw));
            if (items.isEmpty) continue;

            final strict = items
                .where(
                  (item) =>
                      _itemMatchesCategory(item, categoryId, categoryTitle),
                )
                .toList();

            // إذا العناصر نفسها تحمل category metadata نثق بالفلترة المحلية.
            if (strict.isNotEmpty) {
              accepted.addAll(strict);
              foundForType = true;
              break;
            }

            // بعض استجابات Cinemana لا تعيد genre/category داخل العنصر نفسه.
            // نتحقق عندها بطلب تحكم مستحيل: إذا أعاد نفس النتائج فهذا يعني
            // أن الخادم تجاهل معامل التصنيف، فلا نعرض نفس الأفلام بكل الأقسام.
            final ignored = await _categoryFilterWasIgnored(
              items: items,
              field: filter.field,
              type: mediaType,
              page: page,
            );
            if (ignored) continue;

            if (_looksLikeDuplicatedCategoryResult(
              '$key|$mediaType',
              items,
            )) {
              continue;
            }

            accepted.addAll(items);
            foundForType = true;
            break;
          } catch (_) {}
        }
        if (foundForType) break;
      }
    }

    if (accepted.isNotEmpty) return _unique(accepted);

    // fallback من مجموعات Cinemana نفسها عندما يتطابق اسم المجموعة مع التصنيف.
    try {
      final sections = await homeSections();
      final wanted = _normalizeSearch(categoryTitle);
      final matching = sections.where((section) {
        final sectionTitle = _normalizeSearch(section.title);
        return wanted.isNotEmpty &&
            (sectionTitle == wanted ||
                sectionTitle.contains(wanted) ||
                wanted.contains(sectionTitle));
      }).expand((section) => section.items).toList();
      if (matching.isNotEmpty) return _unique(matching);
    } catch (_) {}

    return const <MediaItem>[];
  }

  Future<bool> _categoryFilterWasIgnored({
    required List<MediaItem> items,
    required String field,
    required String type,
    required int page,
  }) async {
    if (items.length < 4) return false;
    final supportKey = '$field|$type';
    final cached = _categoryFilterIgnoredCache[supportKey];
    if (cached != null) return cached;

    try {
      final raw = await _get(
        CinemanaRoutes.advancedSearch,
        query: <String, dynamic>{
          field: '__cinematy_category_that_does_not_exist__',
          'type': type,
          'page': page,
          'currentPage': page,
          'moviesDataRequest': type == 'movie',
          'seriesDataRequest': type == 'series',
        },
        ttl: const Duration(minutes: 30),
      );
      final control = _unique(_mediaList(raw));
      final ignored = control.length >= 4 &&
          _mediaFingerprint(items) == _mediaFingerprint(control);
      _categoryFilterIgnoredCache[supportKey] = ignored;
      return ignored;
    } catch (_) {
      // لا نحفظ نتيجة الخطأ حتى يمكن إعادة التحقق في الطلب اللاحق.
      return false;
    }
  }

  String _mediaFingerprint(List<MediaItem> items) {
    final ids = items.take(12).map((e) => e.id).where((e) => e.isNotEmpty).toList()
      ..sort();
    return ids.join('|');
  }

  List<String> _searchVariants(String query) {
    final q = query.trim();
    if (q.isEmpty) return const <String>[''];
    final values = <String>{q};
    final normalizedSpaces = q.replaceAll(RegExp(r'\s+'), ' ').trim();
    values.add(normalizedSpaces);

    if (RegExp(r'^[A-Za-z0-9 ._\-]+$').hasMatch(q)) {
      final compact = q.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      if (compact.length >= 4) values.add(compact);
      if (q.length >= 6) values.add(q.substring(0, q.length - 1));
      if (q.length >= 5) values.add(q.substring(0, 4));
      if (!q.toLowerCase().endsWith('e')) values.add('${q}e');
      if (q.toLowerCase().endsWith('e') && q.length > 2) {
        values.add(q.substring(0, q.length - 1));
      }
    }
    return values.take(5).toList();
  }

  List<MediaItem> _rankSearch(List<MediaItem> items, String query) {
    final q = query.trim();
    if (q.isEmpty) return items;
    final scored = items
        .map((item) => (item: item, score: _searchScore(item, q)))
        .where((entry) => entry.score >= 180)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return scored.map((e) => e.item).toList();
  }

  int _searchScore(MediaItem item, String query) {
    final q = _normalizeSearch(query);
    if (q.isEmpty) return 1;
    final candidates = <String>{
      _normalizeSearch(item.title),
      _normalizeSearch((item.raw['en_title'] ?? '').toString()),
      _normalizeSearch((item.raw['other_title'] ?? '').toString()),
      _normalizeSearch((item.raw['custom_ar_title'] ?? '').toString()),
      _normalizeSearch((item.raw['ar_title'] ?? '').toString()),
    }..removeWhere((e) => e.isEmpty);

    var best = 0;
    for (final title in candidates) {
      if (title == q) best = best < 1000 ? 1000 : best;
      if (title.startsWith(q) || q.startsWith(title)) {
        best = best < 820 ? 820 : best;
      }
      if (title.contains(q) || q.contains(title)) {
        best = best < 680 ? 680 : best;
      }

      final qTokens = q.split(' ').where((e) => e.isNotEmpty).toSet();
      final tTokens = title.split(' ').where((e) => e.isNotEmpty).toSet();
      if (qTokens.isNotEmpty && tTokens.isNotEmpty) {
        final overlap = qTokens.intersection(tTokens).length / qTokens.length;
        final tokenScore = (overlap * 560).round();
        if (tokenScore > best) best = tokenScore;
      }

      final maxLen = q.length > title.length ? q.length : title.length;
      if (maxLen > 0 && maxLen <= 42) {
        final distance = _levenshtein(q, title);
        final similarity = 1 - (distance / maxLen);
        final fuzzy = (similarity * 520).round();
        if (fuzzy > best) best = fuzzy;
      }
    }
    return best;
  }

  String _normalizeSearch(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[أإآ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 0; i < a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);
      current[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        final insert = current[j] + 1;
        final delete = previous[j + 1] + 1;
        final replace = previous[j] + cost;
        current[j + 1] = [insert, delete, replace].reduce(
          (x, y) => x < y ? x : y,
        );
      }
      previous = current;
    }
    return previous.last;
  }

  bool _itemMatchesCategory(
    MediaItem item,
    String categoryId,
    String categoryTitle,
  ) {
    final id = categoryId.trim().toLowerCase();
    final title = _normalizeSearch(categoryTitle);
    final rawValues = <String>[];
    for (final key in const <String>[
      'catNb',
      'categoryNb',
      'categoryID',
      'categoryId',
      'category',
      'categories',
      'genre',
      'genres',
    ]) {
      final value = item.raw[key];
      if (value != null) rawValues.add(value.toString());
    }
    if (rawValues.isEmpty) return false;
    final joined = rawValues.join(' ').toLowerCase();
    if (id.isNotEmpty && joined.contains(id)) return true;
    if (title.isNotEmpty && _normalizeSearch(joined).contains(title)) return true;
    return false;
  }

  bool _looksLikeDuplicatedCategoryResult(
    String key,
    List<MediaItem> items,
  ) {
    if (items.length < 4) return false;
    final fingerprint = _mediaFingerprint(items);
    for (final entry in _categoryFingerprints.entries) {
      if (entry.key != key && entry.value == fingerprint) return true;
    }
    _categoryFingerprints[key] = fingerprint;
    return false;
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
    final collected = <SubtitleSource>[];

    // المسار المخصص للترجمة هو الأسرع عندما يكون متوفراً.
    try {
      final raw = await _get(
        CinemanaRoutes.translations(id),
        ttl: const Duration(minutes: 20),
      );
      collected.addAll(_subtitleList(raw));
    } catch (_) {}

    // Cinemana القديمة تضع translations داخل allVideoInfo نفسه
    // (name + file). هذا fallback مهم جداً للتنزيلات وللحلقات.
    if (collected.isEmpty) {
      try {
        final raw = await _get(
          CinemanaRoutes.videoInfo(id),
          ttl: AppConfig.detailsCacheTtl,
        );
        collected.addAll(_subtitleList(raw));
      } catch (_) {}
    }

    final seen = <String>{};
    return collected
        .where((e) => e.url.isNotEmpty && seen.add(e.url))
        .toList();
  }

  List<SubtitleSource> _subtitleList(dynamic raw) {
    final result = <SubtitleSource>[];
    for (final map in _flattenMaps(raw)) {
      final ar = (map['arTranslationFilePath'] ??
              map['arTranslationFile'] ??
              '')
          .toString()
          .trim();
      final en = (map['enTranslationFilePath'] ??
              map['enTranslationFile'] ??
              '')
          .toString()
          .trim();
      if (ar.isNotEmpty) {
        result.add(
          SubtitleSource(
            url: normalizeMediaUrl(ar),
            language: 'ar',
            label: 'العربية',
          ),
        );
      }
      if (en.isNotEmpty) {
        result.add(
          SubtitleSource(
            url: normalizeMediaUrl(en),
            language: 'en',
            label: 'الإنجليزية',
          ),
        );
      }

      // الشكل القديم: {name: "Arabic", file: "...srt"}
      // والشكل العام: {url/path/file, lang/language/display_name}.
      final looksLikeSubtitle =
          map.containsKey('arTranslationFilePath') ||
              map.containsKey('enTranslationFilePath') ||
              ((map.containsKey('file') ||
                      map.containsKey('url') ||
                      map.containsKey('path')) &&
                  (map.containsKey('name') ||
                      map.containsKey('lang') ||
                      map.containsKey('language') ||
                      map.containsKey('display_name')));
      if (looksLikeSubtitle) {
        final generic = SubtitleSource.fromJson(map);
        if (generic.url.isNotEmpty &&
            generic.url != normalizeMediaUrl(ar) &&
            generic.url != normalizeMediaUrl(en)) {
          result.add(generic);
        }
      }
    }
    return result;
  }

  Future<List<MediaItem>> personWorks(Person person) async {
    final collected = <MediaItem>[];

    if (person.id.isNotEmpty) {
      try {
        final raw = await _get(
          CinemanaRoutes.staff(person.id),
          ttl: const Duration(hours: 1),
        );
        collected.addAll(_mediaList(raw));

        // بعض استجابات staff تكون متداخلة ولا تمر مباشرة عبر _mediaList.
        for (final map in _flattenMaps(raw)) {
          final item = MediaItem.fromJson(map);
          if (item.id.isNotEmpty &&
              (map.containsKey('kind') ||
                  map.containsKey('videoUploadDate') ||
                  map.containsKey('videoTitle') ||
                  map.containsKey('title'))) {
            collected.add(item);
          }
        }
      } catch (_) {
        // لا نوقف صفحة الممثل إذا كان endpoint الخاص به غير متاح.
      }
    }

    // fallback: البحث باسم الممثل يعطي الأعمال حتى عندما staff يرجع الملف
    // الشخصي فقط ولا يعيد قائمة الأعمال.
    if (person.name.trim().isNotEmpty) {
      try {
        collected.addAll(await search('', star: person.name.trim()));
      } catch (_) {}
    }

    return _unique(collected);
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

  Future<NetworkAccessState> accessState() async {
    // لا نعتمد على /api/info/userInfo وحده لتحديد شبكة إيرثلنك.
    // هذا المسار قد يرجع 403 في بعض إعدادات سينمانا حتى والجهاز داخل الشبكة.
    // بدلاً من ذلك نفحص نفس مسارات المحتوى التي يعتمد عليها التطبيق فعلياً.
    final probes = <String>[
      CinemanaRoutes.videoGroups(AppConfig.language),
      CinemanaRoutes.banner(0),
      CinemanaRoutes.categories,
    ];

    Object? lastError;
    var explicitDenied = 0;
    var reachedCinemana = 0;

    for (final base in _contentBases) {
      final dio = Dio(
        BaseOptions(
          baseUrl: base,
          connectTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 6),
          sendTimeout: const Duration(seconds: 6),
          responseType: ResponseType.plain,
          validateStatus: (status) => status != null && status < 500,
          headers: const {
            'Accept': 'application/json, text/plain, */*',
            'Accept-Language': 'ar-IQ,ar;q=0.9,en;q=0.4',
            'User-Agent': 'Cinematy/1.0 (Flutter; Android/iOS)',
            'Cache-Control': 'no-cache',
          },
        ),
      );

      for (final path in probes) {
        try {
          final response = await dio.get<dynamic>(path);
          final status = response.statusCode ?? 0;

          if (status >= 200 && status < 400) {
            return const NetworkAccessState(NetworkAccessKind.online);
          }

          // وصلنا فعلياً إلى خادم سينمانا، لكن الخادم رفض الوصول صراحةً.
          if (status == 401 || status == 403 || status == 451) {
            explicitDenied++;
            reachedCinemana++;
            continue;
          }

          // 404/405 مثلاً تعني أن الدومين نفسه قابل للوصول؛
          // لا نعتبرها دليلاً على أن المستخدم خارج إيرثلنك.
          if (status >= 400 && status < 500) {
            reachedCinemana++;
          }
        } on DioException catch (error) {
          lastError = error;
          final code = error.response?.statusCode;
          if (code == 401 || code == 403 || code == 451) {
            explicitDenied++;
            reachedCinemana++;
          }
        } catch (error) {
          lastError = error;
        }
      }
    }

    // إذا لا يوجد إنترنت أصلاً، نعرض وضع عدم الاتصال.
    final internet = await _probeInternet();
    if (!internet) {
      return NetworkAccessState(
        NetworkAccessKind.offline,
        details: _shortError(lastError),
      );
    }

    // نعرض "خارج إيرثلنك" فقط عندما نحصل على رفض صريح من خوادم
    // سينمانا الفعلية. هذا يمنع ظهور الرسالة خطأ بسبب userInfo أو عطل مؤقت.
    if (explicitDenied > 0 && reachedCinemana > 0) {
      return NetworkAccessState(
        NetworkAccessKind.outsideEarthlink,
        details: 'Cinemana access denied ($explicitDenied)',
      );
    }

    // الإنترنت يعمل لكن فحص سينمانا كان غير حاسم (timeout / عطل بالخادم).
    // لا نتهم الشبكة بأنها خارج إيرثلنك؛ نعاملها مؤقتاً كعدم توفر خدمة.
    return NetworkAccessState(
      NetworkAccessKind.offline,
      details: _shortError(lastError),
    );
  }

  Future<bool> _probeInternet() async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 4),
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    for (final url in const <String>[
      'https://www.gstatic.com/generate_204',
      'https://www.google.com/generate_204',
      'https://www.cloudflare.com/cdn-cgi/trace',
    ]) {
      try {
        final response = await dio.get<dynamic>(url);
        if ((response.statusCode ?? 600) < 500) return true;
      } catch (_) {}
    }
    return false;
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
