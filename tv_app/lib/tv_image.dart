import 'package:flutter/material.dart';

import 'tv_theme.dart';

class TvImage extends StatelessWidget {
  const TvImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.cacheWidth = 420,
    this.borderRadius = 14,
  });

  final String url;
  final BoxFit fit;
  final int cacheWidth;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final child = url.trim().isEmpty
        ? const ColoredBox(
            color: TvColors.surface2,
            child: Center(
              child: Icon(Icons.movie_outlined, color: Colors.white24, size: 40),
            ),
          )
        : Image.network(
            url,
            fit: fit,
            cacheWidth: cacheWidth,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const ColoredBox(
              color: TvColors.surface2,
              child: Center(
                child: Icon(Icons.broken_image_outlined, color: Colors.white24),
              ),
            ),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: child,
    );
  }
}
