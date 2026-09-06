import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../data/models/media_item.dart';
import 'network_image.dart';

class MediaPosterCard extends StatelessWidget {
  const MediaPosterCard({super.key, required this.item, required this.onTap, this.width = 142, this.progress});

  final MediaItem item;
  final VoidCallback onTap;
  final double width;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: .68,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CinematyNetworkImage(url: item.posterUrl, borderRadius: BorderRadius.circular(18)),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0x70000000)],
                      ),
                    ),
                  ),
                  if (item.rating > 0)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: _Badge(icon: Icons.star_rounded, text: item.rating.toStringAsFixed(1)),
                    ),
                  if (item.isSeries)
                    const Positioned(right: 8, top: 8, child: _Badge(icon: Icons.tv_rounded, text: 'مسلسل')),
                  if (progress != null && progress! > 0)
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: LinearProgressIndicator(
                          minHeight: 3,
                          value: progress!.clamp(0.0, 1.0).toDouble(),
                          backgroundColor: Colors.white.withOpacity(.18),
                          valueColor: const AlwaysStoppedAnimation(AppColors.redBright),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 9),
            Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
            const SizedBox(height: 3),
            Text(
              [if (item.year > 0) '${item.year}', item.isSeries ? 'مسلسل' : 'فيلم'].join(' • '),
              maxLines: 1,
              style: TextStyle(color: Colors.white.withOpacity(.43), fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(color: Colors.black.withOpacity(.58), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(.09))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: Colors.white),
        const SizedBox(width: 3),
        Text(text, style: const TextStyle(fontSize: 9.8, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}
