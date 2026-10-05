import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class CinematyImageCacheManager {
  CinematyImageCacheManager._();

  /// Long-lived artwork cache.
  ///
  /// Posters/backdrops are effectively immutable for our use case. Keeping
  /// them on disk for a long time means revisiting Home/Details does not cause
  /// the same Akwam artwork to be fetched again. The server can still refresh
  /// an item after the stale period expires.
  static final CacheManager instance = CacheManager(
    Config(
      'cinematy_image_cache_v2',
      stalePeriod: const Duration(days: 365),
      maxNrOfCacheObjects: 5000,
    ),
  );
}
