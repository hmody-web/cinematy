import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  const HomeFeed({required this.highlights, required this.newlyAdded, required this.sections});
  final List<MediaItem> highlights;
  final List<MediaItem> newlyAdded;
  final List<MediaSection> sections;
}

final homeFeedProvider = FutureProvider<HomeFeed>((ref) async {
  final api = ref.read(apiProvider);
  final results = await Future.wait<dynamic>([
    api.homeHighlights(),
    api.newlyAdded(),
    api.homeSections(),
  ]);
  return HomeFeed(
    highlights: results[0] as List<MediaItem>,
    newlyAdded: results[1] as List<MediaItem>,
    sections: results[2] as List<MediaSection>,
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
  return ref.read(apiProvider).accessState();
});
