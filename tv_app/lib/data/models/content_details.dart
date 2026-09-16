import '../../core/utils/json_utils.dart';
import 'media_item.dart';

class Person {
  const Person({required this.id, required this.name, this.imageUrl = '', this.role = ''});
  final String id;
  final String name;
  final String imageUrl;
  final String role;

  factory Person.fromJson(Map<String, dynamic> json) => Person(
    id: JsonUtils.string(json, ['id', 'staff_id', 'actorID', 'staffId']),
    name: JsonUtils.string(json, ['name', 'staffTitle', 'ar_title', 'title', 'display_name'], fallback: 'غير معروف'),
    imageUrl: normalizeMediaUrl(JsonUtils.string(json, ['staff_img_medium_thumb', 'staffImgMediumThumb', 'staff_img_thumb', 'staffImgThumb', 'staff_img', 'staffImg', 'image', 'poster'])),
    role: _cleanPersonRole(JsonUtils.string(json, ['role', 'character', 'job', 'type'])),
  );
}

class ContentDetails {
  const ContentDetails({
    required this.media,
    this.genres = const [],
    this.cast = const [],
    this.directors = const [],
    this.writers = const [],
    this.trailer = '',
    this.language = '',
    this.parentalRating = '',
  });

  final MediaItem media;
  final List<String> genres;
  final List<Person> cast;
  final List<Person> directors;
  final List<Person> writers;
  final String trailer;
  final String language;
  final String parentalRating;

  factory ContentDetails.fromJson(Map<String, dynamic> json) {
    List<Person> people(dynamic raw) => JsonUtils.list(raw)
        .whereType<Map>()
        .map((e) => Person.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    final genreRaw = json['genres'] ?? json['categories'];
    final genres = genreRaw is List
        ? genreRaw.map((e) => e is Map ? JsonUtils.string(Map<String, dynamic>.from(e), ['title', 'name', 'ar_title']) : e.toString()).where((e) => e.isNotEmpty).toList()
        : JsonUtils.string(json, ['genre', 'genres']).split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    return ContentDetails(
      media: MediaItem.fromJson(json),
      genres: genres,
      cast: people(json['actorsInfo'] ?? json['cast'] ?? json['actors']),
      directors: people(json['directorsInfo'] ?? json['directors']),
      writers: people(json['writersInfo'] ?? json['writers']),
      trailer: JsonUtils.string(json, ['trailer', 'trailterFile', 'trailerUrl']),
      language: JsonUtils.string(json, ['language', 'lang_ar_title', 'lang']),
      parentalRating: JsonUtils.string(json, ['parentalControl', 'filmRating', 'mpaa']),
    );
  }
}

String _cleanPersonRole(String value) {
  final v = value.trim();
  if (v.isEmpty || RegExp(r'^\d+$').hasMatch(v)) return '';
  return v;
}
