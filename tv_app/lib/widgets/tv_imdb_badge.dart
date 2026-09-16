import 'package:flutter/material.dart';

import '../data/models/media_item.dart';
import '../tv_context.dart';

class TvImdbBadge extends StatelessWidget {
  const TvImdbBadge({
    super.key,
    required this.item,
    this.compact = false,
  });

  final MediaItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<double>(
      future: tvApi.imdbRating(item.id),
      builder: (context, snapshot) {
        final fetched = snapshot.data ?? 0;
        final rating = fetched > 0 ? fetched : item.rating;
        if (rating <= 0) return const SizedBox.shrink();
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 7 : 10,
            vertical: compact ? 4 : 6,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFF5C518),
            borderRadius: BorderRadius.circular(compact ? 7 : 9),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            textDirection: TextDirection.ltr,
            children: [
              Text(
                'IMDb',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: compact ? 10 : 13,
                  height: 1,
                ),
              ),
              SizedBox(width: compact ? 5 : 7),
              Text(
                rating.toStringAsFixed(1),
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: compact ? 11 : 14,
                  height: 1,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
