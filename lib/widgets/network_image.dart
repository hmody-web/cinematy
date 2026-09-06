import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/network/image_cache.dart';

class CinematyNetworkImage extends StatelessWidget {
  const CinematyNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.borderRadius = BorderRadius.zero,
  });

  final String url;
  final BoxFit fit;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: url.isEmpty
          ? const _Placeholder()
          : CachedNetworkImage(
              imageUrl: url,
              cacheManager: CinematyImageCacheManager.instance,
              fit: fit,
              fadeInDuration: const Duration(milliseconds: 180),
              memCacheWidth: 900,
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
    return Container(
      color: AppColors.surfaceHigh,
      alignment: Alignment.center,
      child: loading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white.withOpacity(.35)),
            )
          : Icon(Icons.movie_creation_outlined, color: Colors.white.withOpacity(.18), size: 32),
    );
  }
}
