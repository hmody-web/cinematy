import 'package:flutter/material.dart';

import '../data/models/media_item.dart';
import '../screens/tv_details_screen.dart';
import '../screens/tv_section_screen.dart';
import '../tv_nav.dart';
import '../tv_platform_ui.dart';
import 'tv_media_card.dart';

String _rtlSectionTitle(String value) {
  final text = value.trim();
  final match = RegExp(r'^\s*4K\s+(.+)$', caseSensitive: false).firstMatch(text);
  if (match != null) return '${match.group(1)!.trim()} 4K';
  return text;
}

class TvSectionRow extends StatelessWidget {
  const TvSectionRow({
    super.key,
    required this.section,
    this.cardWidth = 190,
    this.onArrowUp,
  });

  final MediaSection section;
  final double cardWidth;
  final VoidCallback? onArrowUp;

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Iterable<String> _titleCandidates(Map<String, dynamic> raw) sync* {
    const keys = <String>[
      'custom_ar_title',
      'ar_title',
      'arTitle',
      'videoTitle',
      'video_title',
      'movieTitle',
      'filmTitle',
      'seriesTitle',
      'display_name',
      'title',
      'name',
      'en_title',
      'enTitle',
    ];

    for (final key in keys) {
      final value = raw[key];
      if (value != null && '$value'.trim().isNotEmpty) {
        yield '$value'.trim();
      }
    }

    for (final value in raw.values) {
      if (value is Map) {
        final nested = Map<String, dynamic>.from(value);
        for (final key in keys) {
          final candidate = nested[key];
          if (candidate != null && '$candidate'.trim().isNotEmpty) {
            yield '$candidate'.trim();
          }
        }
      }
    }
  }

  String _displayTitle(MediaItem item) {
    final sectionTitle = _normalize(section.title);
    final current = _normalize(item.title);

    if (current.isNotEmpty && current != sectionTitle) {
      return item.title;
    }

    for (final candidate in _titleCandidates(item.raw)) {
      final normalized = _normalize(candidate);
      if (normalized.isEmpty || normalized == sectionTitle) continue;
      if (normalized == '4k' || normalized == 'hd') continue;
      return candidate;
    }

    return item.title;
  }

  @override
  Widget build(BuildContext context) {
    final items = section.items.take(12).toList(growable: false);
    if (items.isEmpty) return const SizedBox.shrink();

    final effectiveCardWidth = tvIsWindowsDesktop
        ? tvDesktopValue(context, tv: cardWidth, windows: 228)
        : cardWidth;
    final sectionBottom = tvIsWindowsDesktop ? 40.0 : 32.0;
    final titleSize = tvIsWindowsDesktop ? 27.0 : 23.0;
    final gap = tvIsWindowsDesktop ? 22.0 : 19.0;

    return Padding(
      padding: EdgeInsets.only(bottom: sectionBottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26),
            child: Text(
              _rtlSectionTitle(section.title),
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontSize: titleSize,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 17),
          SizedBox(
            height: effectiveCardWidth * 1.48 + (tvIsWindowsDesktop ? 74 : 60),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: 26,
                vertical: 4,
              ),
              itemCount: items.length + 1,
              separatorBuilder: (_, __) => SizedBox(width: gap),
              itemBuilder: (context, index) {
                if (index == items.length) {
                  return SizedBox(
                    width: effectiveCardWidth,
                    height: effectiveCardWidth * 1.48 + (tvIsWindowsDesktop ? 74 : 60),
                    child: TvMoreCard(
                      width: effectiveCardWidth,
                      onArrowUp: onArrowUp,
                      onPressed: () => Navigator.of(context).push(
                        tvRoute(TvSectionScreen(section: section)),
                      ),
                    ),
                  );
                }

                final item = items[index];
                final isContinue = section.id == 'continue';
                final resumeTitle = item.raw['_seriesTitle']?.toString().trim();
                final resumeSubtitle = isContinue &&
                        (item.season ?? 0) > 0 &&
                        (item.episode ?? 0) > 0
                    ? 'الموسم ${item.season} • الحلقة ${item.episode}'
                    : null;
                return TvMediaCard(
                  item: item,
                  titleOverride: isContinue && resumeTitle != null && resumeTitle.isNotEmpty
                      ? resumeTitle
                      : _displayTitle(item),
                  subtitleOverride: resumeSubtitle,
                  width: effectiveCardWidth,
                  onArrowUp: onArrowUp,
                  onPressed: () => Navigator.of(context).push(
                    tvRoute(TvDetailsScreen(item: item)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
