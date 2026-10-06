import '../models/category.dart';
import '../models/content_details.dart';
import '../models/content_source.dart';
import '../models/episode.dart';
import '../models/media_item.dart';
import '../models/network_access_state.dart';
import '../models/video_source.dart';
import 'cinemana_api.dart';
import 'web_source_api.dart';

class SourceAwareApi extends CinemanaApi {
  SourceAwareApi({required this.source});

  final ContentSourceDefinition source;
  bool get _isCinemana => source.kind == ContentSourceKind.cinemana || source.id == 'cinemana';
  late final WebSourceApi _web = WebSourceApi(source);

  @override
  Future<List<MediaItem>> homeHighlights({bool refresh = false}) async {
    if (_isCinemana) return super.homeHighlights(refresh: refresh);
    final items = await _home();
    return items.take(8).toList();
  }

  Future<List<MediaItem>> _home() async {
    if (source.id == 'alooytv') return _web.alooyHome();
    if (source.kind == ContentSourceKind.jsonApi && source.id != 'cinejoy') {
      try { return await _web.parseJsonEndpoint(source.baseUrl); } catch (_) {}
    }
    return _web.home();
  }

  @override
  Future<List<MediaItem>> newlyAdded({bool refresh = false}) async {
    if (_isCinemana) return super.newlyAdded(refresh: refresh);
    final items = await _home();
    if (source.id == 'alooytv') return items.take(40).toList(growable: false);
    return items;
  }

  @override
  Future<List<MediaSection>> homeSections({bool refresh = false}) async {
    if (_isCinemana) return super.homeSections(refresh: refresh);
    if (source.id == 'akwam') {
      final results = await Future.wait<List<MediaItem>>([
        _web.categoryVideos('movies', page: 1),
        _web.categoryVideos('series', page: 1),
      ]);
      return <MediaSection>[
        if (results[0].isNotEmpty)
          MediaSection(id: 'akwam_movies', title: 'أفلام', items: results[0]),
        if (results[1].isNotEmpty)
          MediaSection(id: 'akwam_series', title: 'مسلسلات', items: results[1]),
      ];
    }
    final items = await _home();
    if (items.isEmpty) return const [];
    final sectionItems = source.id == 'alooytv'
        ? items.take(80).toList(growable: false)
        : items;
    return [MediaSection(id: 'latest', title: 'أحدث الإضافات', items: sectionItems)];
  }

  @override
  Future<List<MediaSection>> collections({bool refresh = false}) async {
    if (_isCinemana) return super.collections(refresh: refresh);
    return const [];
  }

  @override
  Future<List<MediaItem>> collectionVideos(String collectionId) async {
    if (_isCinemana) return super.collectionVideos(collectionId);
    if (source.id == 'akwam') {
      if (collectionId == 'akwam_movies') {
        return _web.categoryVideos('movies', page: 1);
      }
      if (collectionId == 'akwam_series') {
        return _web.categoryVideos('series', page: 1);
      }
    }
    return _home();
  }

  @override
  Future<List<MediaCategory>> categories({bool refresh = false}) async {
    if (_isCinemana) return super.categories(refresh: refresh);
    return _web.categories();
  }

  @override
  List<MediaItem> categoryCachedVideos(String categoryId) {
    if (_isCinemana) return super.categoryCachedVideos(categoryId);
    return const [];
  }

  @override
  Future<List<MediaItem>> categoryVideos(String categoryId, {String categoryTitle = '', int page = 1}) async {
    if (_isCinemana) {
      return super.categoryVideos(categoryId, categoryTitle: categoryTitle, page: page);
    }
    return _web.categoryVideos(categoryId, page: page);
  }

  @override
  Future<List<MediaItem>> groupVideos(String groupId, {int page = 1, String query = ''}) async {
    if (_isCinemana) return super.groupVideos(groupId, page: page, query: query);
    return _home();
  }

  @override
  Future<List<MediaItem>> search(String query, {int page = 1, String category = '', String type = '', int? fromYear, int? toYear, String star = ''}) async {
    if (_isCinemana) return super.search(query, page: page, category: category, type: type, fromYear: fromYear, toYear: toYear, star: star);
    return _web.search(query, page: page);
  }

  @override
  Future<List<MediaItem>> searchAll(String query, {int page = 1}) async {
    if (_isCinemana) return super.searchAll(query, page: page);
    return _web.search(query, page: page);
  }

