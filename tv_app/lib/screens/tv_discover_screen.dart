import 'package:flutter/material.dart';

import '../data/models/category.dart';
import '../tv_context.dart';
import '../tv_focus.dart';
import '../tv_image.dart';
import '../tv_nav.dart';
import '../tv_platform_ui.dart';
import '../tv_theme.dart';
import 'tv_category_screen.dart';

class TvDiscoverScreen extends StatefulWidget {
  const TvDiscoverScreen({super.key});

  @override
  State<TvDiscoverScreen> createState() => _TvDiscoverScreenState();
}

class _TvDiscoverScreenState extends State<TvDiscoverScreen> {
  late Future<List<MediaCategory>> _future;

  @override
  void initState() {
    super.initState();
    _future = tvApi.categories();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MediaCategory>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        final items = snapshot.data!;
        return CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(22, 24, 22, 14),
                child: Text('اكتشف', style: TextStyle(fontSize: 29, fontWeight: FontWeight.w900)),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 34),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: tvIsWindowsDesktop ? 360 : 285,
                  mainAxisExtent: tvIsWindowsDesktop ? 190 : 150,
                  crossAxisSpacing: tvIsWindowsDesktop ? 18 : 14,
                  mainAxisSpacing: tvIsWindowsDesktop ? 18 : 14,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final category = items[index];
                  return TvFocus(
                    onPressed: () => Navigator.of(context).push(
                      tvRoute(TvCategoryScreen(category: category)),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        TvImage(category.coverUrl, cacheWidth: 460),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Color(0xE6000000), Color(0x22000000)],
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(category.title, maxLines: 2, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
