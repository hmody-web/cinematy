import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models/media_item.dart';
import '../tv_data.dart';
import '../tv_focus.dart';
import '../tv_image.dart';
import '../tv_library.dart';
import '../tv_nav.dart';
import '../tv_platform_ui.dart';
import '../tv_theme.dart';
import '../tv_context.dart';
import '../widgets/tv_section.dart';
import '../widgets/tv_imdb_badge.dart';
import 'tv_details_screen.dart';

class TvHomeScreen extends StatefulWidget {
  const TvHomeScreen({super.key});

  @override
  State<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends State<TvHomeScreen> {
  late Future<TvHomeData> _future;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _heroFocusNode = FocusNode(debugLabel: 'home-hero');

  @override
  void initState() {
    super.initState();
    _future = loadTvHome();
  }

  Future<void> _refresh() async {
    setState(() => _future = loadTvHome(refresh: true));
    await _future;
  }

  void _scrollHeroFullyIntoView() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.offset == 0) return;

    // Banner controls are a special TV region: once focus enters the banner,
    // show the WHOLE banner, not merely the focused button.
    _scrollController.jumpTo(0);
  }

  void _focusHero() {
    _scrollHeroFullyIntoView();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _heroFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _heroFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TvHomeData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (snapshot.hasError || snapshot.data == null) {
          return _ErrorView(onRetry: _refresh);
        }
        final data = snapshot.data!;
        return AnimatedBuilder(
          animation: tvLibrary,
          builder: (context, _) {
            final continueItems = tvLibrary.continueWatching.take(10).toList();
            return CustomScrollView(
              controller: _scrollController,
              cacheExtent: 700,
              slivers: [
                SliverToBoxAdapter(
                  child: _Hero(
                    items: data.highlights,
                    primaryFocusNode: _heroFocusNode,
                    onHeroFocused: _scrollHeroFullyIntoView,
                  ),
                ),
                if (continueItems.isNotEmpty)
                  SliverToBoxAdapter(
                    child: TvSectionRow(
                      onArrowUp: _focusHero,
                      section: MediaSection(
                        id: 'continue',
                        title: 'أكمل المشاهدة',
                        items: continueItems,
                      ),
                    ),
                  ),
                ...data.sections.take(7).toList().asMap().entries.map(
                      (entry) => SliverToBoxAdapter(
                        child: TvSectionRow(
                          section: entry.value,
                          onArrowUp:
                              continueItems.isEmpty && entry.key == 0
                                  ? _focusHero
                                  : null,
                        ),
                      ),
                    ),
                if (data.collections.isNotEmpty) ...[
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(22, 8, 22, 10),
                      child: Text(
                        'المجموعات',
                        style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _Collections(collections: data.collections.take(10).toList()),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 36)),
              ],
            );
          },
        );
      },
    );
  }
}

class _Hero extends StatefulWidget {
  const _Hero({
    required this.items,
    required this.primaryFocusNode,
    required this.onHeroFocused,
  });

