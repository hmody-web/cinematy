import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cinematy/core/navigation/cinematy_page_route.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/category.dart';
import '../../data/models/media_item.dart';
import '../../providers.dart';
import '../../widgets/cinematy_top_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/network_image.dart';
import '../../widgets/shimmer.dart';
import '../category/category_screen.dart';
import '../library/library_screen.dart';

class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    final downloads = ref.watch(downloadProvider);
    return Scaffold(
      appBar: CinematyTopBar(
        section: 'اكتشف',
        downloadsCount: downloads.items.length + downloads.activeItems.length,
        onContinue: () => Navigator.push(
          context,
          CinematyPageRoute(builder: (_) => const ContinueWatchingScreen()),
        ),
        onDownloads: () => Navigator.push(
          context,
          CinematyPageRoute(builder: (_) => const DownloadsScreen()),
        ),
      ),
      body: categories.when(
        loading: () => const _DiscoverSkeleton(),
        error: (_, __) => EmptyState(
          title: 'تعذر جلب التصنيفات',
          onRetry: () => ref.invalidate(categoriesProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(title: 'لا توجد تصنيفات حالياً');
          }
          return GridView.builder(
            key: const PageStorageKey('discover-scroll'),
            padding: EdgeInsets.fromLTRB(
              kIsWeb ? 30 : 18,
              kIsWeb ? 24 : 14,
              kIsWeb ? 30 : 18,
              kIsWeb ? 48 : 130,
            ),
            cacheExtent: 1800,
            itemCount: items.length,
            gridDelegate: kIsWeb
                ? const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 520,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 20,
                    childAspectRatio: 16 / 9,
                  )
                : const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.36,
                  ),
            itemBuilder: (_, i) => _CategoryMosaicCard(category: items[i], seed: i),
          );
        },
      ),
    );
  }
}

class _DiscoverSkeleton extends StatelessWidget {
  const _DiscoverSkeleton();

  @override
  Widget build(BuildContext context) => GridView.builder(
        padding: EdgeInsets.fromLTRB(kIsWeb ? 30 : 18, kIsWeb ? 24 : 14, kIsWeb ? 30 : 18, kIsWeb ? 48 : 130),
        itemCount: 8,
        gridDelegate: kIsWeb
            ? const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 520,
                crossAxisSpacing: 20,
                mainAxisSpacing: 20,
                childAspectRatio: 16 / 9,
              )
            : const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.36,
              ),
        itemBuilder: (_, __) => const SkeletonBox(radius: 26),
      );
}

class _CategoryMosaicCard extends ConsumerStatefulWidget {
  const _CategoryMosaicCard({required this.category, required this.seed});
  final MediaCategory category;
  final int seed;

  @override
  ConsumerState<_CategoryMosaicCard> createState() =>
      _CategoryMosaicCardState();
}

class _CategoryMosaicCardState extends ConsumerState<_CategoryMosaicCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final cachedItems =
        ref.read(apiProvider).categoryCachedVideos(widget.category.id);
    final posterItems = cachedItems
        .where((e) => e.posterUrl.trim().isNotEmpty)
        .take(6)
        .toList(growable: false);

    return AnimatedScale(
      scale: kIsWeb && _focused ? 1.04 : 1,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      child: InkWell(
        onFocusChange: (value) {
          if (!kIsWeb || _focused == value) return;
          setState(() => _focused = value);
        },
        focusColor: Colors.transparent,
        hoverColor: Colors.white.withOpacity(.025),
        onTap: () {
          final ready =
              ref.read(apiProvider).categoryCachedVideos(widget.category.id);
          Navigator.of(context).push(
            CinematyPageRoute(
              builder: (_) => CategoryScreen(
                category: widget.category,
                initialItems: ready,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(26),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: kIsWeb && _focused
                  ? Colors.white.withOpacity(.95)
                  : Colors.white.withOpacity(.07),
              width: kIsWeb && _focused ? 2.2 : 1,
            ),
            boxShadow: [
              const BoxShadow(
                color: Color(0x33000000),
                blurRadius: 22,
                offset: Offset(0, 10),
              ),
              if (kIsWeb && _focused)
                BoxShadow(
                  color: AppColors.redBright.withOpacity(.24),
                  blurRadius: 26,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(25),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (posterItems.length >= 3)
                  _ScatteredPosterMosaic(
                    items: posterItems,
                    seed: widget.seed,
                  )
                else if (widget.category.coverUrl.isNotEmpty)
                  CinematyNetworkImage(
                    url: widget.category.coverUrl,
                    memCacheWidth: kIsWeb ? 900 : 560,
                  )
                else
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [AppColors.surfaceHigh, AppColors.background],
                      ),
                    ),
                  ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, .40, 1],
                      colors: [
                        Color(0x12000000),
                        Color(0x50000000),
                        Color(0xEE070505),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: kIsWeb ? 22 : 15,
                  left: kIsWeb ? 22 : 15,
                  bottom: kIsWeb ? 20 : 13,
                  child: Text(
                    widget.category.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: kIsWeb ? 28 : 18,
                      height: 1.05,
                      shadows: const [
                        Shadow(color: Colors.black, blurRadius: 8),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScatteredPosterMosaic extends StatelessWidget {
  const _ScatteredPosterMosaic({required this.items, required this.seed});
  final List<MediaItem> items;
  final int seed;

  @override
  Widget build(BuildContext context) {
    MediaItem at(int i) => items[i % items.length];
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final cardW = w * .40;
        final cardH = h * .78;
        final placements = <({double x, double y, double angle})>[
          (x: -.10, y: -.18, angle: -.18),
          (x: .22, y: -.30, angle: .10),
          (x: .54, y: -.12, angle: -.11),
          (x: .05, y: .29, angle: .13),
          (x: .40, y: .19, angle: -.16),
          (x: .69, y: .30, angle: .16),
        ];
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: List.generate(math.min(6, items.length), (i) {
            final p = placements[(i + seed) % placements.length];
            return Positioned(
              left: p.x * w,
              top: p.y * h,
              width: cardW,
              height: cardH,
              child: Transform.rotate(
                angle: p.angle,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(.10)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: CinematyNetworkImage(url: at(i).posterUrl, memCacheWidth: 300),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
