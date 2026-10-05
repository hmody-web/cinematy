import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/network/image_cache.dart';
import '../core/theme/app_theme.dart';
import 'shimmer.dart';

String _stableImageCacheKey(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasAuthority) return url.trim();
  // Akwam/CDN mirrors may append changing query parameters to the same poster.
  // Cache the actual image path as one object so returning to a screen is instant.
  return uri.replace(query: '', fragment: '').toString();
}

class CinematyNetworkImage extends StatelessWidget {
  const CinematyNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.borderRadius = BorderRadius.zero,
    this.memCacheWidth = 480,
  });

  final String url;
  final BoxFit fit;
  final BorderRadius borderRadius;
  final int memCacheWidth;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: url.isEmpty
          ? const _Placeholder()
          : CachedNetworkImage(
              imageUrl: url,
              cacheKey: _stableImageCacheKey(url),
              cacheManager: CinematyImageCacheManager.instance,
              fit: fit,
              useOldImageOnUrlChange: true,
              // لا نؤخر ظهور الصورة بأنيميشن fade بعد اكتمال التنزيل.
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              memCacheWidth: memCacheWidth,
              maxWidthDiskCache: 1200,
              maxHeightDiskCache: 1800,
              placeholder: (_, __) => const _Placeholder(loading: true),
              errorWidget: (_, __, ___) => const _Placeholder(),
            ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.loading = false});
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      color: AppColors.surfaceHigh,
      alignment: Alignment.center,
      child: loading
          ? null
          : Icon(
              Icons.movie_creation_outlined,
              color: Colors.white.withOpacity(.18),
              size: 32,
            ),
    );
    return loading ? CinematyShimmer(child: box) : box;
  }
}
