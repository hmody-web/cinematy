import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/category.dart';
import '../models/content_details.dart';
import '../models/content_source.dart';
import '../models/episode.dart';
import '../models/media_item.dart';
import '../models/video_source.dart';

class WebSourceApi {
  WebSourceApi(this.source)
      : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 16),
            receiveTimeout: const Duration(seconds: 22),
            followRedirects: true,
            maxRedirects: 8,
            headers: const {
              'User-Agent':
                  'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1',
              'Accept-Language': 'ar,en-US;q=0.7,en;q=0.3',
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,application/json;q=0.8,*/*;q=0.7',
            },
            responseType: ResponseType.plain,
          ),
        );

  final ContentSourceDefinition source;
  final Dio _dio;
  final Map<String, _AkwamCacheEntry> _akwamListCache = <String, _AkwamCacheEntry>{};
  Map<String, dynamic>? _jsonProviderDescriptor;

  static const _tmdbKey = '8476a7ab80ad76f0936744df0430e67c';

  List<String> get _baseCandidates {
    final values = <String>[source.baseUrl];
    switch (source.id) {
      case 'wecima':
        values.addAll(const [
          'https://wecima.cc',
          'https://wecimma.com',
          'https://wecima.sarl',
          'https://wecima.date',
        ]);
        break;
      case 'alooytv':
        values.addAll(const ['https://alooytv.tv', 'https://a.alooytv8.xyz']);
        break;
      case 'akwam':
        values.addAll(const [
          'https://akwam.ss',
          'https://akwams.org',
          'https://akwam.top',
          'https://akwam.org',
        ]);
        break;
      case 'krmzi':
        values.add('https://krmzi.org');
        break;
      case 'videoviola':
        values.add('https://hd.vio-la.com');
        break;
      case 'royaldrama':
        values.add('https://royal-drama.com');
        break;
    }
    return values
        .map((e) => e.trim().replaceFirst(RegExp(r'/+$'), ''))
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  String _originOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return source.baseUrl;
    return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
  }

  String _abs(String value, {String? pageUrl}) {
    var v = value.trim();
    if (v.isEmpty || v == '#' || v.toLowerCase().startsWith('javascript:')) {
      return '';
    }
    v = v.replaceAll(r'\/', '/').replaceAll('&amp;', '&');
    if (v.startsWith('//')) return 'https:$v';
    if (v.startsWith('http://') || v.startsWith('https://')) return v;
    final base = Uri.tryParse(pageUrl ?? source.baseUrl);
    if (base == null) return v;
    try {
      return base.resolve(v).toString();
    } catch (_) {
      return v;
    }
  }

  Future<_FetchedPage> _getPage(String url, {String? referer}) async {
    final response = await _dio.get<String>(
      url,
      options: Options(
        headers: {
          if (referer != null && referer.isNotEmpty) 'Referer': referer,
        },
      ),
    );
    final resolved = response.realUri.toString();
    return _FetchedPage(resolved, response.data ?? '');
  }

  Future<_FetchedPage> _firstWorkingPage(
    Iterable<String> urls, {
    bool requireBody = true,
  }) async {
    Object? last;
    for (final raw in urls) {
      if (raw.trim().isEmpty) continue;
      try {
        final page = await _getPage(raw);
        if (!requireBody || page.body.trim().isNotEmpty) return page;
      } catch (e) {
        last = e;
      }
    }
    if (last != null) throw last;
    throw StateError('No working source URL');
  }

  String _pickImage(Element? root, {String? pageUrl}) {
    if (root == null) return '';
    final img = root.localName == 'img' ? root : root.querySelector('img');
    String? candidate;
    if (img != null) {
      for (final key in const [
        'data-src',
        'data-lazy-src',
        'data-original',
        'data-image',
        'data-poster',
        'src',
      ]) {
        final value = img.attributes[key]?.trim() ?? '';
        if (value.isNotEmpty && !value.startsWith('data:image')) {
          candidate = value;
          break;
        }
      }
      if ((candidate ?? '').isEmpty) {
        final srcset = img.attributes['srcset'] ?? img.attributes['data-srcset'] ?? '';
        if (srcset.isNotEmpty) {
          candidate = srcset.split(',').last.trim().split(RegExp(r'\s+')).first;
        }
      }
    }
    candidate ??= root.attributes['data-image'] ??
        root.attributes['data-src'] ??
        root.attributes['data-poster'];
    if ((candidate ?? '').isEmpty) {
      final styled = <Element>[root, ...root.querySelectorAll('[style]')];
      for (final el in styled) {
        final style = el.attributes['style'] ?? '';
        final match = RegExp(
          r'''url\(["']?([^"')]+)["']?\)''',
          caseSensitive: false,
        ).firstMatch(style);
        if (match != null) {
          candidate = match.group(1);
          break;
        }
      }
    }
    return _abs(candidate ?? '', pageUrl: pageUrl);
  }

  String _pickTitle(Element root, String href) {
    final img = root.querySelector('img');
    for (final raw in [
      img?.attributes['alt'],
      root.querySelector('a[href]')?.attributes['title'],
      root.querySelector('h1,h2,h3,h4,h5,.title,.Title,.caption,.name')?.text,
      root.attributes['title'],
      root.text,
    ]) {
      final value = (raw ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (value.length >= 2) return value;
    }
    try {
      return Uri.decodeComponent(Uri.parse(href).pathSegments.last)
          .replaceAll('-', ' ')
          .replaceAll('_', ' ')
          .trim();
    } catch (_) {
      return href;
    }
  }

  bool _looksSeries(String haystack) {
    final lower = haystack.toLowerCase();
    return lower.contains('/series/') ||
        lower.contains('series') ||
        lower.contains('مسلسل') ||
        lower.contains('/episode/') ||
        lower.contains('حلقة') ||
        lower.contains('season');
  }

  MediaItem? _cardFromElement(Element root, String pageUrl) {
    Element? anchor = root.localName == 'a' && root.attributes['href'] != null
        ? root
        : root.querySelector('a[href]');
    var parent = root.parent;
    var hops = 0;
    while (anchor == null && parent != null && hops < 3) {
      if (parent.localName == 'a' && parent.attributes['href'] != null) {
        anchor = parent;
        break;
      }
      anchor = parent.querySelector('a[href]');
      parent = parent.parent;
      hops++;
    }
    if (anchor == null) return null;
    final href = _abs(anchor.attributes['href'] ?? '', pageUrl: pageUrl);
    if (href.isEmpty) return null;
    final title = _pickTitle(root, href);
    if (title.isEmpty) return null;
    var poster = _pickImage(root, pageUrl: pageUrl);
    if (poster.isEmpty && anchor.parent != null) {
      poster = _pickImage(anchor.parent, pageUrl: pageUrl);
    }
    final classText = '${root.className} ${anchor.className} $href $title';
    return MediaItem(
      id: href,
      title: title,
      posterUrl: poster,
      backdropUrl: poster,
      isSeries: _looksSeries(classText),
      raw: {
        '_source': source.id,
        '_sourceUrl': href,
        '_sourceBase': _originOf(pageUrl),
      },
    );
  }

  String _akwamImage(Element root, String pageUrl) {
    final img = root.querySelector('.entry-image picture img') ??
        root.querySelector('picture img') ??
        root.querySelector('img');
    if (img == null) return _pickImage(root, pageUrl: pageUrl);
    for (final key in const <String>[
      'data-src',
      'data-lazy-src',
      'data-original',
      'data-image',
      'src',
    ]) {
      final value = (img.attributes[key] ?? '').trim();
      if (value.isNotEmpty && !value.startsWith('data:image')) {
        return _abs(value, pageUrl: pageUrl);
      }
    }
    final srcset = (img.attributes['data-srcset'] ?? img.attributes['srcset'] ?? '').trim();
    if (srcset.isNotEmpty) {
      final value = srcset.split(',').last.trim().split(RegExp(r'\s+')).first;
      return _abs(value, pageUrl: pageUrl);
    }
    return '';
  }

  List<MediaItem> _parseAkwamCards(
    String body,
    String pageUrl, {
    bool? forceSeries,
  }) {
    final doc = html_parser.parse(body);
    final out = <MediaItem>[];
    final seen = <String>{};

    final roots = <Element>[
      ...doc.querySelectorAll('.entry-image'),
      ...doc.querySelectorAll('div.widget'),
    ];

    for (final root in roots) {
      Element? anchor = root.querySelector(
        'a[href*="/movie/"], a[href*="/series/"], a[href*="/episode/"]',
      );
      anchor ??= root.querySelector('.box a[href], a.box[href], a[href]');
      if (anchor == null) continue;

      final href = _abs(anchor.attributes['href'] ?? '', pageUrl: pageUrl);
      if (href.isEmpty ||
          (!href.contains('/movie/') &&
              !href.contains('/series/') &&
              !href.contains('/episode/'))) {
        continue;
      }
      // Home/list pages may contain episode widgets as well. They must not be
      // mixed into the movie/series card rows.
      if (href.contains('/episode/') && forceSeries != null) continue;
      if (!seen.add(href)) continue;

      final picture = root.querySelector('picture img') ?? root.querySelector('img');
      String title = (picture?.attributes['alt'] ?? '').trim();
      if (title.isEmpty) title = (anchor.attributes['title'] ?? '').trim();
      if (title.isEmpty) {
        title = (root.querySelector('h1,h2,h3,h4,.title,.entry-title')?.text ?? anchor.text)
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
      }
      if (title.isEmpty) title = _pickTitle(root, href);
      if (title.isEmpty) continue;

      final poster = _akwamImage(root, pageUrl);
      final text = root.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final yearMatch = RegExp(r'\b(19\d{2}|20\d{2})\b').firstMatch(text);
      final ratingMatch = RegExp(r'\b(10(?:\.0)?|[0-9](?:\.[0-9])?)\b').firstMatch(text);
      final isSeries = forceSeries ?? href.contains('/series/');

      out.add(MediaItem(
        id: href,
        title: title,
        posterUrl: poster,
        backdropUrl: poster,
        year: int.tryParse(yearMatch?.group(1) ?? '') ?? 0,
        rating: double.tryParse(ratingMatch?.group(1) ?? '') ?? 0,
        isSeries: isSeries,
        raw: <String, dynamic>{
          '_source': 'akwam',
          '_sourceUrl': href,
          '_sourceBase': _originOf(pageUrl),
        },
      ));
    }

    // Bawa's Akwam parser also identifies series cards through widget links.
    if (forceSeries != false) {
      for (final a in doc.querySelectorAll("div.widget a[href*='/series/']")) {
        final href = _abs(a.attributes['href'] ?? '', pageUrl: pageUrl);
        if (href.isEmpty || !seen.add(href)) continue;
        Element root = a;
        var cursor = a.parent;
        for (var i = 0; i < 4 && cursor != null; i++) {
          root = cursor;
          if (cursor.classes.contains('entry-image')) break;
          cursor = cursor.parent;
        }
        var poster = _akwamImage(root, pageUrl);
        if (poster.isEmpty && a.parent?.parent != null) {
          poster = _akwamImage(a.parent!.parent!, pageUrl);
        }
        final title = _pickTitle(root, href);
        if (title.isEmpty) continue;
        out.add(MediaItem(
          id: href,
          title: title,
          posterUrl: poster,
          backdropUrl: poster,
          isSeries: true,
          raw: <String, dynamic>{
            '_source': 'akwam',
            '_sourceUrl': href,
            '_sourceBase': _originOf(pageUrl),
          },
        ));
      }
    }
    return out;
  }

  Future<List<MediaItem>> _akwamList(String kind, {int page = 1}) async {
    final key = '$kind:$page';
    final cached = _akwamListCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.createdAt) < const Duration(minutes: 5)) {
      return cached.items;
    }

    final path = '/$kind?page=$page';
    final fetched = await _firstWorkingPage(
      _baseCandidates.map((base) => '$base$path'),
    );
    final items = _parseAkwamCards(
      fetched.body,
      fetched.url,
      forceSeries: kind == 'series',
    );
    if (items.isNotEmpty) {
      _akwamListCache[key] = _AkwamCacheEntry(DateTime.now(), items);
    }
    return items;
  }

  List<MediaItem> _parseCards(String body, String pageUrl) {
    final doc = html_parser.parse(body);
    final out = <MediaItem>[];
    final seen = <String>{};

    final selectors = switch (source.id) {
      'wecima' => const [
          '.GridItem',
          '.Thumb--GridItem',
          '.Thumb--GridItem > a',
          'span.BG--GridItem',
        ],
      'akwam' => const [
          '.entry-image .box',
          '.entry-image',
          '.widget',
          'article',
        ],
      'alooytv' => const [
          'a[href*="/watch/"]',
          '.movie',
          '.item',
          '.thumbnail',
        ],
      'krmzi' => const [
          '.block-post',
          '.block-post a[href]',
          'article',
        ],
      'videoviola' => const [
          'div.block-series',
          'div.pm-video-thumb',
          '.caption',
        ],
      _ => const [
          '.GridItem',
          '.Thumb--GridItem',
          '.block-post',
          '.entry-image',
          '.post',
          '.item',
          'article',
          'div.caption',
          '.widget',
          '.movie',
          '.series',
          '.thumbnail',
        ],
    };

    void add(Element el) {
      final item = _cardFromElement(el, pageUrl);
      if (item == null || !seen.add(item.id)) return;
      out.add(item);
    }

    for (final selector in selectors) {
      for (final el in doc.querySelectorAll(selector)) {
        add(el);
      }
      if (out.length >= 80) break;
    }

    if (out.length < 8) {
      for (final a in doc.querySelectorAll('a[href]')) {
        final href = _abs(a.attributes['href'] ?? '', pageUrl: pageUrl);
        final text = '${a.text} $href'.toLowerCase();
        if (!(text.contains('movie') ||
            text.contains('film') ||
            text.contains('series') ||
            text.contains('episode') ||
            text.contains('فيلم') ||
            text.contains('مسلسل') ||
            text.contains('حلقة'))) {
          continue;
        }
        add(a.parent ?? a);
      }
    }
    return out.take(120).toList(growable: false);
  }

  Future<List<MediaItem>> home() async {
    if (source.id == 'cinejoy') {
      final movies = await _tmdbList(
        'https://api.themoviedb.org/3/trending/movie/day?api_key=$_tmdbKey&language=ar',
      );
      final tv = await _tmdbList(
        'https://api.themoviedb.org/3/trending/tv/day?api_key=$_tmdbKey&language=ar',
      );
      return <MediaItem>[...movies, ...tv];
    }

    if (source.id == 'akwam') {
      final all = <MediaItem>[];
      final seen = <String>{};
      for (final kind in const <String>['movies', 'series']) {
        try {
          for (final item in await _akwamList(kind)) {
            if (seen.add(item.id)) all.add(item);
          }
        } catch (_) {}
      }
      if (all.isNotEmpty) return all;
    }

    if (source.id == 'videoviola') {
      final all = <MediaItem>[];
      final seen = <String>{};
      for (final path in const [
        '/episodes.php?page=1',
        '/movies.php?page=1',
        '/all-series.php?page=1',
      ]) {
        try {
          final page = await _firstWorkingPage(
            _baseCandidates.map((b) => '$b$path'),
          );
          for (final item in _parseCards(page.body, page.url)) {
            if (seen.add(item.id)) all.add(item);
          }
        } catch (_) {}
      }
      if (all.isNotEmpty) return all;
    }

    if (source.id == 'krmzi') {
      try {
        final page = await _firstWorkingPage(
          _baseCandidates.map((b) => '$b/series-list/page/1/'),
        );
        final rows = _parseCards(page.body, page.url);
        if (rows.isNotEmpty) return rows;
      } catch (_) {}
    }

    if (source.id == 'alooytv') {
      final all = <MediaItem>[];
      final seen = <String>{};
      for (final path in const [
        '/',
        '/genre/ramadan-arabi-2026/',
        '/genre/foreign-movies.html',
      ]) {
        try {
          final page = await _firstWorkingPage(
            _baseCandidates.map((b) => '$b$path'),
          );
          for (final item in _parseCards(page.body, page.url)) {
            if (seen.add(item.id)) all.add(item);
          }
        } catch (_) {}
      }
      if (all.isNotEmpty) return all;
    }

    final page = await _firstWorkingPage(_baseCandidates);
    return _parseCards(page.body, page.url);
  }

  Future<Map<String, dynamic>> _providerDescriptor() async {
    if (_jsonProviderDescriptor != null) return _jsonProviderDescriptor!;
    final rawUrl = source.baseUrl.trim();
    if (rawUrl.isEmpty || !rawUrl.toLowerCase().endsWith('.json')) {
      _jsonProviderDescriptor = <String, dynamic>{};
      return _jsonProviderDescriptor!;
    }
    try {
      final decoded = jsonDecode((await _getPage(rawUrl)).body);
      if (decoded is Map) {
        _jsonProviderDescriptor = Map<String, dynamic>.from(decoded);
        return _jsonProviderDescriptor!;
      }
    } catch (_) {}
    _jsonProviderDescriptor = <String, dynamic>{};
    return _jsonProviderDescriptor!;
  }

  String _expandTemplate(String template, Map<String, String> values) {
    var result = template;
    values.forEach((key, value) {
      result = result.replaceAll('{$key}', Uri.encodeQueryComponent(value));
    });
    return result;
  }

  Future<String> _alooyEndpoint(
    String name, {
    Map<String, String> values = const <String, String>{},
  }) async {
    final descriptor = await _providerDescriptor();
    final endpoints = descriptor['endpoints'];
    if (endpoints is Map) {
      final raw = endpoints[name]?.toString().trim() ?? '';
      if (raw.isNotEmpty) return _expandTemplate(raw, values);
    }
    const root = 'https://scrptaty.com/pannel/cinematy_data/providers/alooytv.php';
    switch (name) {
      case 'search':
        return '$root?action=search&q=${Uri.encodeQueryComponent(values['query'] ?? '')}';
      case 'details':
        return '$root?action=details&id=${Uri.encodeQueryComponent(values['id'] ?? '')}';
      default:
        return '$root?action=home';
    }
  }

  MediaItem _alooyCard(Map<String, dynamic> map) {
    final id = (map['id'] ?? '').toString().trim();
    final title = (map['title'] ?? '').toString().trim();
    final image = (map['image'] ?? '').toString().trim();
    final count = int.tryParse((map['episodes_count'] ?? '0').toString()) ?? 0;
    final kind = (map['kind'] ?? '').toString().toLowerCase();
    final stableId = 'alooytv:$id:${Uri.encodeComponent(title)}';
    return MediaItem(
      id: stableId,
      title: title,
      posterUrl: image,
      backdropUrl: image,
      isSeries: kind.contains('series') || count > 1,
      raw: <String, dynamic>{
        ...map,
        '_source': 'alooytv',
        '_sourceUrl': id,
        '_alooySeriesId': id,
      },
    );
  }

  Future<List<MediaItem>> _alooyList(String url) async {
    final decoded = jsonDecode((await _getPage(url)).body);
    final rows = decoded is Map ? decoded['items'] : null;
    if (rows is! List) return const <MediaItem>[];
    return rows
        .whereType<Map>()
        .map((row) => _alooyCard(Map<String, dynamic>.from(row)))
        .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<MediaItem>> alooyHome() async {
    return _alooyList(await _alooyEndpoint('home'));
  }

  Future<List<MediaItem>> _alooySearch(String query) async {
    return _alooyList(await _alooyEndpoint(
      'search',
      values: <String, String>{'query': query},
    ));
  }

  String _alooyNumericId(String value) {
    final raw = value.trim();
    if (raw.startsWith('alooytv:')) {
      final parts = raw.split(':');
      if (parts.length >= 2 && RegExp(r'^\d+$').hasMatch(parts[1])) {
        return parts[1];
      }
    }
    return raw;
  }

  Future<ContentDetails> _alooyDetails(String id) async {
    final seriesId = _alooyNumericId(id);
    final decoded = jsonDecode((await _getPage(await _alooyEndpoint(
      'details',
      values: <String, String>{'id': seriesId},
    )))
        .body);
    if (decoded is! Map) throw StateError('AlooYTV details response is invalid');
    final map = Map<String, dynamic>.from(decoded);
    final image = (map['image'] ?? '').toString().trim();
    final episodeRows = map['episodes'] is List
        ? List<dynamic>.from(map['episodes'] as List)
        : const <dynamic>[];
    final episodeCount = int.tryParse((map['episodes_count'] ?? episodeRows.length).toString()) ?? episodeRows.length;
    final genres = map['genres'] is List
        ? (map['genres'] as List).map((e) => e.toString()).toList(growable: false)
        : const <String>[];
    final raw = <String, dynamic>{
      ...map,
      '_source': 'alooytv',
      '_sourceUrl': seriesId,
      '_alooySeriesId': seriesId,
      '_alooyEpisodes': episodeRows,
      '_alooyStreamUrl': (map['stream_url'] ?? '').toString(),
      'genres': genres,
    };
    return ContentDetails(
      media: MediaItem(
        id: seriesId,
        title: (map['title'] ?? '').toString(),
        description: (map['description'] ?? '').toString(),
        posterUrl: image,
        backdropUrl: image,
        year: int.tryParse(((map['release'] ?? '').toString().split('-').first)) ?? 0,
        rating: double.tryParse((map['rating'] ?? '0').toString()) ?? 0,
        isSeries: map['is_series'] == true || episodeCount > 1,
        raw: raw,
      ),
    );
  }

  List<SeasonGroup> alooySeasonGroupsFor(MediaItem media, dynamic embedded) =>
      _alooySeasonGroups(media, embedded);

  List<SeasonGroup> _alooySeasonGroups(
    MediaItem media,
    dynamic embedded,
  ) {
    if (embedded is! List || embedded.isEmpty) return const <SeasonGroup>[];
    final episodes = <Episode>[];
    for (final row in embedded.whereType<Map>()) {
      final map = Map<String, dynamic>.from(row);
      final number = int.tryParse((map['episode'] ?? '0').toString()) ?? 0;
      final stream = (map['stream_url'] ?? map['url'] ?? '').toString().trim();
      if (number <= 0 || stream.isEmpty) continue;
      episodes.add(Episode(
        id: stream,
        title: (map['title'] ?? 'الحلقة $number').toString(),
        seasonNumber: 1,
        episodeNumber: number,
        posterUrl: (map['image'] ?? media.posterUrl).toString(),
        description: '',
        raw: <String, dynamic>{
          ...map,
          '_source': 'alooytv',
          '_sourceUrl': stream,
          '_streamUrl': stream,
          '_seriesId': media.id,
          '_seriesTitle': media.title,
          '_seriesPoster': media.posterUrl,
          '_seriesBackdrop': media.backdropUrl,
        },
      ));
    }
    episodes.sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    return episodes.isEmpty ? const <SeasonGroup>[] : <SeasonGroup>[SeasonGroup(1, episodes)];
  }

  Future<List<MediaItem>> _tmdbList(String url) async {
    final raw = jsonDecode((await _getPage(url)).body);
    final rows = raw is Map ? raw['results'] : null;
    if (rows is! List) return const [];
    return rows.whereType<Map>().map((e) {
      final map = Map<String, dynamic>.from(e);
      final id = (map['id'] ?? '').toString();
      final type =
          (map['media_type'] ?? (map.containsKey('name') ? 'tv' : 'movie'))
              .toString();
      final posterPath = (map['poster_path'] ?? '').toString();
      final backPath = (map['backdrop_path'] ?? '').toString();
      return MediaItem(
        id: 'tmdb:$type:$id',
        title: (map['title'] ??
                map['name'] ??
                map['original_title'] ??
                map['original_name'] ??
                '')
            .toString(),
        description: (map['overview'] ?? '').toString(),
        posterUrl: posterPath.isEmpty
            ? ''
            : 'https://image.tmdb.org/t/p/w500$posterPath',
        backdropUrl: backPath.isEmpty
            ? ''
            : 'https://image.tmdb.org/t/p/w1280$backPath',
        year: int.tryParse(
              ((map['release_date'] ?? map['first_air_date'] ?? '')
                  .toString()
                  .split('-')
                  .first),
            ) ??
            0,
        rating: map['vote_average'] is num
            ? (map['vote_average'] as num).toDouble()
            : 0,
        isSeries: type == 'tv',
        raw: {...map, '_source': 'cinejoy', '_tmdbType': type},
      );
    }).where((e) => e.id != 'tmdb::' && e.title.isNotEmpty).toList();
  }

  Future<List<MediaItem>> search(String query, {int page = 1}) async {
    if (source.id == 'alooytv') return _alooySearch(query);
    final q = Uri.encodeQueryComponent(query);
    if (source.id == 'cinejoy') {
      return _tmdbList(
        'https://api.themoviedb.org/3/search/multi?api_key=$_tmdbKey&language=ar&query=$q&page=$page',
      );
    }

    final paths = <String>[];
    if (source.searchTemplate.isNotEmpty) {
      paths.add(source.searchTemplate
          .replaceAll('{query}', q)
          .replaceAll('{page}', '$page'));
    }
    switch (source.id) {
      case 'akwam':
        paths.addAll(<String>[
          '/search/$q',
          '/search?q=$q',
          '/?s=$q',
        ]);
        break;
      case 'videoviola':
        paths.add('/search.php?keywords=$q');
        break;
      case 'wecima':
        paths.addAll(['/search/$q/', '/?s=$q']);
        break;
      case 'krmzi':
        paths.addAll(['/search/$q/', '/?s=$q']);
        break;
      default:
        paths.addAll(['/?s=$q', '/search/$q', '/search?q=$q']);
    }

    Object? last;
    for (final base in _baseCandidates) {
      for (final path in paths) {
        try {
          final url = path.startsWith('http') ? path : '$base$path';
          final resultPage = await _getPage(url);
          final list = source.id == 'akwam'
              ? _parseAkwamCards(resultPage.body, resultPage.url)
              : _parseCards(resultPage.body, resultPage.url);
          if (list.isNotEmpty) return list;
        } catch (e) {
          last = e;
        }
      }
    }
    if (last != null) throw last;
    return const [];
  }

  Future<ContentDetails> _akwamDetails(String id) async {
    final requested = _abs(id, pageUrl: source.baseUrl);
    if (requested.isEmpty) {
      throw StateError('Akwam details URL is empty');
    }

    // Bawa loads the series/movie page itself first. The episode links are
    // embedded in that HTML; it does not discover them from the list endpoint.
    final page = await _getPage(requested, referer: source.baseUrl);
    final doc = html_parser.parse(page.body);

    final title = (doc.querySelector('h1')?.text ??
            doc.querySelector('meta[property="og:title"]')?.attributes['content'] ??
            'تفاصيل')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    var poster = '';
    final entryImage = doc.querySelector('.entry-image');
    if (entryImage != null) poster = _akwamImage(entryImage, page.url);
    if (poster.isEmpty) {
      final og = doc.querySelector('meta[property="og:image"]')?.attributes['content'] ?? '';
      if (og.trim().isNotEmpty) poster = _abs(og, pageUrl: page.url);
    }
    if (poster.isEmpty) poster = _pickImage(doc.body, pageUrl: page.url);

    String description = '';
    for (final selector in const <String>[
      'meta[name=description]',
      '.story',
      '.Story',
      '.description',
      '.content p',
    ]) {
      final el = doc.querySelector(selector);
      final value = (selector.startsWith('meta')
              ? el?.attributes['content']
              : el?.text)
          ?.replaceAll(RegExp(r'\s+'), ' ')
          .trim() ??
          '';
      if (value.isNotEmpty) {
        description = value;
        break;
      }
    }

    // Exact selector found inside Bawa/AkwamAPI.swift.
    final exactEpisodeAnchors = doc.querySelectorAll("h2 a[href*='/episode/']");
    final isSeries = page.url.contains('/series/') || exactEpisodeAnchors.isNotEmpty;
    final seasonNo = _seasonNumber('$title ${page.url}', fallback: 1);
    final episodes = isSeries
        ? _extractAkwamEpisodes(doc, page.body, page.url, poster, seasonNo)
        : const <Episode>[];

    final raw = <String, dynamic>{
      '_source': 'akwam',
      '_sourceUrl': page.url,
      '_sourceBase': _originOf(page.url),
      '_html': page.body,
      '_akwamSeason': seasonNo,
      '_akwamEpisodeCount': episodes.length,
      '_akwamEpisodes': episodes
          .map((episode) => <String, dynamic>{
                'id': episode.id,
                'title': episode.title,
                'seasonNumber': episode.seasonNumber,
                'episodeNumber': episode.episodeNumber,
                'posterUrl': episode.posterUrl,
                'description': episode.description,
                '_source': 'akwam',
                '_sourceUrl': episode.id,
                '_seriesPoster': poster,
              })
          .toList(growable: false),
    };

    return ContentDetails(
      media: MediaItem(
        id: page.url,
        title: title,
        description: description,
        posterUrl: poster,
        backdropUrl: poster,
        isSeries: isSeries,
        raw: raw,
      ),
    );
  }

  Future<ContentDetails> details(String id) async {
    if (source.id == 'alooytv') return _alooyDetails(id);
    if (source.id == 'akwam') {
      return _akwamDetails(id);
    }
    if (source.id == 'cinejoy' && id.startsWith('tmdb:')) {
      final parts = id.split(':');
      final type = parts.length > 1 ? parts[1] : 'movie';
      final tmdbId = parts.length > 2 ? parts[2] : '';
      final raw = jsonDecode((await _getPage(
        'https://api.themoviedb.org/3/$type/$tmdbId?api_key=$_tmdbKey&language=ar',
      ))
          .body);
      if (raw is Map) {
        final map = Map<String, dynamic>.from(raw);
        final posterPath = (map['poster_path'] ?? '').toString();
        final backPath = (map['backdrop_path'] ?? '').toString();
        return ContentDetails(
          media: MediaItem(
            id: id,
            title: (map['title'] ?? map['name'] ?? '').toString(),
            description: (map['overview'] ?? '').toString(),
            posterUrl: posterPath.isEmpty
                ? ''
                : 'https://image.tmdb.org/t/p/w500$posterPath',
            backdropUrl: backPath.isEmpty
                ? ''
                : 'https://image.tmdb.org/t/p/w1280$backPath',
            year: int.tryParse(
                  ((map['release_date'] ?? map['first_air_date'] ?? '')
                      .toString()
                      .split('-')
                      .first),
                ) ??
                0,
            rating: map['vote_average'] is num
                ? (map['vote_average'] as num).toDouble()
                : 0,
            isSeries: type == 'tv',
            raw: {...map, '_source': 'cinejoy', '_tmdbType': type},
          ),
        );
      }
    }

    final page = await _getPage(id);
    final doc = html_parser.parse(page.body);
    final title = (doc.querySelector('h1')?.text ??
            doc.querySelector('meta[property="og:title"]')?.attributes['content'] ??
            'تفاصيل')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final poster = source.id == 'akwam'
        ? (() {
            final meta = doc.querySelector('meta[property="og:image"]')?.attributes['content'] ?? '';
            if (meta.trim().isNotEmpty) return _abs(meta, pageUrl: page.url);
            final entry = doc.querySelector('.entry-image');
            if (entry != null) {
              final image = _akwamImage(entry, page.url);
              if (image.isNotEmpty) return image;
            }
            return _pickImage(doc.body, pageUrl: page.url);
          })()
        : _abs(
            doc.querySelector('meta[property="og:image"]')?.attributes['content'] ??
                _pickImage(doc.body, pageUrl: page.url),
            pageUrl: page.url,
          );
    final backdrop = _abs(
      doc.querySelector('meta[property="og:image"]')?.attributes['content'] ??
          poster,
      pageUrl: page.url,
    );
    final descriptionSelectors = switch (source.id) {
      'videoviola' => const [
          'div.pm-series-description div[itemprop=description]',
          'div.pm-video-description div[itemprop=description]',
          'div.description div[itemprop=description]',
          'div[itemprop=description]',
        ],
      'wecima' => const ['meta[itemprop=description]', '.StoryMovieContent', '.story'],
      _ => const ['meta[name=description]', '.story', '.Story', '.description', '.content p'],
    };
    String description = '';
    for (final selector in descriptionSelectors) {
      final el = doc.querySelector(selector);
      final raw = selector.startsWith('meta')
          ? el?.attributes['content']
          : el?.text;
      final value = (raw ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (value.isNotEmpty) {
        description = value;
        break;
      }
    }
    final isSeries = _looksSeries('${page.url} $title') ||
        doc.querySelector('.EpisodesList a[href], a[href*="/episode/"], .episodes a[href], div.SeasonsEpisodesMain') != null;

    final raw = <String, dynamic>{
      '_source': source.id,
      '_sourceUrl': page.url,
      '_sourceBase': _originOf(page.url),
      '_html': page.body,
    };

    // Akwam exposes every episode directly in the series details HTML. Parse
    // the list exactly once here and carry it with ContentDetails so the UI
    // never depends on a second request or on reparsing a later response.
    if (source.id == 'akwam' && isSeries) {
      final seasonNo = _seasonNumber('$title ${page.url}', fallback: 1);
      final episodes = _extractAkwamEpisodes(
        doc,
        page.body,
        page.url,
        poster,
        seasonNo,
      );
      raw['_akwamSeason'] = seasonNo;
      raw['_akwamEpisodeCount'] = episodes.length;
      raw['_akwamEpisodes'] = episodes
          .map((episode) => <String, dynamic>{
                'id': episode.id,
                'title': episode.title,
                'seasonNumber': episode.seasonNumber,
                'episodeNumber': episode.episodeNumber,
                'posterUrl': episode.posterUrl,
                'description': episode.description,
                '_source': 'akwam',
                '_sourceUrl': episode.id,
                '_seriesPoster': poster,
              })
          .toList(growable: false);
    }

    return ContentDetails(
      media: MediaItem(
        id: page.url,
        title: title,
        description: description,
        posterUrl: poster,
        backdropUrl: backdrop,
        isSeries: isSeries,
        raw: raw,
      ),
    );
  }

  String _safePercentDecode(String text) {
    if (text.isEmpty || !text.contains('%')) return text;
    try {
      return Uri.decodeFull(text);
    } catch (_) {
      // Akwam occasionally returns Arabic URLs/text containing a raw '%' that
      // is not followed by two hex digits. Decode only valid %XX sequences and
      // leave every other percent sign untouched instead of throwing.
      return text.replaceAllMapped(RegExp(r'%(?:[0-9A-Fa-f]{2})+'), (match) {
        try {
          return Uri.decodeFull(match.group(0)!);
        } catch (_) {
          return match.group(0)!;
        }
      });
    }
  }

  String _rawLastPathPart(String value) {
    var clean = value.split('#').first.split('?').first;
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    final slash = clean.lastIndexOf('/');
    final tail = slash >= 0 ? clean.substring(slash + 1) : clean;
    return _safePercentDecode(tail);
  }

  int _episodeNumber(String text, {int fallback = 0}) {
    final normalized = _safePercentDecode(text)
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Akwam commonly uses "حلقة 3" in visible titles. Prefer visible/slug
    // episode markers and never treat the numeric content id directly after
    // /episode/ as the episode number (e.g. /episode/102907/.../الحلقة-3).
    final patterns = <RegExp>[
      RegExp(r'(?:الحلقة|حلقة|episode|ep\.?|\be\b)\s*[:#-]?\s*(\d+)', caseSensitive: false),
      RegExp(r'(?:الحلقة|حلقة|episode|ep)[-_/ ]+(\d+)', caseSensitive: false),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(normalized);
      final value = int.tryParse(m?.group(1) ?? '');
      if (value != null && value > 0) return value;
    }
    return fallback;
  }

  int _arabicOrdinalNumber(String text) {
    final normalized = text.replaceAll('ـ', '').trim();
    const values = <String, int>{
      'الاول': 1,
      'الأول': 1,
      'الثاني': 2,
      'الثانى': 2,
      'الثالث': 3,
      'الرابع': 4,
      'الخامس': 5,
      'السادس': 6,
      'السابع': 7,
      'الثامن': 8,
      'التاسع': 9,
      'العاشر': 10,
      'الحادي عشر': 11,
      'الحادى عشر': 11,
      'الثاني عشر': 12,
      'الثانى عشر': 12,
      'الثالث عشر': 13,
      'الرابع عشر': 14,
      'الخامس عشر': 15,
      'السادس عشر': 16,
      'السابع عشر': 17,
      'الثامن عشر': 18,
      'التاسع عشر': 19,
      'العشرون': 20,
    };
    for (final entry in values.entries) {
      if (normalized.contains(entry.key)) return entry.value;
    }
    return 0;
  }

  int _seasonNumber(String text, {int fallback = 1}) {
    final decoded = _safePercentDecode(text).replaceAll('-', ' ').replaceAll('_', ' ');
    final m = RegExp(
      r'(?:الموسم|season)\s*[:#-]?\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(decoded);
    final numeric = int.tryParse(m?.group(1) ?? '');
    if (numeric != null && numeric > 0) return numeric;

    final seasonWord = RegExp(
      r'(?:الموسم|season)\s+([^:/|]+)',
      caseSensitive: false,
    ).firstMatch(decoded)?.group(1) ?? '';
    final ordinal = _arabicOrdinalNumber(seasonWord);
    return ordinal > 0 ? ordinal : fallback;
  }

  Episode? _episodeFromAnchor(
    Element a,
    String pageUrl, {
    required int fallbackNumber,
    required int fallbackSeason,
    required String fallbackPoster,
  }) {
    final href = _abs(a.attributes['href'] ?? '', pageUrl: pageUrl);
    if (href.isEmpty) return null;
    final text = a.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final combined = '$text $href';
    final episodeNumber = _episodeNumber(combined, fallback: fallbackNumber);
    if (episodeNumber <= 0) return null;
    final seasonNumber = _seasonNumber(combined, fallback: fallbackSeason);
    var poster = _pickImage(a, pageUrl: pageUrl);
    if (poster.isEmpty && a.parent != null) {
      poster = _pickImage(a.parent, pageUrl: pageUrl);
    }
    if (poster.isEmpty) poster = fallbackPoster;
    return Episode(
      id: href,
      title: text.isEmpty ? 'الحلقة $episodeNumber' : text,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      posterUrl: poster,
      raw: {
        '_source': source.id,
        '_sourceUrl': href,
        '_seriesPoster': fallbackPoster,
      },
    );
  }

  List<Episode> _parseAkwamEpisodesFromRawHtml(
    String body,
    String pageUrl,
    String fallbackPoster,
    int seasonNumber,
  ) {
    final episodesByUrl = <String, Episode>{};

    final anchorExp = RegExp(
      r'''<a\b[^>]*href\s*=\s*["']([^"']*/episode/[^"']*)["'][^>]*>([\s\S]*?)</a>''',
      caseSensitive: false,
      multiLine: true,
    );

    for (final match in anchorExp.allMatches(body)) {
      final href = _abs(match.group(1) ?? '', pageUrl: pageUrl);
      if (href.isEmpty) continue;

      final fragment = html_parser.parseFragment(match.group(2) ?? '');
      var title = (fragment.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (title.isEmpty) {
        final tail = _rawLastPathPart(href);
        title = tail.replaceAll('-', ' ').trim();
      }

      var episodeNo = _episodeNumber(title);
      if (episodeNo <= 0) {
        final tail = _rawLastPathPart(href);
        episodeNo = _episodeNumber(tail);
      }
      if (episodeNo <= 0) continue;

      episodesByUrl[href] = Episode(
        id: href,
        title: title.isEmpty ? 'الحلقة $episodeNo' : title,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNo,
        posterUrl: fallbackPoster,
        raw: <String, dynamic>{
          '_source': 'akwam',
          '_sourceUrl': href,
          '_seriesPoster': fallbackPoster,
        },
      );
    }

    final episodes = episodesByUrl.values.toList()
      ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    return episodes;
  }

  List<Episode> _extractAkwamEpisodes(
    Document doc,
    String body,
    String pageUrl,
    String fallbackPoster,
    int seasonNumber,
  ) {
    final byEpisode = <String, Episode>{};

    void addFromAnchor(Element a) {
      final href = _abs(a.attributes['href'] ?? '', pageUrl: pageUrl);
      if (href.isEmpty || !href.contains('/episode/')) return;

      var title = a.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      var episodeNo = _episodeNumber(title);
      if (episodeNo <= 0) {
        final tail = _rawLastPathPart(href);
        episodeNo = _episodeNumber(tail);
        if (title.isEmpty) title = tail.replaceAll('-', ' ').trim();
      }
      if (episodeNo <= 0) return;

      var poster = _pickImage(a.parent, pageUrl: pageUrl);
      if (poster.isEmpty && a.parent?.parent != null) {
        poster = _pickImage(a.parent!.parent, pageUrl: pageUrl);
      }
      if (poster.isEmpty) poster = fallbackPoster;

      final key = '$seasonNumber:$episodeNo';
      byEpisode.putIfAbsent(
        key,
        () => Episode(
          id: href,
          title: title.isEmpty ? 'الحلقة $episodeNo' : title,
          seasonNumber: seasonNumber,
          episodeNumber: episodeNo,
          posterUrl: poster,
          raw: <String, dynamic>{
            '_source': 'akwam',
            '_sourceUrl': href,
            '_seriesPoster': fallbackPoster,
          },
        ),
      );
    }

    // This is the exact selector embedded in Bawa's AkwamAPI.
    for (final a in doc.querySelectorAll("h2 a[href*='/episode/']")) {
      addFromAnchor(a);
    }

    // Akwam can change the surrounding heading tag while keeping /episode/.
    // Use all episode anchors as a structural fallback, but still derive the
    // episode number only from the visible title or final slug, never the ID.
    if (byEpisode.isEmpty) {
      for (final a in doc.querySelectorAll("a[href*='/episode/']")) {
        addFromAnchor(a);
      }
    }

    // Raw-HTML fallback for malformed/partial DOM responses.
    if (byEpisode.isEmpty) {
      for (final episode in _parseAkwamEpisodesFromRawHtml(
        body,
        pageUrl,
        fallbackPoster,
        seasonNumber,
      )) {
        byEpisode.putIfAbsent(
          '${episode.seasonNumber}:${episode.episodeNumber}',
          () => episode,
        );
      }
    }

    final episodes = byEpisode.values.toList()
      ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    return episodes;
  }

  Future<List<SeasonGroup>> seasons(
    String id, {
    String htmlBody = '',
    String pageUrlOverride = '',
  }) async {
    if (source.id == 'alooytv') {
      final details = await _alooyDetails(id);
      return _alooySeasonGroups(details.media, details.media.raw['_alooyEpisodes']);
    }
    if (source.id == 'cinejoy' && id.startsWith('tmdb:tv:')) {
      final tmdbId = id.split(':')[2];
      final detail = jsonDecode((await _getPage(
        'https://api.themoviedb.org/3/tv/$tmdbId?api_key=$_tmdbKey&language=ar',
      ))
          .body);
      final seasonRows = detail is Map ? detail['seasons'] : null;
      if (seasonRows is List) {
        final groups = <SeasonGroup>[];
        for (final row in seasonRows.whereType<Map>()) {
          final sn = int.tryParse((row['season_number'] ?? '').toString()) ?? 0;
          if (sn <= 0) continue;
          final season = jsonDecode((await _getPage(
            'https://api.themoviedb.org/3/tv/$tmdbId/season/$sn?api_key=$_tmdbKey&language=ar',
          ))
              .body);
          final epRows = season is Map ? season['episodes'] : null;
          if (epRows is! List) continue;
          final seasonPosterPath = (row['poster_path'] ?? '').toString();
          final episodes = epRows.whereType<Map>().map((e) {
            final en = int.tryParse((e['episode_number'] ?? '').toString()) ?? 0;
            final still = (e['still_path'] ?? '').toString();
            final imagePath = still.isNotEmpty ? still : seasonPosterPath;
            return Episode(
              id: 'tmdb:tv:$tmdbId:$sn:$en',
              title: (e['name'] ?? 'الحلقة $en').toString(),
              seasonNumber: sn,
              episodeNumber: en,
              posterUrl: imagePath.isEmpty
                  ? ''
                  : 'https://image.tmdb.org/t/p/w500$imagePath',
              description: (e['overview'] ?? '').toString(),
              raw: {...Map<String, dynamic>.from(e), '_source': 'cinejoy'},
            );
          }).toList();
          groups.add(SeasonGroup(sn, episodes));
        }
        return groups;
      }
    }

    final _FetchedPage page;
    if (htmlBody.trim().isNotEmpty) {
      page = _FetchedPage(
        pageUrlOverride.trim().isNotEmpty ? pageUrlOverride : id,
        htmlBody,
      );
    } else {
      page = await _getPage(id);
    }
    final doc = html_parser.parse(page.body);
    final seriesPoster = source.id == 'akwam'
        ? (() {
            final meta = doc.querySelector('meta[property="og:image"]')?.attributes['content'] ?? '';
            if (meta.trim().isNotEmpty) return _abs(meta, pageUrl: page.url);
            final entry = doc.querySelector('.entry-image');
            if (entry != null) {
              final image = _akwamImage(entry, page.url);
              if (image.isNotEmpty) return image;
            }
            return _pickImage(doc.body, pageUrl: page.url);
          })()
        : _abs(
            doc.querySelector('meta[property="og:image"]')?.attributes['content'] ??
                _pickImage(doc.body, pageUrl: page.url),
            pageUrl: page.url,
          );

    final grouped = <int, List<Episode>>{};
    final seen = <String>{};
    var fallback = 1;
    final pageTitle = (doc.querySelector('h1')?.text ??
            doc.querySelector('meta[property="og:title"]')?.attributes['content'] ??
            '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final akwamPageSeason = source.id == 'akwam'
        ? _seasonNumber('$pageTitle ${page.url}', fallback: 1)
        : 1;

    void addAnchor(Element a, {int forcedSeason = 0, int? forcedEpisode}) {
      final href = _abs(a.attributes['href'] ?? '', pageUrl: page.url);
      if (href.isEmpty) return;

      final titleText = a.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      // For Akwam, calculate the episode from the visible title first and from
      // the final URL slug second. This prevents the content id after
      // /episode/ from being mistaken for the episode number.
      int episodeNo = forcedEpisode ?? 0;
      if (source.id == 'akwam' && episodeNo <= 0) {
        episodeNo = _episodeNumber(titleText);
        if (episodeNo <= 0) {
          final uri = Uri.tryParse(href);
          final tail = uri == null || uri.pathSegments.isEmpty
              ? href
              : uri.pathSegments.last;
          episodeNo = _episodeNumber(tail);
        }
        if (episodeNo <= 0) episodeNo = fallback;
      }

      final ep = _episodeFromAnchor(
        a,
        page.url,
        fallbackNumber: episodeNo > 0 ? episodeNo : fallback,
        fallbackSeason: forcedSeason > 0
            ? forcedSeason
            : source.id == 'akwam'
                ? akwamPageSeason
                : 1,
        fallbackPoster: seriesPoster,
      );
      if (ep == null || !seen.add(ep.id)) return;
      fallback = ep.episodeNumber + 1;
      grouped.putIfAbsent(ep.seasonNumber, () => <Episode>[]).add(ep);
    }

    if (source.id == 'akwam') {
      final episodes = _extractAkwamEpisodes(
        doc,
        page.body,
        page.url,
        seriesPoster,
        akwamPageSeason,
      );
      if (episodes.isNotEmpty) {
        return <SeasonGroup>[SeasonGroup(akwamPageSeason, episodes)];
      }
    }

    if (source.id == 'videoviola') {
      final seasonButtons = doc.querySelectorAll(
        'div.SeasonsBoxUL.seasons-serie button.tablinks',
      );
      final tabs = doc.querySelectorAll(
        'div.SeasonsEpisodesMain div.tabcontent',
      );
      for (var i = 0; i < tabs.length; i++) {
        final raw = i < seasonButtons.length ? seasonButtons[i].text : tabs[i].id;
        final seasonNo = _seasonNumber(raw, fallback: i + 1);
        for (final a in tabs[i].querySelectorAll('a[href]')) {
          addAnchor(a, forcedSeason: seasonNo);
        }
      }
    }

    final selectors = switch (source.id) {
      'wecima' => const ['.EpisodesList a[href]', 'a[href*="/episode/"]'],
      'akwam' => const ['h2 a[href*="/episode/"]', 'a[href*="/episode/"]'],
      'krmzi' => const ['.block-post a[href]', 'a[href*="/episode/"]'],
      'alooytv' => const [
          'a[href*="/watch/"]',
          '.episodes a[href]',
          '.episode a[href]',
        ],
      _ => const [
          'a[href*="episode"]',
          '.episodes a[href]',
          '.Episodes a[href]',
          '.episode a[href]',
        ],
    };

    for (final selector in selectors) {
      for (final a in doc.querySelectorAll(selector)) {
        final combined = '${a.text} ${a.attributes['href'] ?? ''}';
        if (_episodeNumber(combined) <= 0 && source.id != 'alooytv') continue;
        addAnchor(a);
      }
    }

    // AlooYTV and some mirrors render episode choices as buttons instead of
    // normal links. Recover their target URL from data-* or onclick.
    for (final button in doc.querySelectorAll('button, [data-href], [data-url]')) {
      final onclick = button.attributes['onclick'] ?? '';
      final match = RegExp(
        r'''https?://[^"'\s)]+|/[A-Za-z0-9_%?&=./-]+''',
        caseSensitive: false,
      ).firstMatch(onclick);
      final rawUrl = button.attributes['data-href'] ??
          button.attributes['data-url'] ??
          match?.group(0) ??
          '';
      if (rawUrl.isEmpty) continue;
      final text = '${button.text} $rawUrl';
      if (_episodeNumber(text) <= 0) continue;
      final a = Element.tag('a')
        ..attributes['href'] = rawUrl
        ..text = button.text;
      addAnchor(a);
    }

    final groups = grouped.entries.map((entry) {
      final episodes = entry.value
        ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
      return SeasonGroup(entry.key, episodes);
    }).toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    return groups;
  }

  void _collectDirectMedia(String body, Set<String> urls, String pageUrl) {
    final normalized = body
        .replaceAll(r'\/', '/')
        .replaceAll('&amp;', '&')
        .replaceAll(r'\u0026', '&');
    final patterns = <RegExp>[
      RegExp(r'''https?://[^"'\s<>]+?\.m3u8(?:\?[^"'\s<>]*)?''', caseSensitive: false),
      RegExp(r'''https?://[^"'\s<>]+?\.mp4(?:\?[^"'\s<>]*)?''', caseSensitive: false),
      RegExp(r'''(?:file|src|videoUrl|source)\s*[:=]\s*["']([^"']+\.(?:m3u8|mp4)[^"']*)["']''', caseSensitive: false),
      RegExp(r'''"(?:hls_ondemand|hls_fmp4|hls)"\s*:\s*"([^"]+)"''', caseSensitive: false),
      RegExp(r'''"url\d+"\s*:\s*"([^"]+)"''', caseSensitive: false),
    ];
    for (final re in patterns) {
      for (final m in re.allMatches(normalized)) {
        final raw = m.groupCount >= 1 && (m.group(1) ?? '').isNotEmpty
            ? m.group(1)!
            : m.group(0)!;
        final url = _abs(raw, pageUrl: pageUrl);
        if (url.startsWith('http')) urls.add(url);
      }
    }
  }

  String? _tryDecodeUrl(String raw, String pageUrl) {
    final decodedUri = _safePercentDecode(raw).replaceAll(r'\/', '/');
    final direct = RegExp(r'''https?://[^\s"'<>]+''', caseSensitive: false)
        .firstMatch(decodedUri)
        ?.group(0);
    if (direct != null) return direct;

    final uri = Uri.tryParse(raw);
    final candidates = <String>[
      if (uri != null) ...uri.queryParameters.values,
      raw,
    ];
    for (var value in candidates) {
      value = _safePercentDecode(value).trim();
      while (value.length % 4 != 0) {
        value += '=';
      }
      try {
        final decoded = utf8.decode(base64Decode(value));
        final match = RegExp(r'''https?://[^\s"'<>]+''', caseSensitive: false)
            .firstMatch(decoded)
            ?.group(0);
        if (match != null) return _abs(match, pageUrl: pageUrl);
      } catch (_) {}
    }
    return null;
  }

  List<String> _serverUrls(Document doc, String pageUrl) {
    final urls = <String>{};
    void add(String? raw) {
      if (raw == null || raw.trim().isEmpty) return;
      var value = raw.trim();
      final decoded = _tryDecodeUrl(value, pageUrl);
      if (decoded != null) value = decoded;
      final u = _abs(value, pageUrl: pageUrl);
      if (!u.startsWith('http')) return;
      urls.add(u);
    }

    final selectors = <String>[
      'video source',
      'video',
      'source',
      'iframe',
      'ul#watch li[data-watch]',
      '.serversList li[data-server]',
      'li[data-embed]',
      'a[href*="download_video"]',
      '.Download--Wecima--Single a',
      'a.download--btn',
      '.download--servers a',
      'a[href*="secure_stream"]',
      'a[href*="link.mycima"]',
      'a[href]',
    ];
    for (final selector in selectors) {
      for (final el in doc.querySelectorAll(selector)) {
        add(el.attributes['src']);
        add(el.attributes['data-src']);
        add(el.attributes['href']);
        add(el.attributes['data-watch']);
        add(el.attributes['data-server']);
        add(el.attributes['data-embed']);
      }
    }
    return urls.toList(growable: false);
  }

  Future<List<VideoSource>> _akwamVideoSources(String id) async {
    final direct = <String>{};
    final visited = <String>{};
    final watchQueue = <_FetchTarget>[];

    Future<void> inspect(String url, {String? referer, int depth = 0}) async {
      if (url.isEmpty || !visited.add(url)) return;
      final page = await _getPage(url, referer: referer);
      _collectDirectMedia(page.body, direct, page.url);
      final doc = html_parser.parse(page.body);

      // This is the exact Akwam watch selector used by Bawa. On a movie or
      // episode page it points to the actual /watch/... quality pages.
      for (final a in doc.querySelectorAll(
        'a.link-btn.link-show[href], a[href*="/watch/"]',
      )) {
        final next = _abs(a.attributes['href'] ?? '', pageUrl: page.url);
        if (next.isEmpty) continue;
        if (next.contains('.m3u8') || next.contains('.mp4')) {
          direct.add(next);
        } else if (depth < 2 && !visited.contains(next)) {
          watchQueue.add(_FetchTarget(next, page.url, depth + 1));
        }
      }

      // Akwam can also emit the playable URL as a source/video element.
      for (final el in doc.querySelectorAll('video, video source, source')) {
        for (final key in const <String>['src', 'data-src']) {
          final value = _abs(el.attributes[key] ?? '', pageUrl: page.url);
          if (value.contains('.m3u8') || value.contains('.mp4')) direct.add(value);
        }
      }
    }

    try {
      await inspect(id);
    } catch (_) {}

    while (watchQueue.isNotEmpty && visited.length < 12) {
      final target = watchQueue.removeAt(0);
      try {
        await inspect(
          target.url,
          referer: target.referer,
          depth: target.depth,
        );
      } catch (_) {}
    }

    final urls = direct.where((url) {
      final lower = url.toLowerCase();
      return lower.startsWith('http') &&
          (lower.contains('.m3u8') || lower.contains('.mp4'));
    }).toList();

    int qualityScore(String url) {
      final lower = url.toLowerCase();
      if (lower.contains('2160')) return 2160;
      if (lower.contains('1440')) return 1440;
      if (lower.contains('1080')) return 1080;
      if (lower.contains('720')) return 720;
      if (lower.contains('480')) return 480;
      if (lower.contains('360')) return 360;
      return 0;
    }

    urls.sort((a, b) => qualityScore(b).compareTo(qualityScore(a)));
    return urls.map((url) {
      final q = qualityScore(url);
      return VideoSource(
        url: url,
        quality: q > 0 ? '${q}p' : (url.toLowerCase().contains('.m3u8') ? 'HLS' : 'المصدر'),
      );
    }).toList(growable: false);
  }

  Future<List<VideoSource>> videoSources(String id) async {
    if (source.id == 'cinejoy' && id.startsWith('tmdb:')) {
      final p = id.split(':');
      if (p.length >= 3) {
        final type = p[1] == 'tv' ? 'tv' : 'movie';
        final tmdbId = p[2];
        final extra = p.length >= 5 ? '&season=${p[3]}&episode=${p[4]}' : '';
        try {
          final raw = jsonDecode((await _getPage(
            'https://data.vidsrcme.ru/api.php?type=$type&id=$tmdbId$extra',
          ))
              .body);
          final data = raw is Map ? raw['data'] : null;
          final streams = data is Map ? data['stream_urls'] : null;
          if (streams is List) {
            return streams
                .map((e) => VideoSource(url: e.toString(), quality: 'المصدر'))
                .where((e) => e.url.startsWith('http'))
                .toList();
          }
        } catch (_) {}
      }
      return const [];
    }

    if (source.id == 'alooytv') {
      final direct = id.trim();
      final lower = direct.toLowerCase();
      if (direct.startsWith('http') && (lower.contains('.mp4') || lower.contains('.m3u8'))) {
        return <VideoSource>[
          VideoSource(
            url: direct,
            quality: lower.contains('.m3u8') ? 'HLS' : 'MP4',
          ),
        ];
      }
      try {
        final details = await _alooyDetails(direct);
        final stream = (details.media.raw['_alooyStreamUrl'] ?? '').toString().trim();
        if (stream.isNotEmpty) {
          return <VideoSource>[VideoSource(url: stream, quality: 'MP4')];
        }
        final groups = _alooySeasonGroups(details.media, details.media.raw['_alooyEpisodes']);
        if (groups.length == 1 && groups.first.episodes.length == 1) {
          return <VideoSource>[VideoSource(url: groups.first.episodes.first.id, quality: 'MP4')];
        }
      } catch (_) {}
      return const <VideoSource>[];
    }

    if (source.id == 'akwam') {
      return _akwamVideoSources(id);
    }

    final direct = <String>{};
    final queue = <_FetchTarget>[_FetchTarget(id, null, 0)];
    final visited = <String>{};

    while (queue.isNotEmpty && visited.length < 18) {
      final target = queue.removeAt(0);
      if (!visited.add(target.url)) continue;
      try {
        final page = await _getPage(target.url, referer: target.referer);
        _collectDirectMedia(page.body, direct, page.url);
        final doc = html_parser.parse(page.body);
        for (final candidate in _serverUrls(doc, page.url)) {
          if (candidate.contains('.m3u8') || candidate.contains('.mp4')) {
            direct.add(candidate);
          } else if (target.depth < 2 && !visited.contains(candidate)) {
            queue.add(_FetchTarget(candidate, page.url, target.depth + 1));
          }
        }
      } catch (_) {}
    }

    final sorted = direct.toList()
      ..sort((a, b) {
        int score(String u) {
          final lower = u.toLowerCase();
          if (lower.contains('1080')) return 0;
          if (lower.contains('720')) return 1;
          if (lower.contains('.m3u8')) return 2;
          if (lower.contains('.mp4')) return 3;
          return 4;
        }
        return score(a).compareTo(score(b));
      });
    return sorted.map((u) {
      final match = RegExp(r'(2160|1440|1080|720|480|360)p?', caseSensitive: false)
          .firstMatch(u);
      return VideoSource(
        url: u,
        quality: match == null ? 'المصدر' : '${match.group(1)}p',
      );
    }).toList(growable: false);
  }

  Future<List<MediaCategory>> categories() async {
    if (source.id == 'alooytv') {
      return const <MediaCategory>[MediaCategory(id: 'all', title: 'الكل')];
    }
    if (source.id == 'akwam') {
      return const <MediaCategory>[
        MediaCategory(id: 'movies', title: 'أفلام'),
        MediaCategory(id: 'series', title: 'مسلسلات'),
      ];
    }
    return const <MediaCategory>[MediaCategory(id: 'all', title: 'الكل')];
  }

  Future<List<MediaItem>> categoryVideos(String id, {int page = 1}) async {
    if (source.id == 'alooytv') return alooyHome();
    if (source.id == 'akwam') {
      if (id == 'movies') return _akwamList('movies', page: page);
      if (id == 'series') return _akwamList('series', page: page);
      final movies = await _akwamList('movies', page: page);
      final series = await _akwamList('series', page: page);
      return <MediaItem>[...movies, ...series];
    }
    return home();
  }

  Future<List<MediaItem>> parseJsonEndpoint(String url) async {
    final raw = (await _getPage(url)).body;
    final decoded = jsonDecode(raw);
    dynamic data = decoded;
    if (decoded is Map) {
      for (final key in const [
        'results',
        'items',
        'data',
        'movies',
        'series',
        'content',
      ]) {
        if (decoded[key] is List) {
          data = decoded[key];
          break;
        }
      }
    }
    if (data is! List) return const [];
    return data.whereType<Map>().map((m) {
      final map = Map<String, dynamic>.from(m);
      String pick(List<String> keys) {
        for (final k in keys) {
          final v = map[k];
          if (v != null && v.toString().trim().isNotEmpty) return v.toString();
        }
        return '';
      }

      final id = pick(['id', 'url', 'link', 'slug']);
      final title = pick(['title', 'name', 'ar_title', 'original_title']);
      final poster = _abs(pick([
        'poster',
        'poster_path',
        'image',
        'cover',
        'thumbnail',
      ]));
      final backdrop = _abs(pick([
        'backdrop',
        'backdrop_path',
        'cover',
        'image',
        'poster',
      ]));
      final type = pick(['type', 'media_type', 'kind']).toLowerCase();
      return MediaItem(
        id: id.startsWith('http') ? id : _abs(id),
        title: title,
        posterUrl: poster,
        backdropUrl: backdrop.isEmpty ? poster : backdrop,
        isSeries: type.contains('tv') || type.contains('series'),
        raw: {...map, '_source': source.id},
      );
    }).where((e) => e.id.isNotEmpty && e.title.isNotEmpty).toList();
  }
}

class _AkwamCacheEntry {
  const _AkwamCacheEntry(this.createdAt, this.items);
  final DateTime createdAt;
  final List<MediaItem> items;
}

class _FetchedPage {
  const _FetchedPage(this.url, this.body);
  final String url;
  final String body;
}

class _FetchTarget {
  const _FetchTarget(this.url, this.referer, this.depth);
  final String url;
  final String? referer;
  final int depth;
}
