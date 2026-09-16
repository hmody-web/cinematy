import 'package:flutter/material.dart';

import '../data/models/media_item.dart';
import '../tv_context.dart';
import '../tv_focus.dart';
import '../tv_image.dart';
import '../tv_nav.dart';
import '../tv_platform_ui.dart';
import '../tv_theme.dart';
import 'tv_details_screen.dart';

String _rtlSectionScreenTitle(String value) {
  final text = value.trim();
  final match = RegExp(r'^\s*4K\s+(.+)$', caseSensitive: false).firstMatch(text);
  return match == null ? text : '${match.group(1)!.trim()} 4K';
}

class TvSectionScreen extends StatefulWidget {
  const TvSectionScreen({super.key, required this.section});
  final MediaSection section;

  @override
  State<TvSectionScreen> createState() => _TvSectionScreenState();
}

class _TvSectionScreenState extends State<TvSectionScreen> {
  late Future<List<MediaItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.section.id == 'all'
        ? Future.value(widget.section.items)
        : tvApi.groupVideos(widget.section.id, page: 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_rtlSectionScreenTitle(widget.section.title), textDirection: TextDirection.rtl), backgroundColor: TvColors.background),
      body: FutureBuilder<List<MediaItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          final items = snapshot.data?.isNotEmpty == true ? snapshot.data! : widget.section.items;
          return GridView.builder(
            padding: const EdgeInsets.all(22),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: tvIsWindowsDesktop ? 286 : 232,
              childAspectRatio: tvIsWindowsDesktop ? .62 : .61,
              crossAxisSpacing: tvIsWindowsDesktop ? 24 : 20,
              mainAxisSpacing: tvIsWindowsDesktop ? 28 : 22,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return TvFocus(
                onPressed: () => Navigator.of(context).push(tvRoute(TvDetailsScreen(item: item))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: TvImage(item.posterUrl, cacheWidth: 340)),
                    const SizedBox(height: 10),
                    Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, textDirection: TextDirection.rtl, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
