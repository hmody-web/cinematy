import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../data/models/media_item.dart';
import 'imdb_badge.dart';
import 'network_image.dart';

class MediaPosterCard extends StatefulWidget {
  const MediaPosterCard({
    super.key,
    required this.item,
    required this.onTap,
    this.width = 142,
    this.progress,
    this.titleOverride,
    this.subtitleOverride,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final double width;
  final double? progress;
  final String? titleOverride;
  final String? subtitleOverride;

  @override
  State<MediaPosterCard> createState() => _MediaPosterCardState();
}

class _MediaPosterCardState extends State<MediaPosterCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tvPreviewFocused = kIsWeb && _focused;
    final requestedWidth = widget.width;
    final effectiveWidth = kIsWeb && requestedWidth.isFinite
        ? requestedWidth.clamp(220.0, double.infinity).toDouble()
        : requestedWidth;

    return AnimatedScale(
      scale: tvPreviewFocused ? 1.075 : 1.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: SizedBox(
        width: effectiveWidth,
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (value) {
            if (_focused == value) return;
            setState(() => _focused = value);
          },
          focusColor: Colors.transparent,
          hoverColor: Colors.white.withOpacity(.025),
          borderRadius: BorderRadius.circular(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: .68,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CinematyNetworkImage(
                      url: widget.item.posterUrl,
                      borderRadius: BorderRadius.circular(18),
                    ),
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
                    if (tvPreviewFocused)
                      IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.white.withOpacity(.94),
                              width: 2.4,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.redBright.withOpacity(.42),
                                blurRadius: 18,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: ImdbBadge(item: widget.item, compact: true),
                    ),
                    if (widget.item.isSeries)
                      const Positioned(
                        right: 8,
                        top: 8,
                        child: _Badge(icon: Icons.tv_rounded, text: 'مسلسل'),
                      ),
                    if (widget.progress != null && widget.progress! > 0)
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 8,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: LinearProgressIndicator(
                            minHeight: 3,
                            value: widget.progress!.clamp(0.0, 1.0).toDouble(),
                            backgroundColor: Colors.white.withOpacity(.18),
                            valueColor: const AlwaysStoppedAnimation(
                              AppColors.redBright,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 9),
              Text(
                (widget.titleOverride ?? widget.item.title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: kIsWeb ? (tvPreviewFocused ? 20.0 : 18.5) : (tvPreviewFocused ? 14.2 : 13.5),
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                widget.subtitleOverride ??
                    [
                      if (widget.item.year > 0) '${widget.item.year}',
                      widget.item.isSeries ? 'مسلسل' : 'فيلم',
                    ].join(' • '),
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white.withOpacity(tvPreviewFocused ? .68 : .43),
                  fontSize: kIsWeb ? 14.8 : 11.5,
                ),
              ),
            ],
          ),
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
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.58),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(.09)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            text,
            style: const TextStyle(fontSize: 9.8, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
