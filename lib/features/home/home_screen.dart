import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/download_item.dart';
import '../../data/models/media_item.dart';
import '../../data/models/network_access_state.dart';
import '../../providers.dart';
import '../../widgets/cinematy_top_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/media_card.dart';
import '../../widgets/network_image.dart';
import '../../widgets/section_header.dart';
import '../../widgets/shimmer.dart';
import '../details/details_screen.dart';
import '../library/library_screen.dart';
import '../player/player_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _brandGlassProgress = ValueNotifier<double>(0);
  final ValueNotifier<double> _brandOpacity = ValueNotifier<double>(1);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset.clamp(0.0, 2000.0);

    // Once we reach the Continue Watching level, keep the logo background
    // enabled for every deeper scroll position. Only the logo opacity keeps
    // changing afterwards. ValueNotifiers rebuild only the top-bar content,
    // not the entire home feed, which keeps scrolling smooth.
    final glass = offset >= 390.0 ? 1.0 : 0.0;

    // من مستوى قسم "أكمل المشاهدة" وما تحته يبقى الشعار وخلفيته
    // ظاهرين دائماً، حتى لو كان المستخدم في آخر الصفحة ثم بدأ بالصعود.
    // لا نخفي الشعار حسب عمق السكرول؛ فقط نبدّل الخلفية عند العتبة.
    if (_brandGlassProgress.value != glass) {
      _brandGlassProgress.value = glass;
    }
    if (_brandOpacity.value != 1.0) {
      _brandOpacity.value = 1.0;
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _brandGlassProgress.dispose();
    _brandOpacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(homeFeedProvider);
    final access = ref.watch(networkAccessProvider);
    final library = ref.watch(libraryProvider);
    final downloads = ref.watch(downloadProvider);
    final continueItems = library.continueWatching();

    final accessValue = access.asData?.value;
    if (accessValue != null && !accessValue.isOnline) {
      return _UnavailableHome(
        state: accessValue,
        downloads: downloads.items,
        activeDownloads: downloads.activeItems.length,
        onRetry: () => _refresh(ref),
        onOpenDownload: (item) => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PlayerScreen(
              media: item.media,
              localPath: item.localPath,
            ),
          ),
        ),
        onContinue: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ContinueWatchingScreen()),
        ),
        onDownloads: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DownloadsScreen()),
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.redBright,
      backgroundColor: AppColors.surfaceHigh,
      onRefresh: () => _refresh(ref),
      child: feed.when(
        loading: () => _HomeSkeleton(
          downloadsCount: downloads.items.length + downloads.activeItems.length,
          onContinue: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ContinueWatchingScreen()),
          ),
          onDownloads: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DownloadsScreen()),
          ),
        ),
        error: (error, _) => CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _topBarSliver(
              downloads.items.length + downloads.activeItems.length,
              onContinue: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ContinueWatchingScreen()),
              ),
              onDownloads: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DownloadsScreen()),
              ),
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                title: 'تعذر تحميل مكتبة سينمانا',
                message:
                    'تحقق من الاتصال ثم اسحب للأسفل للمحاولة مجدداً.',
                onRetry: () => _refresh(ref),
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
                _topBarSliver(
                  downloads.items.length + downloads.activeItems.length,
                  onContinue: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ContinueWatchingScreen()),
                  ),
                  onDownloads: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DownloadsScreen()),
                  ),
                ),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    title: 'المصدر متصل لكن لم يرجع محتوى',
                    message: 'اسحب للأسفل لإعادة المحاولة.',
                    onRetry: () => _refresh(ref),
                  ),
                ),
              ],
            );
          }

          return CustomScrollView(
            key: const PageStorageKey('home-scroll'),
            controller: _scrollController,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            cacheExtent: 1200,
            slivers: [
              _topBarSliver(
                downloads.items.length + downloads.activeItems.length,
                brandGlassProgressListenable: _brandGlassProgress,
                brandOpacityListenable: _brandOpacity,
                onContinue: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ContinueWatchingScreen()),
                ),
                onDownloads: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DownloadsScreen()),
                ),
              ),
              if (data.highlights.isNotEmpty)
                SliverToBoxAdapter(
                  child: _HeroCarousel(
                    items: data.highlights,
                    onOpen: (item) => _open(context, item),
                  ),
                ),
              if (continueItems.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: SectionHeader(
                    title: 'أكمل المشاهدة',
                    subtitle: 'ارجع من نفس اللحظة التي توقفت عندها',
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 270,
                    child: ListView.separated(
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
                const SliverToBoxAdapter(
                  child: SectionHeader(
                    title: 'وصل حديثاً',
                    subtitle: 'أحدث الإضافات في سينماتي',
                  ),
                ),
                SliverToBoxAdapter(
                  child: _HorizontalRail(
                    items: data.newlyAdded.take(18).toList(),
                    onOpen: (item) => _open(context, item),
                    progressFor: (item) => library.cardProgress(item.id)?.ratio,
                  ),
                ),
              ],
              ...data.sections.take(6).expand(
                    (section) => <Widget>[
                      SliverToBoxAdapter(
                        child: SectionHeader(
                          title: section.title,
                          subtitle: 'مختارات مرتبة من المصدر',
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _HorizontalRail(
                          items: section.items.take(18).toList(),
                          onOpen: (item) => _open(context, item),
                          progressFor: (item) => library.cardProgress(item.id)?.ratio,
                        ),
                      ),
                    ],
                  ),
              const SliverToBoxAdapter(child: SizedBox(height: 140)),
            ],
          );
        },
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref) async {
    await ref.read(apiProvider).clearApiCache();
    ref.invalidate(networkAccessProvider);
    ref.invalidate(homeFeedProvider);
    await Future.wait([
      ref.read(networkAccessProvider.future).catchError(
            (_) => const NetworkAccessState(NetworkAccessKind.offline),
          ),
      ref.read(homeFeedProvider.future).catchError(
            (_) => const HomeFeed(
              highlights: <MediaItem>[],
              newlyAdded: <MediaItem>[],
              sections: <MediaSection>[],
            ),
          ),
    ]);
  }

  void _open(BuildContext context, MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DetailsScreen(item: item)),
    );
  }
}

