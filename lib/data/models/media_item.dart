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
    // Cinemana exposes separate image sizes. Keep the medium thumbnail for
    // list/poster cards, but preserve the full object image for immersive
    // banners/detail pages. The native Cinemana app model contains both URL
    // spellings (ObjUrl and ObjURL), so support both exactly.
    final poster = JsonUtils.string(json, [
      'poster', 'posterUrl', 'posterURL',
      'imgMediumThumbObjUrl', 'imgMediumThumbObjURL',
      'imgThumbObjUrl', 'imgThumbObjURL',
      'imgMediumThumb', 'imgThumb',
      'imgObjUrl', 'imgObjURL',
      'seasonPoster', 'episodePoster', 'image', 'cover', 'thumbnail',
    ]);
    final backdrop = JsonUtils.string(json, [
      'imgObjUrl', 'imgObjURL',
      'fullImage', 'full_image', 'originalImage', 'original_image',
      'backdrop', 'backdropUrl', 'backdropURL', 'backdrop_path',
      'background', 'cover', 'poster', 'posterUrl', 'posterURL',
      'imgMediumThumbObjUrl', 'imgMediumThumbObjURL',
    ]);

    return MediaItem(
      id: id,
      title: JsonUtils.string(json, [
        'custom_ar_title', 'ar_title', 'lang_ar_title', 'arTitle', 'display_name', 'title', 'en_title', 'enTitle',
      ], fallback: 'بدون عنوان'),
      description: JsonUtils.string(json, ['ar_content', 'arContent', 'description', 'plot', 'overview', 'en_content', 'enContent']),
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

  Map<String, dynamic> toJson() => {
    ...raw,
    'nb': id,
    'custom_ar_title': title,
    'ar_content': description,
    'poster': posterUrl,
    'backdrop': backdropUrl,
    'year': year,
    'rating': rating,
    'views': views,
    'isSeries': isSeries,
    if (season != null) 'season': season,
    if (episode != null) 'episodeNummer': episode,
  };

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