  final List<MediaItem> items;
  final FocusNode primaryFocusNode;
  final VoidCallback onHeroFocused;

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> {
  int _index = 0;
  Timer? _autoTimer;
  bool _precacheScheduled = false;

  @override
  void initState() {
    super.initState();
    _autoTimer = Timer.periodic(
      const Duration(seconds: 7),
      (_) {
        if (mounted && widget.items.length > 1) _next();
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precacheScheduled) {
      _precacheScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _precacheAround());
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  void _restorePrimaryFocusAfterBannerChange(bool hadFocus) {
    if (!hadFocus) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.primaryFocusNode.requestFocus();

      // AnimatedSwitcher temporarily keeps the outgoing banner alive.
      // Re-assert focus after the transition too, so focus never leaves
      // "عرض التفاصيل" while automatic browsing continues.
      Future<void>.delayed(const Duration(milliseconds: 820), () {
        if (!mounted) return;
        widget.primaryFocusNode.requestFocus();
      });
    });
  }

  void _precacheAround() {
    if (!mounted || widget.items.isEmpty) return;
    final indexes = <int>{
      _index,
      (_index + 1) % widget.items.length,
      (_index - 1 + widget.items.length) % widget.items.length,
    };
    for (final index in indexes) {
      final item = widget.items[index];
      final url =
          item.backdropUrl.isNotEmpty ? item.backdropUrl : item.posterUrl;
      if (url.trim().isEmpty) continue;
      precacheImage(
        ResizeImage(NetworkImage(url), width: 1280),
        context,
      );
    }
  }

  void _previous() {
    if (widget.items.length < 2) return;
    final keepDetailsFocused = widget.primaryFocusNode.hasFocus;

    setState(() {
      _index =
          (_index - 1 + widget.items.length) % widget.items.length;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _precacheAround());
    _restorePrimaryFocusAfterBannerChange(keepDetailsFocused);
  }

  void _next() {
    if (widget.items.length < 2) return;
    final keepDetailsFocused = widget.primaryFocusNode.hasFocus;

    setState(() => _index = (_index + 1) % widget.items.length);

    WidgetsBinding.instance.addPostFrameCallback((_) => _precacheAround());
    _restorePrimaryFocusAfterBannerChange(keepDetailsFocused);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox(height: 18);
    final item = widget.items[_index.clamp(0, widget.items.length - 1)];
    final heroHeight = tvIsWindowsDesktop
        ? (MediaQuery.sizeOf(context).height * .55).clamp(560.0, 720.0)
        : 535.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
      child: Container(
        height: heroHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF090808),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withOpacity(.06)),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 760),
          reverseDuration: const Duration(milliseconds: 640),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            fit: StackFit.expand,
            children: [
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          ),
          transitionBuilder: (child, animation) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(-.018, 0),
                  end: Offset.zero,
                ).animate(curved),
                child: ScaleTransition(
                  scale: Tween<double>(
                    begin: 1.035,
                    end: 1.0,
                  ).animate(curved),
                  child: child,
                ),
              ),
            );
          },
          child: _HeroScene(
            key: ValueKey('${item.id}-$_index'),
            item: item,
            index: _index,
            total: widget.items.length,
            onPrevious: _previous,
            onNext: _next,
            primaryFocusNode: widget.primaryFocusNode,
            onHeroFocused: widget.onHeroFocused,
          ),
        ),
      ),
    );
  }
}

class _HeroScene extends StatelessWidget {
  const _HeroScene({
    super.key,
    required this.item,
    required this.index,
    required this.total,
    required this.onPrevious,
    required this.onNext,
    required this.primaryFocusNode,
    required this.onHeroFocused,
  });

  final MediaItem item;
  final int index;
  final int total;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final FocusNode primaryFocusNode;
  final VoidCallback onHeroFocused;

