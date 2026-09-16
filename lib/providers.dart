import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/utils/display_text.dart';
import 'data/models/category.dart';
import 'data/models/media_item.dart';
import 'data/models/network_access_state.dart';
import 'data/services/cinemana_api.dart';
import 'data/stores/download_store.dart';
import 'data/stores/app_settings_store.dart';
import 'data/stores/library_store.dart';
import 'data/stores/subtitle_settings_store.dart';

final apiProvider = Provider<CinemanaApi>((ref) => CinemanaApi());

final imdbRatingProvider = FutureProvider.family<double, String>((ref, id) async {
  final cleanId = id.trim();
  if (cleanId.isEmpty) return 0;
  return ref.read(apiProvider).imdbRating(cleanId);
});

final libraryProvider = ChangeNotifierProvider<LibraryStore>((ref) {
  final store = LibraryStore();
  store.load();
  return store;
});

final downloadProvider = ChangeNotifierProvider<DownloadStore>((ref) {
  final store = DownloadStore();
  store.load();
  return store;
});

final appSettingsProvider = ChangeNotifierProvider<AppSettingsStore>((ref) {
  final store = AppSettingsStore();
  store.load();
  return store;
});

final subtitleSettingsProvider = ChangeNotifierProvider<SubtitleSettingsStore>((ref) {
  final store = SubtitleSettingsStore();
  store.load();
  return store;
});

class HomeFeed {
  const HomeFeed({
    required this.highlights,
    required this.newlyAdded,
    required this.sections,
    required this.collections,
  });

  final List<MediaItem> highlights;
  final List<MediaItem> newlyAdded;
  final List<MediaSection> sections;
  final List<MediaSection> collections;
}

const _preferredHomeGroups = <String>[
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

List<MediaSection> _orderMediaSections(
  List<MediaSection> input,
  List<String> preferred,
) {
  final remaining = [...input];
  final ordered = <MediaSection>[];

  for (final wanted in preferred) {
    final needle = cinematyComparableTitle(wanted);
    final index = remaining.indexWhere((section) {
      final haystack = cinematyComparableTitle(section.title);
      return haystack == needle || haystack.contains(needle) || needle.contains(haystack);
    });
    if (index >= 0) ordered.add(remaining.removeAt(index));
  }
  ordered.addAll(remaining);
  return ordered;
}

final homeFeedProvider = FutureProvider<HomeFeed>((ref) async {
  final api = ref.read(apiProvider);
  final results = await Future.wait<dynamic>([
    api.homeHighlights(),
    api.newlyAdded(),
    api.homeSections(),
    api.collections(),
  ]);

  final groups = _orderMediaSections(
    results[2] as List<MediaSection>,
    _preferredHomeGroups,
  );
  var collections = _orderMediaSections(
    results[3] as List<MediaSection>,
    _preferredCollections,
  );

  // Collection metadata can arrive without embedded videos. Load a tiny
  // preview for the first collections so the home "المجموعات" cards use real
  // Cinemana artwork. The full collection is still loaded only after opening.
  final previewCount = collections.length.clamp(0, 10).toInt();
  if (previewCount > 0) {
    final previews = await Future.wait(
      collections.take(previewCount).map((section) async {
        if (section.items.isNotEmpty) return section;
        try {
          final items = await api.collectionVideos(section.id);
          return MediaSection(
            id: section.id,
            title: section.title,
            items: items.take(6).toList(),
          );
        } catch (_) {
          return section;
        }
      }),
    );
    collections = <MediaSection>[
      ...previews,
      ...collections.skip(previewCount),
    ];
  }

  return HomeFeed(
    highlights: results[0] as List<MediaItem>,
    newlyAdded: results[1] as List<MediaItem>,
    sections: groups,
    collections: collections,
  );
});

final categoriesProvider = FutureProvider<List<MediaCategory>>((ref) => ref.read(apiProvider).categories());

final categoryPreviewProvider = FutureProvider.family<List<MediaItem>, ({String id, String title})>((ref, category) async {
  final items = await ref.read(apiProvider).categoryVideos(
    category.id,
    categoryTitle: category.title,
    page: 1,
  );
  return items.take(6).toList();
});

final networkAccessProvider = FutureProvider<NetworkAccessState>((ref) async {
  // Chrome is used only as a TV UI preview. Browser network probing can be
  // reported as offline because of CORS/preflight behaviour even while the
  // Cinemana API itself is reachable. Never show the mobile "offline /
  // outside Earthlink" gate in this preview. Android and iOS keep the original
  // accessState() logic unchanged.
  if (kIsWeb) {
    return const NetworkAccessState(NetworkAccessKind.online);
  }
  return ref.read(apiProvider).accessState();
});
