import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class CinematyImageCacheManager {
  CinematyImageCacheManager._();

  static final CacheManager instance = CacheManager(
    Config(
      'cinematy_image_cache_v1',
      stalePeriod: const Duration(days: 14),
      maxNrOfCacheObjects: 420,
    ),
  );
}