SliverAppBar _topBarSliver(
  int downloadsCount, {
  required VoidCallback onContinue,
  required VoidCallback onDownloads,
  double brandGlassProgress = 0,
  double brandOpacity = 1,
  ValueListenable<double>? brandGlassProgressListenable,
  ValueListenable<double>? brandOpacityListenable,
}) =>
    SliverAppBar(
      pinned: false,
      floating: true,
      toolbarHeight: 74,
      automaticallyImplyLeading: false,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.background.withOpacity(.82),
              border: Border(
                bottom: BorderSide(color: Colors.white.withOpacity(.035)),
              ),
            ),
          ),
        ),
      ),
      titleSpacing: 16,
      title: brandGlassProgressListenable == null || brandOpacityListenable == null
          ? CinematyTopBarContent(
              downloadsCount: downloadsCount,
              onContinue: onContinue,
              onDownloads: onDownloads,
              brandGlassProgress: brandGlassProgress,
              brandOpacity: brandOpacity,
            )
          : ValueListenableBuilder<double>(
              valueListenable: brandGlassProgressListenable,
              builder: (context, glass, _) => ValueListenableBuilder<double>(
                valueListenable: brandOpacityListenable,
                builder: (context, opacity, _) => CinematyTopBarContent(
                  downloadsCount: downloadsCount,
                  onContinue: onContinue,
                  onDownloads: onDownloads,
                  brandGlassProgress: glass,
                  brandOpacity: opacity,
                ),
              ),
            ),
    );

class _UnavailableHome extends StatelessWidget {
  const _UnavailableHome({
    required this.state,
    required this.downloads,
    required this.activeDownloads,
    required this.onRetry,
    required this.onOpenDownload,
    required this.onContinue,
    required this.onDownloads,
  });

  final NetworkAccessState state;
  final List<DownloadItem> downloads;
  final int activeDownloads;
  final VoidCallback onRetry;
  final ValueChanged<DownloadItem> onOpenDownload;
  final VoidCallback onContinue;
  final VoidCallback onDownloads;

