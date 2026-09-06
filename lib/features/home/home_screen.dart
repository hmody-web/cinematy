import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/media_item.dart';
import '../../providers.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/media_card.dart';
import '../../widgets/network_image.dart';
import '../../widgets/section_header.dart';
import '../details/details_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(homeFeedProvider);
    final library = ref.watch(libraryProvider);
    final continueItems = library.continueWatching();

    return RefreshIndicator(
      color: AppColors.redBright,
      backgroundColor: AppColors.surfaceHigh,
      onRefresh: () async {
        ref.invalidate(homeFeedProvider);
        await ref.read(homeFeedProvider.future);
      },
      child: feed.when(
        loading: () => const _HomeSkeleton(),
        error: (error, _) => CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 110)),
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                title: 'تعذر تحميل مكتبة سينمانا',
                message: kDebugMode
                    ? 'جرّب السحب للأسفل.\n\nتفاصيل التشخيص:\n$error'
                    : 'تحقق من الاتصال ثم اسحب للأسفل للمحاولة مجدداً.',
                onRetry: () async {
                  await ref.read(apiProvider).clearApiCache();
                  ref.invalidate(homeFeedProvider);
                },
              ),
            ),
          ],
        ),
        data: (data) {
          final isCompletelyEmpty = data.highlights.isEmpty &&
              data.newlyAdded.isEmpty &&
              data.sections.isEmpty;

          if (isCompletelyEmpty) {
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 110)),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    title: 'المصدر اتصل لكن لم يرجع محتوى',
                    message: kDebugMode
                        ? 'افتح Debug Console في VS Code وابحث عن [Cinematy API] ثم أرسل لي السطور الظاهرة.'
                        : 'اسحب للأسفل لإعادة المحاولة.',
                    onRetry: () async {
                      await ref.read(apiProvider).clearApiCache();
                      ref.invalidate(homeFeedProvider);
                    },
                  ),
                ),
              ],
            );
          }

          return CustomScrollView(
          key: const PageStorageKey('home-scroll'),
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          cacheExtent: 1200,
          slivers: [
            SliverAppBar(
              pinned: false,
              floating: true,
              backgroundColor: AppColors.background.withOpacity(.92),
              surfaceTintColor: Colors.transparent,
              title: const BrandLogo(size: 36),
            ),
            if (data.highlights.isNotEmpty)
              SliverToBoxAdapter(child: _HeroCarousel(items: data.highlights, onOpen: (item) => _open(context, item))),
            if (continueItems.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SectionHeader(title: 'أكمل المشاهدة', subtitle: 'ارجع من نفس اللحظة التي توقفت عندها')),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 270,
                  child: ListView.separated(
                    reverse: false,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    scrollDirection: Axis.horizontal,
                    itemCount: continueItems.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, i) {
                      final item = continueItems[i];
                      return MediaPosterCard(
                        item: item,
                        width: 138,
                        progress: library.cardProgress(item.id)?.ratio,
                        onTap: () => _open(context, item),
                      );
                    },
                  ),
                ),
              ),
            ],
            if (data.newlyAdded.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SectionHeader(title: 'وصل حديثاً', subtitle: 'أحدث الإضافات في سينماتي')),
              SliverToBoxAdapter(child: _HorizontalRail(items: data.newlyAdded.take(18).toList(), onOpen: (item) => _open(context, item), progressFor: (item) => library.cardProgress(item.id)?.ratio)),
            ],
            ...data.sections.take(5).expand((section) => <Widget>[
              SliverToBoxAdapter(child: SectionHeader(title: section.title, subtitle: 'اختيارات مرتبة من المصدر')),
              SliverToBoxAdapter(child: _HorizontalRail(items: section.items.take(18).toList(), onOpen: (item) => _open(context, item), progressFor: (item) => library.cardProgress(item.id)?.ratio)),
            ]),
            const SliverToBoxAdapter(child: SizedBox(height: 140)),
          ],
        );
        },
      ),
    );
  }

  void _open(BuildContext context, MediaItem item) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailsScreen(item: item)));
  }
}

