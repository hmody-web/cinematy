import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/utils/display_text.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.subtitle, this.onMore});
  final String title;
  final String? subtitle;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(kIsWeb ? 30 : 18, kIsWeb ? 34 : 22, kIsWeb ? 30 : 18, kIsWeb ? 18 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cinematyDisplayTitle(title), textDirection: TextDirection.rtl, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: kIsWeb ? 32 : 19)),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(subtitle!, style: TextStyle(color: Colors.white.withOpacity(.42), fontSize: kIsWeb ? 17 : 12)),
                ],
              ],
            ),
          ),
          if (onMore != null)
            TextButton(onPressed: onMore, child: const Text('المزيد')),
        ],
      ),
    );
  }
}
