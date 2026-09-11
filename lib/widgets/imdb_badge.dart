import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/media_item.dart';
import '../providers.dart';

class ImdbBadge extends ConsumerWidget {
  const ImdbBadge({
    super.key,
    required this.item,
    this.compact = false,
    this.darkText = true,
  });

  final MediaItem item;
  final bool compact;
  final bool darkText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(imdbRatingProvider(item.id));
    final fetched = async.asData?.value ?? 0;
    final rating = fetched > 0 ? fetched : item.rating;
    if (rating <= 0) return const SizedBox.shrink();

    final foreground = darkText ? Colors.black : Colors.white;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF5C518),
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'IMDb',
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w900,
              fontSize: compact ? 8.5 : 10,
              letterSpacing: -.2,
            ),
          ),
          SizedBox(width: compact ? 4 : 5),
          Text(
            rating.toStringAsFixed(1),
            textDirection: TextDirection.ltr,
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w900,
              fontSize: compact ? 9.5 : 11,
            ),
          ),
        ],
      ),
    );
  }
}
