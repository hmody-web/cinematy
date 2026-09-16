import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cinematy/core/navigation/cinematy_page_route.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/display_text.dart';
import '../../data/models/download_item.dart';
import '../../data/models/media_item.dart';
import '../../data/models/network_access_state.dart';
import '../../providers.dart';
import '../../widgets/cinematy_top_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/imdb_badge.dart';
import '../../widgets/media_card.dart';
import '../../widgets/network_image.dart';
import '../../widgets/section_header.dart';
import '../../widgets/shimmer.dart';
import '../details/details_screen.dart';
import 'section_browse_screen.dart';
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
          CinematyPageRoute(
            builder: (_) => PlayerScreen(
              media: item.media,
              localPath: item.localPath,
            ),
          ),
        ),
        onContinue: () => Navigator.push(
          context,
          CinematyPageRoute(builder: (_) => const ContinueWatchingScreen()),
        ),
        onDownloads: () => Navigator.push(
          context,
          CinematyPageRoute(builder: (_) => const DownloadsScreen()),
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
            CinematyPageRoute(builder: (_) => const ContinueWatchingScreen()),
          ),
          onDownloads: () => Navigator.push(
            context,
            CinematyPageRoute(builder: (_) => const DownloadsScreen()),
          ),
        ),
        error: (error, _) => CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _topBarSliver(
              downloads.items.length + downloads.activeItems.length,
              onContinue: () => Navigator.push(
                context,
                CinematyPageRoute(builder: (_) => const ContinueWatchingScreen()),
              ),
              onDownloads: () => Navigator.push(
                context,
                CinematyPageRoute(builder: (_) => const DownloadsScreen()),
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
              data.sections.isEmpty &&
              data.collections.isEmpty;
          if (isCompletelyEmpty) {
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                _topBarSliver(
                  downloads.items.length + downloads.activeItems.length,
                  onContinue: () => Navigator.push(
                    context,
                    CinematyPageRoute(builder: (_) => const ContinueWatchingScreen()),
                  ),
                  onDownloads: () => Navigator.push(
                    context,
                    CinematyPageRoute(builder: (_) => const DownloadsScreen()),
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
                  CinematyPageRoute(builder: (_) => const ContinueWatchingScreen()),
                ),
                onDownloads: () => Navigator.push(
                  context,
                  CinematyPageRoute(builder: (_) => const DownloadsScreen()),
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
                    height: kIsWeb ? 410 : 270,
                    child: ListView.separated(
                      padding: EdgeInsets.symmetric(horizontal: kIsWeb ? 30 : 18),
                      scrollDirection: Axis.horizontal,
                      itemCount: continueItems.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (_, i) {
                        final item = continueItems[i];
                        final resumeTitle =
                            item.raw['_seriesTitle']?.toString().trim();
                        final resumeSubtitle = (item.season ?? 0) > 0 && (item.episode ?? 0) > 0
                            ? 'الموسم ${item.season} • الحلقة ${item.episode}'
                            : null;
                        return MediaPosterCard(
                          item: item,
                          width: kIsWeb ? 188 : 138,
                          progress: library.cardProgress(item.id)?.ratio,
                          titleOverride: resumeTitle != null && resumeTitle.isNotEmpty
                              ? resumeTitle
                              : null,
                          subtitleOverride: resumeSubtitle,
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
                    onMore: () => Navigator.push(
                      context,
                      CinematyPageRoute(
                        builder: (_) => SectionBrowseScreen(
                          title: 'الإصدارات الجديدة',
                          id: 'newly-added',
                          kind: SectionBrowseKind.newlyAdded,
                          initialItems: data.newlyAdded,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              ...data.sections.take(6).expand(
                    (section) => <Widget>[
                      SliverToBoxAdapter(
                        child: SectionHeader(
                          title: cinematyDisplayTitle(section.title),
                          subtitle: 'مختارات مرتبة من المصدر',
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _HorizontalRail(
                          items: section.items.take(18).toList(),
                          onOpen: (item) => _open(context, item),
                          progressFor: (item) => library.cardProgress(item.id)?.ratio,
                          onMore: () => Navigator.push(
                            context,
                            CinematyPageRoute(
                              builder: (_) => SectionBrowseScreen(
                                title: cinematyDisplayTitle(section.title),
                                id: section.id,
                                kind: SectionBrowseKind.group,
                                initialItems: section.items,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              if (data.collections.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: SectionHeader(
                    title: 'المجموعات',
                    subtitle: 'مجموعات مختارة من سينمانا',
                  ),
                ),
                SliverToBoxAdapter(
                  child: _CollectionsRail(
                    collections: data.collections.take(10).toList(),
                    onOpen: (section) => Navigator.push(
                      context,
                      CinematyPageRoute(
                        builder: (_) => SectionBrowseScreen(
                          title: cinematyDisplayTitle(section.title),
                          id: section.id,
                          kind: SectionBrowseKind.collection,
                          initialItems: section.items,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              SliverToBoxAdapter(child: SizedBox(height: kIsWeb ? 60 : 140)),
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
              collections: <MediaSection>[],
            ),
          ),
    ]);
  }

  void _open(BuildContext context, MediaItem item) {
    Navigator.of(context).push(
      CinematyPageRoute(builder: (_) => DetailsScreen(item: item)),
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
                borderRadius: BorderRadius.circular(kIsWeb ? 34 : 30),
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
                padding: EdgeInsets.symmetric(horizontal: kIsWeb ? 30 : 18),
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
        SliverToBoxAdapter(child: SizedBox(height: kIsWeb ? 60 : 140)),
      ],
    );
  }
}

class _HorizontalRail extends StatelessWidget {
  const _HorizontalRail({
    required this.items,
    required this.onOpen,
    this.progressFor,
    this.onMore,
  });

  final List<MediaItem> items;
  final ValueChanged<MediaItem> onOpen;
  final double? Function(MediaItem item)? progressFor;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: kIsWeb ? 410 : 270,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          scrollDirection: Axis.horizontal,
          cacheExtent: 900,
          itemCount: items.length + (onMore == null ? 0 : 1),
          separatorBuilder: (_, __) => SizedBox(width: kIsWeb ? 18 : 12),
          itemBuilder: (_, i) {
            if (i == items.length && onMore != null) {
              return _MorePosterCard(onTap: onMore!);
            }
            final item = items[i];
            return MediaPosterCard(
              item: item,
              width: kIsWeb ? 228 : 142,
              progress: progressFor?.call(item),
              onTap: () => onOpen(item),
            );
          },
        ),
      );
}

class _MorePosterCard extends StatefulWidget {
  const _MorePosterCard({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_MorePosterCard> createState() => _MorePosterCardState();
}

class _MorePosterCardState extends State<_MorePosterCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final width = kIsWeb ? 228.0 : 142.0;
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(kIsWeb ? 24 : 18),
        onTap: widget.onTap,
        onFocusChange: kIsWeb ? (value) => setState(() => _focused = value) : null,
        child: AnimatedScale(
          scale: kIsWeb && _focused ? 1.06 : 1,
          duration: const Duration(milliseconds: 150),
          child: Container(
            margin: const EdgeInsets.only(bottom: 56),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [Color(0xFF251011), Color(0xFF100B0B)],
              ),
              borderRadius: BorderRadius.circular(kIsWeb ? 24 : 18),
              border: Border.all(
                color: _focused
                    ? Colors.white
                    : AppColors.redBright.withOpacity(.30),
                width: _focused ? 2.2 : 1,
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: AppColors.redBright.withOpacity(.26),
                        blurRadius: 24,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: kIsWeb ? 68 : 50,
                  height: kIsWeb ? 68 : 50,
                  decoration: BoxDecoration(
                    color: AppColors.redBright.withOpacity(.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                    size: kIsWeb ? 34 : 26,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'المزيد',
                  style: TextStyle(
                    fontSize: kIsWeb ? 24 : 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'عرض القسم كاملاً',
                  style: TextStyle(
                    color: Colors.white.withOpacity(.46),
                    fontSize: kIsWeb ? 13 : 10,
                    fontWeight: FontWeight.w700,
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

class _CollectionsRail extends StatelessWidget {
  const _CollectionsRail({required this.collections, required this.onOpen});

  final List<MediaSection> collections;
  final ValueChanged<MediaSection> onOpen;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: kIsWeb ? 270 : 168,
        child: ListView.separated(
          padding: EdgeInsets.symmetric(horizontal: kIsWeb ? 30 : 18),
          scrollDirection: Axis.horizontal,
          itemCount: collections.length,
          separatorBuilder: (_, __) => SizedBox(width: kIsWeb ? 20 : 12),
          itemBuilder: (_, i) => _CollectionCard(
            section: collections[i],
            onTap: () => onOpen(collections[i]),
          ),
        ),
      );
}

class _CollectionCard extends StatefulWidget {
  const _CollectionCard({required this.section, required this.onTap});
  final MediaSection section;
  final VoidCallback onTap;

  @override
  State<_CollectionCard> createState() => _CollectionCardState();
}

class _CollectionCardState extends State<_CollectionCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final preview = widget.section.items.isEmpty ? null : widget.section.items.first;
    final image = preview == null
        ? ''
        : (preview.backdropUrl.isNotEmpty ? preview.backdropUrl : preview.posterUrl);
    final width = kIsWeb ? 410.0 : 238.0;

    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(kIsWeb ? 26 : 20),
        onTap: widget.onTap,
        onFocusChange: kIsWeb ? (value) => setState(() => _focused = value) : null,
        child: AnimatedScale(
          scale: kIsWeb && _focused ? 1.045 : 1,
          duration: const Duration(milliseconds: 150),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kIsWeb ? 26 : 20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Color(0xFF161010)),
                if (image.isNotEmpty)
                  CinematyNetworkImage(url: image, fit: BoxFit.cover),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x22000000), Color(0xEE070505)],
                    ),
                  ),
                ),
                Positioned(
                  right: kIsWeb ? 22 : 14,
                  left: kIsWeb ? 22 : 14,
                  bottom: kIsWeb ? 22 : 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cinematyDisplayTitle(widget.section.title),
                        textDirection: TextDirection.rtl,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: kIsWeb ? 24 : 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'فتح المجموعة',
                        style: TextStyle(
                          color: Colors.white.withOpacity(.56),
                          fontSize: kIsWeb ? 13 : 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_focused)
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: Colors.white, width: 2.3),
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

class _HeroCarousel extends StatefulWidget {
  const _HeroCarousel({required this.items, required this.onOpen});
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onOpen;

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  final _controller = PageController(viewportFraction: kIsWeb ? .94 : .91);
  int _index = 0;
  int? _focusedIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final bannerWidth = screenWidth * (kIsWeb ? .78 : .91);
    // TV preview uses a cinematic 16:9 hero instead of the phone-style crop.
    // The clamp keeps it luxurious on 1080p/4K while leaving room for rails.
    final bannerHeight = kIsWeb
        ? (bannerWidth * 9 / 16).clamp(500.0, 760.0).toDouble()
        : (bannerWidth * .60).clamp(210.0, 335.0).toDouble();

    return Column(
      children: [
        SizedBox(
          height: bannerHeight + 16,
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
                  child: InkWell(
                    onTap: () => widget.onOpen(item),
                    onFocusChange: (focused) {
                      if (!kIsWeb) return;
                      setState(() => _focusedIndex = focused ? index : null);
                    },
                    focusColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    borderRadius: BorderRadius.circular(kIsWeb ? 34 : 30),
                    child: AnimatedScale(
                      scale: kIsWeb && _focusedIndex == index ? 1.018 : 1,
                      duration: const Duration(milliseconds: 150),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(kIsWeb ? 34 : 30),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const ColoredBox(color: Color(0xFF070707)),
                          CinematyNetworkImage(
                            url: image,
                            memCacheWidth: 1800,
                            fit: BoxFit.cover,
                          ),
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
                          if (kIsWeb && _focusedIndex == index)
                            IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(34),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(.95),
                                    width: 2.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.redBright.withOpacity(.28),
                                      blurRadius: 28,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          Positioned(
                            right: kIsWeb ? 46 : 16,
                            left: kIsWeb ? 46 : 16,
                            bottom: kIsWeb ? 42 : 14,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    ImdbBadge(item: item, compact: true),
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
                                const SizedBox(height: 8),
                                Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: kIsWeb ? 40 : 21,
                                    fontWeight: FontWeight.w900,
                                    height: 1.05,
                                  ),
                                ),

                              ],
                            ),
                          ),
                        ],
                      ),
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
                aspectRatio: 16 / 9,
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
