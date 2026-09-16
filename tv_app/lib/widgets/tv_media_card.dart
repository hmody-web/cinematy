import 'package:flutter/material.dart';

import '../data/models/media_item.dart';
import '../tv_focus.dart';
import '../tv_image.dart';
import '../tv_platform_ui.dart';
import '../tv_theme.dart';

class TvMediaCard extends StatelessWidget {
  const TvMediaCard({
    super.key,
    required this.item,
    required this.onPressed,
    this.width = 190,
    this.showTitle = true,
    this.autofocus = false,
    this.titleOverride,
    this.subtitleOverride,
    this.onArrowUp,
  });

  final MediaItem item;
  final VoidCallback onPressed;
  final double width;
  final bool showTitle;
  final bool autofocus;
  final String? titleOverride;
  final String? subtitleOverride;
  final VoidCallback? onArrowUp;

  @override
  Widget build(BuildContext context) {
    final height = width * 1.48;
    final title = (titleOverride ?? item.title).trim().isEmpty
        ? item.title
        : (titleOverride ?? item.title).trim();

    return SizedBox(
      width: width,
      child: TvFocus(
        autofocus: autofocus,
        onPressed: onPressed,
        onArrowUp: onArrowUp,
        borderRadius: 17,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: width,
              height: height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TvImage(
                    item.posterUrl,
                    cacheWidth: (width * 1.8).round(),
                    borderRadius: 15,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.center,
                        colors: [
                          Color(0x66000000),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  if (item.rating > 0)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5C518),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          textDirection: TextDirection.ltr,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'IMDb',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              item.rating.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (showTitle) ...[
              const SizedBox(height: 11),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontSize: tvIsWindowsDesktop ? 18 : 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (subtitleOverride != null || item.year > 0) ...[
                const SizedBox(height: 2),
                Text(
                  subtitleOverride ?? '${item.year}',
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: TvColors.textMuted,
                    fontSize: tvIsWindowsDesktop ? 13 : 12,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class TvMoreCard extends StatelessWidget {
  const TvMoreCard({
    super.key,
    required this.onPressed,
    this.width = 190,
    this.onArrowUp,
  });

  final VoidCallback onPressed;
  final double width;
  final VoidCallback? onArrowUp;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width * 1.48 + 52,
      child: TvFocus(
        onPressed: onPressed,
        onArrowUp: onArrowUp,
        borderRadius: 17,
        child: Container(
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                TvColors.surface2,
                TvColors.surface,
              ],
            ),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.arrow_back_rounded,
                size: tvIsWindowsDesktop ? 50 : 42,
                color: Colors.white,
              ),
              SizedBox(height: 12),
              Text(
                'المزيد',
                style: TextStyle(
                  fontSize: tvIsWindowsDesktop ? 21 : 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