  @override
  Widget build(BuildContext context) {
    final image =
        item.backdropUrl.isNotEmpty ? item.backdropUrl : item.posterUrl;
    final desktop = tvIsWindowsDesktop;
    final scale = tvWindowsScale(context);
    final screen = MediaQuery.sizeOf(context);
    final sideImageWidth = desktop
        ? (620.0 * scale).clamp(500.0, screen.width * .34)
        : 535.0;
    final copyWidth = desktop
        ? (760.0 * scale).clamp(620.0, screen.width * .43)
        : 670.0;
    final titleSize = desktop ? 48.0 * scale.clamp(.9, 1.08) : 43.0;
    final descriptionSize = desktop ? 17.5 * scale.clamp(.9, 1.08) : 16.0;
    final detailsButtonWidth = desktop ? 220.0 * scale.clamp(.9, 1.08) : 190.0;
    final detailsButtonHeight = desktop ? 56.0 * scale.clamp(.9, 1.08) : 50.0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        fit: StackFit.expand,
        children: [
          TvImage(
            image,
            cacheWidth: 1280,
            borderRadius: 0,
            fit: BoxFit.cover,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
                colors: [
                  Color(0xFB060606),
                  Color(0xE5090808),
                  Color(0x88080707),
                  Color(0x20000000),
                ],
                stops: [0, .32, .62, 1],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Color(0xC9000000),
                  Colors.transparent,
                ],
                stops: [0, .45],
              ),
            ),
          ),
          Positioned(
            left: 34,
            top: 45,
            bottom: 54,
            width: sideImageWidth,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: TvImage(
                image,
                cacheWidth: 920,
                borderRadius: 0,
                fit: BoxFit.cover,
              ),
            ),
          ),
          Positioned(
            right: 44,
            top: 48,
            bottom: 54,
            width: copyWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TvImdbBadge(item: item),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontSize: titleSize,
                      height: 1.08,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 13),
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    item.description,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontSize: descriptionSize,
                      height: 1.62,
                      color: Colors.white.withOpacity(.74),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: detailsButtonWidth,
                    child: TvFocus(
                      autofocus: true,
                      focusNode: primaryFocusNode,
                      onFocused: onHeroFocused,
                      onArrowUp: onHeroFocused,
                      onArrowDown: () {
                        FocusScope.of(context).focusInDirection(
                          TraversalDirection.down,
                        );
                      },
                      borderRadius: 14,
                      onPressed: () => Navigator.of(context).push(
                        tvRoute(TvDetailsScreen(item: item)),
                      ),
                      child: Container(
                        height: detailsButtonHeight,
                        decoration: BoxDecoration(
                          color: TvColors.red,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          textDirection: TextDirection.rtl,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.play_arrow_rounded, size: 26),
                            SizedBox(width: 8),
                            Text(
                              'عرض التفاصيل',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 34,
            right: 34,
            bottom: 16,
            child: Row(
              textDirection: TextDirection.rtl,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xDD0B0B0B),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${index + 1} / $total',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Spacer(),
                if (total > 1) ...[
                  TvFocus(
                    onFocused: onHeroFocused,
                    onPressed: onPrevious,
                    borderRadius: 11,
                    child: Container(
                      width: 44,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xDD0B0B0B),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        size: 28,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  TvFocus(
                    onFocused: onHeroFocused,
                    onPressed: onNext,
                    borderRadius: 11,
                    child: Container(
                      width: 44,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xDD0B0B0B),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.chevron_left_rounded,
                        size: 28,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Collections extends StatelessWidget {
  const _Collections({required this.collections});
  final List<MediaSection> collections;

  @override
  Widget build(BuildContext context) {
    final collectionHeight = tvIsWindowsDesktop
        ? tvDesktopValue(context, tv: 210, windows: 250)
        : 210.0;
    final collectionWidth = tvIsWindowsDesktop
        ? tvDesktopValue(context, tv: 330, windows: 400)
        : 330.0;

    return SizedBox(
      height: collectionHeight,
      child: ListView.separated(
        reverse: false,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 4),
        itemCount: collections.length,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final section = collections[index];
          final cover = section.items.isEmpty ? '' : section.items.first.backdropUrl;
          return SizedBox(
            width: collectionWidth,
            child: TvFocus(
              onPressed: () => Navigator.of(context).push(
                tvRoute(_CollectionScreen(section: section)),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TvImage(cover, cacheWidth: 580, borderRadius: 14),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xDD000000), Colors.transparent],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        section.title,
                        maxLines: 2,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CollectionScreen extends StatefulWidget {
  const _CollectionScreen({required this.section});
  final MediaSection section;

  @override
  State<_CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<_CollectionScreen> {
  late final Future<List<MediaItem>> _future = tvApi.collectionVideos(widget.section.id);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.section.title), backgroundColor: TvColors.background),
      body: FutureBuilder<List<MediaItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          return _PosterGrid(items: snapshot.data!);
        },
      ),
    );
  }
}

class _PosterGrid extends StatelessWidget {
  const _PosterGrid({required this.items});
  final List<MediaItem> items;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(28),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        childAspectRatio: .61,
        crossAxisSpacing: 18,
        mainAxisSpacing: 18,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return TvFocus(
          onPressed: () => Navigator.of(context).push(tvRoute(TvDetailsScreen(item: item))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: TvImage(item.posterUrl, cacheWidth: 420)),
              const SizedBox(height: 8),
              Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ],
          ),
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 60, color: Colors.white30),
          const SizedBox(height: 14),
          const Text('تعذر تحميل المحتوى', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }
}
