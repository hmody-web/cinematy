import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/category.dart';
import '../../data/models/media_item.dart';
import '../../providers.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/network_image.dart';
import '../category/category_screen.dart';

class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const BrandLogo(size: 34, showName: false),
        actions: [
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: Center(child: Text('اكتشف', style: Theme.of(context).textTheme.titleLarge)),
          ),
        ],
      ),
      body: categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => EmptyState(title: 'تعذر جلب التصنيفات', onRetry: () => ref.invalidate(categoriesProvider)),
        data: (items) => items.isEmpty
            ? const EmptyState(title: 'لا توجد تصنيفات حالياً')
            : GridView.builder(
                key: const PageStorageKey('discover-scroll'),
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 130),
                cacheExtent: 650,
                itemCount: items.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.46,
                ),
                itemBuilder: (_, i) => _CategoryMosaicCard(category: items[i]),
              ),
      ),
    );
  }
}

class _CategoryMosaicCard extends ConsumerWidget {
  const _CategoryMosaicCard({required this.category});
  final MediaCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(categoryPreviewProvider(category.id));
    final items = preview.asData?.value ?? const <MediaItem>[];
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CategoryScreen(category: category))),
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(.07)),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 22, offset: Offset(0, 10))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(23),
          child: Stack(fit: StackFit.expand, children: [
            if (items.isNotEmpty)
              _PosterMosaic(items: items)
            else
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [AppColors.surfaceHigh, AppColors.background]),
                ),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, .48, 1],
                  colors: [Color(0x08000000), Color(0x55000000), Color(0xE5070505)],
                ),
              ),
            ),
            Positioned(
              right: 15,
              left: 15,
              bottom: 13,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(category.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, height: 1.05, shadows: [Shadow(color: Colors.black, blurRadius: 8)])),
                const SizedBox(height: 4),
                Text(category.count > 0 ? '${category.count} عمل' : 'استكشف المحتوى', style: TextStyle(color: Colors.white.withOpacity(.60), fontSize: 10.5, fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _PosterMosaic extends StatelessWidget {
  const _PosterMosaic({required this.items});
  final List<MediaItem> items;

  @override
  Widget build(BuildContext context) {
    MediaItem at(int i) => items[i % items.length];
    return Row(children: [
      Expanded(
        flex: 7,
        child: Column(children: [
          Expanded(child: CinematyNetworkImage(url: at(0).posterUrl)),
          Expanded(child: CinematyNetworkImage(url: at(1).posterUrl)),
        ]),
      ),
      Expanded(
        flex: 6,
        child: Column(children: [
          Expanded(flex: 6, child: CinematyNetworkImage(url: at(2).posterUrl)),
          Expanded(flex: 5, child: CinematyNetworkImage(url: at(3).posterUrl)),
        ]),
      ),
      Expanded(
        flex: 5,
        child: Column(children: [
          Expanded(child: CinematyNetworkImage(url: at(4).posterUrl)),
          Expanded(child: CinematyNetworkImage(url: at(5).posterUrl)),
        ]),
      ),
    ]);
  }
}