  @override
  Widget build(BuildContext context) {
    final outside = state.isOutsideEarthlink;
    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        _topBarSliver(
          downloads.length + activeDownloads,
          onContinue: onContinue,
          onDownloads: onDownloads,
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 4),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    AppColors.redBright.withOpacity(.12),
                    Colors.white.withOpacity(.035),
                    Colors.transparent,
                  ],
                ),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white.withOpacity(.075)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.06),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      outside ? Icons.router_outlined : Icons.wifi_off_rounded,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    outside
                        ? 'أنت لست في نطاق خوادم إيرثلنك'
                        : 'انقطع اتصالك في الشبكة',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    outside
                        ? 'سينمانا تعمل ضمن نطاق خوادم إيرثلنك. يرجى المحاولة لاحقاً أو الاتصال بالشبكة المدعومة.'
                        : 'لا يوجد اتصال إنترنت فعلي الآن. تقدر تكمل مشاهدة كل ما نزلته مسبقاً بدون شبكة.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(.58),
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة الفحص'),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: SectionHeader(
            title: 'جاهز للمشاهدة بدون إنترنت',
            subtitle: 'التنزيلات الموجودة على جهازك',
          ),
        ),
        if (downloads.isEmpty)
          const SliverToBoxAdapter(
            child: SizedBox(
              height: 190,
              child: EmptyState(
                icon: Icons.download_done_rounded,
                title: 'لا توجد أفلام أو حلقات محمّلة',
                message: 'نزّل المحتوى عندما يرجع الاتصال وسيبقى متاحاً هنا.',
              ),
            ),
          )
        else
          SliverToBoxAdapter(
            child: SizedBox(
              height: 275,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                scrollDirection: Axis.horizontal,
                itemCount: downloads.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final item = downloads[i];
                  return Stack(
                    children: [
                      MediaPosterCard(
                        item: item.media,
                        width: 142,
                        onTap: () => onOpenDownload(item),
                      ),
                      if ((item.media.episode ?? 0) > 0)
                        Positioned(
                          right: 7,
                          top: 7,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(.78),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'ح ${item.media.episode}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 140)),
      ],
    );
  }
}

class _HorizontalRail extends StatelessWidget {
  const _HorizontalRail({
    required this.items,
    required this.onOpen,
    this.progressFor,
  });

  final List<MediaItem> items;
  final ValueChanged<MediaItem> onOpen;
  final double? Function(MediaItem item)? progressFor;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 270,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          scrollDirection: Axis.horizontal,
          cacheExtent: 900,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) => MediaPosterCard(
            item: items[i],
            progress: progressFor?.call(items[i]),
            onTap: () => onOpen(items[i]),
          ),
        ),
      );
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
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          SizedBox(
            height: 430,
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.items.length,
              onPageChanged: (value) => setState(() => _index = value),
              itemBuilder: (_, index) {
                final item = widget.items[index];
                final image = item.backdropUrl.isNotEmpty
                    ? item.backdropUrl
                    : item.posterUrl;
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
                          CinematyNetworkImage(url: image, memCacheWidth: 1800),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: [.15, .58, 1],
                                colors: [
                                  Color(0x08000000),
                                  Color(0x55000000),
                                  Color(0xF0070505),
                                ],
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
                                Row(
                                  children: [
                                    if (item.rating > 0)
                                      _HeroPill(
                                        icon: Icons.star_rounded,
                                        label: item.rating.toStringAsFixed(1),
                                      ),
                                    if (item.year > 0) ...[
                                      const SizedBox(width: 7),
                                      _HeroPill(label: '${item.year}'),
                                    ],
                                    const SizedBox(width: 7),
                                    _HeroPill(
                                      label: item.isSeries ? 'مسلسل' : 'فيلم',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  item.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 29,
                                    fontWeight: FontWeight.w900,
                                    height: 1.08,
                                  ),
                                ),
                                if (item.description.isNotEmpty) ...[
                                  const SizedBox(height: 9),
                                  Text(
                                    item.description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(.72),
                                      height: 1.45,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    FilledButton.icon(
                                      onPressed: () => widget.onOpen(item),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: AppColors.background,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 18,
                                          vertical: 12,
                                        ),
                                      ),
                                      icon: const Icon(Icons.play_arrow_rounded),
                                      label: const Text(
                                        'مشاهدة',
                                        style: TextStyle(fontWeight: FontWeight.w900),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    IconButton.filledTonal(
                                      onPressed: () => widget.onOpen(item),
                                      icon: const Icon(Icons.info_outline_rounded),
                                    ),
                                  ],
                                ),
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
            children: List.generate(
              widget.items.length.clamp(0, 8).toInt(),
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _index ? 18 : 5,
                height: 5,
                decoration: BoxDecoration(
                  color: i == _index ? Colors.white : Colors.white.withOpacity(.22),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
        ],
      );
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label, this.icon});
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.34),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withOpacity(.10)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
            ),
          ],
        ),
      );
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton({
    required this.downloadsCount,
    required this.onContinue,
    required this.onDownloads,
  });

  final int downloadsCount;
  final VoidCallback onContinue;
  final VoidCallback onDownloads;

  @override
  Widget build(BuildContext context) => CustomScrollView(
        slivers: [
          _topBarSliver(
            downloadsCount,
            onContinue: onContinue,
            onDownloads: onDownloads,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: AspectRatio(
                aspectRatio: 1.05,
                child: SkeletonBox(radius: 30),
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: SectionHeader(title: 'جاري تجهيز المحتوى'),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 260,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                scrollDirection: Axis.horizontal,
                itemCount: 5,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, __) => const SkeletonPosterCard(),
              ),
            ),
          ),
        ],
      );
}
