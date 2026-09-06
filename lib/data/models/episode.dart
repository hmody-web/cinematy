import '../../core/utils/json_utils.dart';
import 'media_item.dart';

class Episode {
  const Episode({
    required this.id,
    required this.title,
    required this.seasonNumber,
    required this.episodeNumber,
    this.posterUrl = '',
    this.duration = '',
    this.description = '',
    this.raw = const {},
  });

  final String id;
  final String title;
  final int seasonNumber;
  final int episodeNumber;
  final String posterUrl;
  final String duration;
  final String description;
  final Map<String, dynamic> raw;

  factory Episode.fromJson(Map<String, dynamic> json) {
    final ep = JsonUtils.integer(json, ['episodeNummer', 'episodeNumber', 'episode']);
    return Episode(
      id: JsonUtils.string(json, ['nb', 'videoId', 'videoID', 'id', 'item_id']),
      title: JsonUtils.string(json, ['custom_ar_title', 'ar_title', 'title'], fallback: ep > 0 ? 'الحلقة $ep' : 'حلقة'),
      seasonNumber: JsonUtils.integer(json, ['season', 'seasonNumber'], fallback: 1),
      episodeNumber: ep,
      posterUrl: normalizeMediaUrl(JsonUtils.string(json, ['episodePoster', 'seasonPoster', 'poster', 'imgMediumThumbObjUrl', 'imgThumbObjUrl'])),
      duration: JsonUtils.string(json, ['duration']),
      description: JsonUtils.string(json, ['ar_content', 'description', 'plot']),
      raw: json,
    );
  }
}

class SeasonGroup {
  const SeasonGroup(this.number, this.episodes);
  final int number;
  final List<Episode> episodes;
}
