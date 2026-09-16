import 'data/models/media_item.dart';
import 'tv_context.dart';

class TvHomeData {
  const TvHomeData({
    required this.highlights,
    required this.sections,
    required this.collections,
  });

  final List<MediaItem> highlights;
  final List<MediaSection> sections;
  final List<MediaSection> collections;
}

const _preferredGroups = <String>[
  'عالم مارفل 4K',
  'افلام مميزه',
  'الاصدارات الجديده',
  'مسلسلات مميزه',
  'افلام 4K',
  'مسلسلات اكثر شعبيه',
];

const _preferredCollections = <String>[
  'المستحيله 4K',
  'احدث المسلسلات الاسيويه',
  'افلام التحقيق',
  'جيمس بوند 4K',
  'احدث المسلسلات',
];

String _normalize(String input) => input
    .toLowerCase()
    .replaceAll('أ', 'ا')
    .replaceAll('إ', 'ا')
    .replaceAll('آ', 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

List<MediaSection> _order(List<MediaSection> source, List<String> preferred) {
  final remaining = <MediaSection>[...source];
  final result = <MediaSection>[];
  for (final wanted in preferred) {
    final needle = _normalize(wanted);
    final index = remaining.indexWhere((section) {
      final value = _normalize(section.title);
      return value == needle || value.contains(needle) || needle.contains(value);
    });
    if (index >= 0) result.add(remaining.removeAt(index));
  }
  result.addAll(remaining);
  return result;
}

Future<TvHomeData> loadTvHome({bool refresh = false}) async {
  final results = await Future.wait<dynamic>([
    tvApi.homeHighlights(refresh: refresh),
    tvApi.homeSections(refresh: refresh),
    tvApi.collections(refresh: refresh),
  ]);
  final sections = _order(results[1] as List<MediaSection>, _preferredGroups);
  final collections = _order(results[2] as List<MediaSection>, _preferredCollections);
  return TvHomeData(
    highlights: results[0] as List<MediaItem>,
    sections: sections,
    collections: collections,
  );
}