class _HorizontalRail extends StatelessWidget {
  const _HorizontalRail({required this.items, required this.onOpen, this.progressFor});
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onOpen;
  final double? Function(MediaItem item)? progressFor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 270,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        scrollDirection: Axis.horizontal,
        cacheExtent: 900,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => MediaPosterCard(item: items[i], progress: progressFor?.call(items[i]), onTap: () => onOpen(items[i])),
      ),
    );
  }
}

class _HeroCarousel extends StatefulWidget {
  const _HeroCarousel({required this.items, required this.onOpen});
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onOpen;

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  final _controller = PageController(viewportFraction: .91);
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 430,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.items.length,
            onPageChanged: (value) => setState(() => _index = value),
            itemBuilder: (_, index) {
              final item = widget.items[index];
              final image = item.backdropUrl.isNotEmpty ? item.backdropUrl : item.posterUrl;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onOpen(item),
                  child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CinematyNetworkImage(url: image),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: [.15, .58, 1],
                            colors: [Color(0x08000000), Color(0x55000000), Color(0xF0070505)],
                          ),
                        ),
                      ),
                      Positioned(
                        right: 22,
                        left: 22,
                        bottom: 22,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              if (item.rating > 0) _HeroPill(icon: Icons.star_rounded, label: item.rating.toStringAsFixed(1)),
                              if (item.year > 0) ...[const SizedBox(width: 7), _HeroPill(label: '${item.year}')],
                              const SizedBox(width: 7),
                              _HeroPill(label: item.isSeries ? 'مسلسل' : 'فيلم'),
                            ]),
                            const SizedBox(height: 12),
                            Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w900, height: 1.08)),
                            if (item.description.isNotEmpty) ...[
                              const SizedBox(height: 9),
                              Text(item.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withOpacity(.72), height: 1.45)),
                            ],
                            const SizedBox(height: 16),
                            Row(children: [
                              FilledButton.icon(
                                onPressed: () => widget.onOpen(item),
                                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.background, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: const Text('مشاهدة', style: TextStyle(fontWeight: FontWeight.w900)),
                              ),
                              const SizedBox(width: 10),
                              IconButton.filledTonal(onPressed: () => widget.onOpen(item), icon: const Icon(Icons.info_outline_rounded)),
                            ]),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.items.length.clamp(0, 8).toInt(), (i) => AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == _index ? 18 : 5,
            height: 5,
            decoration: BoxDecoration(color: i == _index ? Colors.white : Colors.white.withOpacity(.22), borderRadius: BorderRadius.circular(20)),
          )),
        ),
      ],
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label, this.icon});
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: Colors.black.withOpacity(.34), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white.withOpacity(.10))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13), const SizedBox(width: 4)],
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
      ]),
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();
  @override
  Widget build(BuildContext context) => CustomScrollView(slivers: [
    const SliverAppBar(title: BrandLogo(size: 36)),
    SliverToBoxAdapter(child: Container(height: 420, margin: const EdgeInsets.all(18), decoration: BoxDecoration(color: Colors.white.withOpacity(.035), borderRadius: BorderRadius.circular(30)))),
    const SliverToBoxAdapter(child: SectionHeader(title: 'جاري تجهيز المحتوى')),
    SliverToBoxAdapter(child: SizedBox(height: 260, child: ListView.separated(padding: const EdgeInsets.symmetric(horizontal: 18), scrollDirection: Axis.horizontal, itemCount: 5, separatorBuilder: (_, __) => const SizedBox(width: 12), itemBuilder: (_, __) => Container(width: 142, decoration: BoxDecoration(color: Colors.white.withOpacity(.035), borderRadius: BorderRadius.circular(18)))))),
  ]);
}
