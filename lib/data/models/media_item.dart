import '../../core/config/app_config.dart';
import '../../core/utils/json_utils.dart';

class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    this.description = '',
    this.posterUrl = '',
    this.backdropUrl = '',
    this.year = 0,
    this.rating = 0,
    this.views = 0,
    this.isSeries = false,
    this.season,
    this.episode,
    this.raw = const {},
  });

  final String id;
  final String title;
  final String description;
  final String posterUrl;
  final String backdropUrl;
  final int year;
  final double rating;
  final int views;
  final bool isSeries;
  final int? season;
  final int? episode;
  final Map<String, dynamic> raw;

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    final kind = JsonUtils.string(json, ['kind', 'type', 'videoKind']).toLowerCase();
    final season = JsonUtils.integer(json, ['season', 'seasonNumber'], fallback: -1);
    final episode = JsonUtils.integer(json, ['episodeNummer', 'episodeNumber', 'episode'], fallback: -1);
    final id = JsonUtils.string(json, ['nb', 'videoId', 'videoID', 'id', 'item_id', '_id']);
    final poster = JsonUtils.string(json, [
      'poster', 'imgMediumThumbObjUrl', 'imgThumbObjUrl', 'imgObjUrl', 'imgMediumThumb',
      'imgThumb', 'seasonPoster', 'episodePoster', 'image', 'cover', 'thumbnail',
    ]);
    final backdrop = JsonUtils.string(json, [
      'imgObjUrl', 'backdrop', 'backdrop_path', 'background', 'cover', 'poster',
    ]);

    return MediaItem(
      id: id,
      title: JsonUtils.string(json, [
        'custom_ar_title', 'ar_title', 'lang_ar_title', 'display_name', 'title', 'en_title',
      ], fallback: 'بدون عنوان'),
      description: JsonUtils.string(json, ['ar_content', 'description', 'plot', 'overview', 'en_content']),
      posterUrl: normalizeMediaUrl(poster),
      backdropUrl: normalizeMediaUrl(backdrop),
      year: JsonUtils.integer(json, ['year']),
      rating: JsonUtils.decimal(json, ['imdbRating', 'filmRating', 'seriesRating', 'rating', 'rate']),
      views: JsonUtils.integer(json, ['views', 'totalViews', 'viewsNumber']),
      isSeries: kind == '2' || kind.contains('tv') || kind.contains('series') || season > 0 || JsonUtils.boolean(json, ['isSeries']),
      season: season < 0 ? null : season,
      episode: episode < 0 ? null : episode,
      raw: json,
    );
  }

  MediaItem copyWith({String? backdropUrl}) => MediaItem(
    id: id,
    title: title,
    description: description,
    posterUrl: posterUrl,
    backdropUrl: backdropUrl ?? this.backdropUrl,
    year: year,
    rating: rating,
    views: views,
    isSeries: isSeries,
    season: season,
    episode: episode,
    raw: raw,
  );
}

String normalizeMediaUrl(String value) {
  if (value.isEmpty) return '';
  if (value.startsWith('http://') || value.startsWith('https://')) return value;
  if (value.startsWith('//')) return 'https:$value';
  if (value.startsWith('/')) return '${AppConfig.baseUrl}$value';
  return '${AppConfig.baseUrl}/$value';
}


class MediaSection {
  const MediaSection({required this.id, required this.title, required this.items});
  final String id;
  final String title;
  final List<MediaItem> items;
}