  @override
  Future<List<int>> availableSearchYears({bool refresh = false}) async {
    if (_isCinemana) return super.availableSearchYears(refresh: refresh);
    return const [];
  }

  @override
  Future<ContentDetails> details(String id, {bool refresh = false}) async {
    if (_isCinemana) return super.details(id, refresh: refresh);
    return _web.details(id);
  }

  @override
  Future<List<SeasonGroup>> seasons(String id) async {
    if (_isCinemana) return super.seasons(id);
    return _web.seasons(id);
  }

  @override
  Future<List<SeasonGroup>> seasonsFor(MediaItem media, {Map<String, dynamic> detailsRaw = const {}}) async {
    if (_isCinemana) return super.seasonsFor(media, detailsRaw: detailsRaw);

    if (source.id == 'alooytv') {
      final embedded = detailsRaw['_alooyEpisodes'] ?? media.raw['_alooyEpisodes'];
      if (embedded is List && embedded.isNotEmpty) {
        return _web.alooySeasonGroupsFor(media, embedded);
      }
      return _web.seasons(media.id);
    }

    if (source.id == 'akwam') {
      final embedded = detailsRaw['_akwamEpisodes'] ?? media.raw['_akwamEpisodes'];
      if (embedded is List && embedded.isNotEmpty) {
        final bySeason = <int, List<Episode>>{};
        for (final row in embedded.whereType<Map>()) {
          final map = Map<String, dynamic>.from(row);
          final seasonNo = int.tryParse((map['seasonNumber'] ?? map['season'] ?? '1').toString()) ?? 1;
          final episodeNo = int.tryParse((map['episodeNumber'] ?? map['episode'] ?? '0').toString()) ?? 0;
          final id = (map['id'] ?? map['_sourceUrl'] ?? '').toString();
          if (episodeNo <= 0 || id.isEmpty) continue;
          final episode = Episode(
            id: id,
            title: (map['title'] ?? 'الحلقة $episodeNo').toString(),
            seasonNumber: seasonNo,
            episodeNumber: episodeNo,
            posterUrl: (map['posterUrl'] ?? media.posterUrl).toString(),
            description: (map['description'] ?? '').toString(),
            raw: <String, dynamic>{
              ...map,
              '_source': 'akwam',
              '_sourceUrl': id,
              '_seriesId': media.id,
              '_seriesTitle': media.title,
              '_seriesPoster': media.posterUrl,
              '_seriesBackdrop': media.backdropUrl,
            },
          );
          bySeason.putIfAbsent(seasonNo, () => <Episode>[]).add(episode);
        }
        if (bySeason.isNotEmpty) {
          final groups = bySeason.entries.map((entry) {
            final episodes = entry.value
              ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
            return SeasonGroup(entry.key, episodes);
          }).toList()
            ..sort((a, b) => a.number.compareTo(b.number));
          return groups;
        }
      }

      final html = (detailsRaw['_html'] ?? media.raw['_html'] ?? '').toString();
      final pageUrl = (detailsRaw['_sourceUrl'] ?? media.raw['_sourceUrl'] ?? media.id).toString();
      if (html.trim().isNotEmpty) {
        return _web.seasons(
          media.id,
          htmlBody: html,
          pageUrlOverride: pageUrl,
        );
      }
    }
    return _web.seasons(media.id);
  }

  @override
  Future<List<VideoSource>> videoSources(String id) async {
    if (_isCinemana) return super.videoSources(id);
    return _web.videoSources(id);
  }

  @override
  Future<List<SubtitleSource>> subtitles(String id) async {
    if (_isCinemana) return super.subtitles(id);
    return const [];
  }

  @override
  Future<List<SubtitleSource>> subtitlesFor(MediaItem media) async {
    if (_isCinemana) return super.subtitlesFor(media);
    return const [];
  }

  @override
  Future<double> imdbRating(String id, {bool refresh = false}) async {
    if (_isCinemana) return super.imdbRating(id, refresh: refresh);
    return 0;
  }

  @override
  Future<List<MediaItem>> recommendations(String id) async {
    if (_isCinemana) return super.recommendations(id);
    return const [];
  }

  @override
  Future<NetworkAccessState> accessState() async {
    if (_isCinemana) return super.accessState();
    return const NetworkAccessState(NetworkAccessKind.online);
  }

  @override
  Future<void> clearApiCache() async {
    if (_isCinemana) await super.clearApiCache();
  }
}
