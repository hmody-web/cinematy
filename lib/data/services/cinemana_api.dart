import 'dart:async';
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
    // تطبيق Cinemana 3.4.2 الرسمي المرفق يستخدم نطاق .com حرفياً.
    'https://cinemana.shabakaty.com',
    // يبقى .cc كـ fallback فقط للإصدارات/الشبكات التي تحوله إليه.
    'https://cinemana.shabakaty.cc',
  ];

  static const List<String> _recommendationBases = <String>[
    'https://recommend.shabakaty.cc',
    'https://recommend.shabakaty.com',
  ];

  final ApiDiskCache _cache = ApiDiskCache();
  final Map<String, String> _categoryFingerprints = <String, String>{};
  final Map<String, bool> _categoryFilterIgnoredCache = <String, bool>{};
  // أفلام التصنيفات الحقيقية القادمة داخل /categories نفسه.
  final Map<String, List<MediaItem>> _embeddedCategoryItems = <String, List<MediaItem>>{};
  // langNb المرتبط بكل Category كما يعيده تطبيق Cinemana داخل langArray.
  // هذا الحقل مهم جداً لطلب /video/V/2 ولا يجوز إسقاطه.
  final Map<String, String> _categoryLanguageIds = <String, String>{};

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

  Future<dynamic> _postForm(
    String path, {
    Map<String, dynamic>? data,
    String? forceBase,
  }) async {
    Object? lastError;
    final bases = forceBase == null
        ? _contentBases
        : <String>[forceBase, ..._contentBases.where((e) => e != forceBase)];

    for (final base in bases) {
      try {
        final response = await _dioFor(base).post<dynamic>(
          path,
          data: data,
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
            headers: const {
              'Accept': 'application/json, text/plain, */*',
            },
          ),
        );
        final decoded = _decodeResponse(response.data);
        _debug('POST-FORM', '$base$path', response.statusCode ?? 0, decoded);
        return decoded;
      } on DioException catch (error) {
        lastError = error;
        _debugError('POST-FORM', '$base$path', error);
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError('فشل POST form على مصدر سينمانا: ${_shortError(lastError)}');
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

  /// تصنيفات صفحة «اكتشف» من نفس endpoint الذي يستخدمه Cinemana الأصلي.
  ///
  /// ملاحظة مهمة من الـ IPA: Category.videoInfo ليس شرطاً أن يكون Map، كما أن
  /// categoryNb قد لا يكون في جذر Category بل داخل langArray. الإصدار السابق
  /// اشترط شكل JSON واحداً فقط، ولذلك أسقط كل التصنيفات عند بعض استجابات الخادم.
  Future<List<MediaCategory>> categories({bool refresh = false}) async {
    try {
      final raw = await _get(
        CinemanaRoutes.categories,
        refresh: refresh,
        ttl: const Duration(minutes: 30),
        requireNonEmpty: true,
      );

      final found = <MediaCategory>[];
      final seen = <String>{};
      _embeddedCategoryItems.clear();
      _categoryLanguageIds.clear();

      List<Map<String, dynamic>> languageEntries(dynamic value) {
        final out = <Map<String, dynamic>>[];
        void walkLang(dynamic node) {
          if (node is List) {
            for (final e in node) walkLang(e);
            return;
          }
          if (node is! Map) return;
          final map = Map<String, dynamic>.from(node);
          final hasCat = JsonUtils.string(map, const [
            'catNb', 'categoryNb', 'category_id', 'nb'
          ]).trim().isNotEmpty;
          final hasLang = JsonUtils.string(map, const [
            'langNb', 'languageNb', 'langArTitle', 'langEnTitle'
          ]).trim().isNotEmpty;
          if (hasCat || hasLang) out.add(map);
          for (final v in map.values) {
            if (v is List || v is Map) walkLang(v);
          }
        }
        walkLang(value);
        return out;
      }

      String firstImage(dynamic node) {
        String result = '';
        void walkImage(dynamic value) {
          if (result.isNotEmpty || value == null) return;
          if (value is String) {
            final v = value.trim();
            if (v.startsWith('http://') || v.startsWith('https://')) {
              result = normalizeMediaUrl(v);
            }
            return;
          }
          if (value is List) {
            for (final e in value) {
              walkImage(e);
              if (result.isNotEmpty) return;
            }
            return;
          }
          if (value is! Map) return;
          final map = Map<String, dynamic>.from(value);
          for (final key in const [
            'imgMediumThumbObjUrl',
            'imgThumbObjUrl',
            'imgObjUrl',
            'imgMediumThumb',
            'imgThumb',
            'poster',
            'image',
            'cover',
          ]) {
            final candidate = (map[key] ?? '').toString().trim();
            if (candidate.isNotEmpty) {
              result = normalizeMediaUrl(candidate);
              if (result.isNotEmpty) return;
            }
          }
          for (final v in map.values) {
            if (v is List || v is Map || v is String) {
              walkImage(v);
              if (result.isNotEmpty) return;
            }
          }
        }
        walkImage(node);
        return result;
      }

      void addCategory(Map<String, dynamic> map) {
        final title = JsonUtils.string(map, const [
          'arTitle', 'ar_title', 'lang_ar_title', 'custom_ar_title',
          'title', 'enTitle', 'en_title', 'lang_en_title', 'name',
        ]).trim();
        if (title.isEmpty || _looksLikeLanguageCategory(title)) return;

        // نفس خصائص Category الموجودة كسلاسل داخل تطبيق Cinemana.
        final looksLikeCategory = map.containsKey('langArray') ||
            map.containsKey('videoInfo') ||
            map.containsKey('categoryDescription') ||
            map.containsKey('porder');
        if (!looksLikeCategory) return;

        final langs = languageEntries(map['langArray']);
        Map<String, dynamic>? selected;
        if (langs.isNotEmpty) {
          // نفضل السجل العربي إن وجد، وإلا أول سجل فعلي.
          for (final lang in langs) {
            final label = JsonUtils.string(lang, const [
              'langArTitle', 'langEnTitle', 'lang_ar_title', 'lang_en_title'
            ]).toLowerCase();
            if (label.contains('عرب') || label.contains('arab')) {
              selected = lang;
              break;
            }
          }
          selected ??= langs.first;
        }

        var id = JsonUtils.string(map, const [
          'categoryNb', 'catNb', 'nb', 'categoryID', 'categoryId', 'category_id'
        ]).trim();
        if (id.isEmpty && selected != null) {
          id = JsonUtils.string(selected, const [
            'catNb', 'categoryNb', 'category_id', 'nb'
          ]).trim();
        }
        // لا نسقط التصنيف لمجرد اختلاف شكل الاستجابة؛ هذا fallback للعرض فقط.
        if (id.isEmpty) id = 'title:${_normalizeSearch(title)}';

        final key = _normalizeSearch(title);
        if (key.isEmpty || !seen.add(key)) return;

        final langNb = selected == null
            ? ''
            : JsonUtils.string(selected, const ['langNb', 'languageNb']).trim();
        if (langNb.isNotEmpty) _categoryLanguageIds[id] = langNb;

        var count = JsonUtils.integer(map, const ['count', 'itemsCount']);
        if (count <= 0 && selected != null) {
          count = JsonUtils.integer(selected, const ['langFreq', 'count', 'itemsCount']);
        }

        final embedded = <MediaItem>[];
        final vi = map['videoInfo'];
        if (vi != null) embedded.addAll(_mediaList(vi));
        final ready = _unique(embedded)
            .where((e) => e.id.isNotEmpty)
            .toList(growable: false);
        if (ready.isNotEmpty) _embeddedCategoryItems[id] = ready;

        found.add(MediaCategory(
          id: id,
          title: title,
          count: count > ready.length ? count : ready.length,
          coverUrl: firstImage(vi),
          languageId: langNb,
          order: JsonUtils.integer(map, const ['porder', 'order']),
        ));
      }

      void walk(dynamic node) {
        if (node is List) {
          for (final e in node) walk(e);
          return;
        }
        if (node is! Map) return;
        final map = Map<String, dynamic>.from(node);
        addCategory(map);
        // langArray لا يتم تحويله إلى تصنيفات لأن addCategory يتطلب خصائص Category.
        for (final v in map.values) {
          if (v is List || v is Map) walk(v);
        }
      }

      walk(raw);

      // في بعض إصدارات الخادم تكون /category قائمة Genres أبسط. نستخدمها فقط
      // إذا /categories نفسها لم تنتج أي بطاقة، بدون إضافة أي تصنيف يدوي.
      if (found.isEmpty) {
        final fallbackRaw = await _get(
          CinemanaRoutes.category,
          refresh: refresh,
          ttl: const Duration(minutes: 30),
          requireNonEmpty: true,
        );
        for (final map in _flattenMaps(fallbackRaw)) {
          final title = JsonUtils.string(map, const [
            'arTitle', 'ar_title', 'lang_ar_title', 'title',
            'enTitle', 'en_title', 'name'
          ]).trim();
          if (title.isEmpty || _looksLikeLanguageCategory(title)) continue;
          final id = JsonUtils.string(map, const [
            'nb', 'categoryNb', 'catNb', 'categoryID', 'categoryId', 'category_id', 'id'
          ]).trim();
          if (id.isEmpty) continue;
          final key = _normalizeSearch(title);
          if (key.isEmpty || !seen.add(key)) continue;
          found.add(MediaCategory(id: id, title: title));
        }
      }

      // المطلوب: التصنيفات التي لديها محتوى/غلاف أولاً، ثم ترتيب Cinemana.
      found.sort((a, b) {
        final aReady = (a.count > 0 || a.coverUrl.isNotEmpty) ? 1 : 0;
        final bReady = (b.count > 0 || b.coverUrl.isNotEmpty) ? 1 : 0;
        final byReady = bReady.compareTo(aReady);
        if (byReady != 0) return byReady;
        final byCount = b.count.compareTo(a.count);
        if (byCount != 0) return byCount;
        final ao = a.order <= 0 ? 1 << 20 : a.order;
        final bo = b.order <= 0 ? 1 << 20 : b.order;
        return ao.compareTo(bo);
      });

      if (found.isNotEmpty) unawaited(_warmCategoryFirstPages(found));
      return found;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Cinematy API] Cinemana categories -> $error');
      }
      return const <MediaCategory>[];
    }
  }

  bool _looksLikeLanguageCategory(String value) {
    final v = _normalizeSearch(value);
    const blocked = <String>{
      'arabic', 'english', 'العربية', 'العربي', 'انجليزي', 'الانجليزية',
      'english language', 'arabic language', 'languages', 'language', 'اللغات', 'لغة',
    };
    return blocked.contains(v);
  }

  /// أول صفحة يتم تخزينها في الذاكرة حتى الدخول إلى التصنيف يكون فورياً.
  List<MediaItem> categoryCachedVideos(String categoryId) {
    final items = _embeddedCategoryItems[categoryId.trim()];
    if (items == null || items.isEmpty) return const <MediaItem>[];
    return List<MediaItem>.unmodifiable(items);
  }

  Future<void> _warmCategoryFirstPages(List<MediaCategory> categories) async {
    // أول التصنيفات هي الأكثر ظهوراً للمستخدم؛ نسخن 8 بالتوازي فوراً.
    final first = categories.take(8).toList(growable: false);
    await Future.wait(first.map((category) async {
      try {
        await categoryVideos(category.id, page: 1);
      } catch (_) {}
    }));

    // البقية تسخن بالتتابع حتى لا نغرق خادم Cinemana بعشرات الطلبات دفعة واحدة.
    for (final category in categories.skip(8)) {
      if (_embeddedCategoryItems.containsKey(category.id)) continue;
      try {
        await categoryVideos(category.id, page: 1);
      } catch (_) {}
    }
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

  /// بحث Cinemana المطابق لطريقة البحث الفعلية في تطبيق Cinemana:
  /// GET /api/android/AdvancedSearch?videoTitle=...&type=movie|series
  ///
  /// إذا لم يحدد المستدعي النوع، نبحث movie و series بالتوازي حتى تبقى
  /// الاستجابة سريعة وتظهر المكتبة كاملة كما في التطبيق الأصلي.
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
    if (q.isEmpty) return const <MediaItem>[];

    final normalizedType = type.trim().toLowerCase();
    final requestedTypes = normalizedType == 'movie' || normalizedType == 'series'
        ? <String>[normalizedType]
        : const <String>['movie', 'series'];

    final batches = await Future.wait<List<MediaItem>>(
      requestedTypes.map((mediaType) async {
        try {
          final raw = await _advancedSearchExactFast(
            title: q,
            type: mediaType,
            page: page,
            star: star,
            category: category,
            fromYear: fromYear,
            toYear: toYear,
          );
          return _mediaList(raw);
        } catch (error) {
          if (kDebugMode) {
            debugPrint('[Cinematy API] exact search $mediaType: ${_shortError(error)}');
          }
          return <MediaItem>[];
        }
      }),
    );

    return _rankSearch(_unique(batches.expand((e) => e).toList()), q);
  }

  /// نفس طلب تطبيق Cinemana حرفياً تقريباً، لكن ندعم .com و .cc معاً.
  /// النطاقان ينطلقان بالتوازي ونأخذ أول استجابة تحتوي بيانات فعلية.
  Future<dynamic> _advancedSearchExactFast({
    required String title,
    required String type,
    int page = 1,
    String star = '',
    String category = '',
    int? fromYear,
    int? toYear,
  }) async {
    final params = <String, dynamic>{
      'videoTitle': title,
      'type': type,
      if (star.trim().isNotEmpty) 'star': star.trim(),
      if (category.trim().isNotEmpty) 'category': category.trim(),
      if (fromYear != null) 'fromYear': fromYear,
      if (toYear != null) 'toYear': toYear,
      if (page > 1) 'page': page,
    };

    final cacheKey = 'cinemana-exact-search-v7|${jsonEncode(params)}';
    final cached = await _cache.get(cacheKey, const Duration(minutes: 3));
    if (cached != null && _hasUsefulData(cached)) return cached;

    final completer = Completer<dynamic>();
    var finished = 0;
    dynamic firstEmpty;
    Object? lastError;

    Future<void> launch(String base) async {
      try {
        final response = await _dioFor(base).get<dynamic>(
          CinemanaRoutes.advancedSearch,
          queryParameters: params,
          options: Options(
            headers: const {'Accept': 'application/json, text/plain, */*'},
          ),
        );
        final decoded = _decodeResponse(response.data);
        _debug('SEARCH', '$base${CinemanaRoutes.advancedSearch}',
            response.statusCode ?? 0, decoded);

        if (_hasUsefulData(decoded)) {
          if (!completer.isCompleted) completer.complete(decoded);
          return;
        }
        firstEmpty ??= decoded;
      } catch (error) {
        lastError = error;
        if (kDebugMode) {
          debugPrint('[Cinematy API] SEARCH $base -> ${_shortError(error)}');
        }
      } finally {
        finished++;
        if (finished == _contentBases.length && !completer.isCompleted) {
          if (firstEmpty != null) {
            completer.complete(firstEmpty);
          } else {
            completer.completeError(
              StateError('فشل بحث سينمانا: ${_shortError(lastError)}'),
            );
          }
        }
      }
    }

    for (final base in _contentBases) {
      launch(base);
    }

    final result = await completer.future;
    if (_hasUsefulData(result)) {
      await _cache.put(cacheKey, result);
    }
    return result;
  }

  Future<List<MediaItem>> searchAll(String query, {int page = 1}) async {
    final q = query.trim();
    if (q.isEmpty) return const <MediaItem>[];

    // المسار الأساسي: نفس AdvancedSearch في تطبيق Cinemana، movie + series
    // بالتوازي. لا نفحص مجموعات أو صفحات عديدة، لذلك البحث سريع.
    final direct = await search(q, page: page);
    if (direct.isNotEmpty) return direct;

    // Alias صغير فقط للأعمال التي لها اسم تجاري مختلف تماماً.
    final aliases = _exactSearchAliases(q);
    if (aliases.isEmpty) return const <MediaItem>[];

    final batches = await Future.wait<List<MediaItem>>(
      aliases.map((alias) => search(alias, page: page)),
    );
    return _rankSearch(_unique(batches.expand((e) => e).toList()), q);
  }

  List<String> _exactSearchAliases(String query) {
    final normalized = _normalizeSearch(query);
    const aliases = <String, List<String>>{
      'la casa de papel': <String>['Money Heist'],
      'money heist': <String>['La Casa de Papel'],
    };
    return aliases[normalized] ?? const <String>[];
  }

  /// محتوى التصنيف بنفس endpoint الموجود حرفياً في Cinemana 3.4.2:
  /// /api/android/video/V/2
  ///
  /// CategoryMoviesRequest في الـ IPA يحمل الحقول:
  /// categoryNb, videoKind, langNb, itemsPerPage, pageNumber,
  /// level, sortParam, currentPage.
  Future<List<MediaItem>> categoryVideos(
    String categoryId, {
    String categoryTitle = '',
    int page = 1,
  }) async {
    final id = categoryId.trim();
    if (id.isEmpty) return const <MediaItem>[];

    if (page == 1) {
      final cached = _embeddedCategoryItems[id];
      if (cached != null && cached.isNotEmpty) return cached;
    }

    final cacheKey = 'cinemana-category-v2-exact|$id|$page';
    final diskCached = await _cache.get(cacheKey, const Duration(minutes: 20));
    if (diskCached != null) {
      final cachedItems = _unique(_mediaList(diskCached));
      if (cachedItems.isNotEmpty) {
        if (page == 1) _embeddedCategoryItems[id] = cachedItems;
        return cachedItems;
      }
    }

    // kind=1 و kind=2 هما Movies / Series في بيانات Cinemana. نطلقهما
    // بالتوازي ونمزجهما حتى لا يضيع أي نوع من التصنيف.
    final langNb = _categoryLanguageIds[id] ?? '';

    // في Binary تطبيق Cinemana، RawValue الخاص بـ CategoryMovieType يظهر
    // كـ Movies / Series. لذلك نجرب القيم النصية أولاً مع langNb الحقيقي.
    final batches = await Future.wait<List<MediaItem>>([
      _categoryMoviesExact(id, videoKind: 'Movies', langNb: langNb, page: page),
      _categoryMoviesExact(id, videoKind: 'Series', langNb: langNb, page: page),
    ]);
    var result = _unique(batches.expand((e) => e).toList());

    // fallback فقط للخوادم التي تتوقع enum رقمي.
    if (result.isEmpty) {
      final numericBatches = await Future.wait<List<MediaItem>>([
        _categoryMoviesExact(id, videoKind: '1', langNb: langNb, page: page),
        _categoryMoviesExact(id, videoKind: '2', langNb: langNb, page: page),
      ]);
      result = _unique(numericBatches.expand((e) => e).toList());
    }

    if (result.isNotEmpty) {
      await _cache.put(cacheKey, result.map((e) => e.toJson()).toList());
      if (page == 1) _embeddedCategoryItems[id] = result;
    }
    return result;
  }

  Future<List<MediaItem>> _categoryMoviesExact(
    String categoryNb, {
    required String videoKind,
    required String langNb,
    required int page,
  }) async {
    const path = '/api/android/video/V/2';
    final params = <String, dynamic>{
      'categoryNb': categoryNb,
      'videoKind': videoKind,
      'itemsPerPage': 60,
      'pageNumber': page,
      'currentPage': page,
      'level': 0,
      'sortParam': '',
      if (langNb.isNotEmpty) 'langNb': langNb,
    };

    // نستخدم .com و .cc بالتوازي كما طلب المستخدم. كذلك نجرب GET و
    // form-urlencoded بالتوازي لأن نسخ Shabakaty المختلفة قبلت الطريقتين،
    // ونأخذ أول نتيجة مفيدة ثم نلغي انتظار البقية منطقياً.
    final completer = Completer<List<MediaItem>>();
    var finished = 0;
    final total = _contentBases.length * 2;
    Object? lastError;

    Future<void> finishOne(List<MediaItem> items) async {
      if (items.isNotEmpty && !completer.isCompleted) {
        completer.complete(items);
      }
      finished++;
      if (finished >= total && !completer.isCompleted) {
        if (lastError != null && kDebugMode) {
          debugPrint('[Cinematy API] category exact empty: ${_shortError(lastError)}');
        }
        completer.complete(const <MediaItem>[]);
      }
    }

    for (final base in _contentBases) {
      () async {
        try {
          final response = await _dioFor(base).get<dynamic>(path, queryParameters: params);
          final raw = _decodeResponse(response.data);
          _debug('CATEGORY-GET', '$base$path', response.statusCode ?? 0, raw);
          await finishOne(_unique(_mediaList(raw)));
        } catch (e) {
          lastError = e;
          await finishOne(const <MediaItem>[]);
        }
      }();

      () async {
        try {
          final response = await _dioFor(base).post<dynamic>(
            path,
            data: params,
            options: Options(contentType: Headers.formUrlEncodedContentType),
          );
          final raw = _decodeResponse(response.data);
          _debug('CATEGORY-FORM', '$base$path', response.statusCode ?? 0, raw);
          await finishOne(_unique(_mediaList(raw)));
        } catch (e) {
          lastError = e;
          await finishOne(const <MediaItem>[]);
        }
      }();
    }

    return completer.future;
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
      if (compact.length >= 4 && compact.toLowerCase() != q.toLowerCase()) {
        values.add(compact);
      }

      // لا نقطع العناوين القصيرة مثل From؛ ذلك كان يولد نتائج بعيدة جداً.
      // نستخدم typo-tolerant variants فقط للعناوين الأطول.
      if (q.length >= 7) {
        values.add(q.substring(0, q.length - 1));
      }
    }
    return values.take(4).toList();
  }

  List<MediaItem> _rankSearch(List<MediaItem> items, String query) {
    final q = query.trim();
    if (q.isEmpty) return items;
    final scored = items
        .map((item) => (item: item, score: _searchScore(item, q)))
        .where((entry) => entry.score >= 150)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return scored.map((e) => e.item).toList();
  }

  Set<String> _searchCandidateTitles(MediaItem item) {
    final candidates = <String>{
      _normalizeSearch(item.title),
      for (final key in const <String>[
        'en_title',
        'ar_title',
        'lang_ar_title',
        'custom_ar_title',
        'other_title',
        'otherTitle',
        'original_title',
        'originalTitle',
        'display_name',
        'name',
        'title',
      ])
        _normalizeSearch((item.raw[key] ?? '').toString()),
    }..removeWhere((value) => value.isEmpty);
    return candidates;
  }

  int _searchScore(MediaItem item, String query) {
    final q = _normalizeSearch(query);
    if (q.isEmpty) return 1;
    final candidates = _searchCandidateTitles(item);

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
