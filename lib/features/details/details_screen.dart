import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cinematy/core/navigation/cinematy_page_route.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/content_details.dart';
import '../../data/models/episode.dart';
import '../../data/models/media_item.dart';
import '../../data/models/video_source.dart';
import '../../providers.dart';
import '../../widgets/app_notice.dart';
import '../../widgets/imdb_badge.dart';
import '../../widgets/media_card.dart';
import '../../widgets/network_image.dart';
import '../../widgets/section_header.dart';
import '../../widgets/shimmer.dart';
import '../player/player_screen.dart';
import '../watch_party/watch_party_launcher_sheet.dart';
import '../watch_party/watch_party_service.dart';
import 'actor_screen.dart';

class DetailsScreen extends ConsumerStatefulWidget {
  const DetailsScreen({super.key, required this.item});
  final MediaItem item;

  @override
  ConsumerState<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends ConsumerState<DetailsScreen> {
  late Future<ContentDetails> _details;
  Future<List<SeasonGroup>>? _seasons;
  Future<List<MediaItem>>? _recommendations;
  bool _moreInfo = false;

  @override
  void initState() {
    super.initState();
    final api = ref.read(apiProvider);
    _details = api.details(widget.item.id);
    _recommendations = api.recommendations(widget.item.id).catchError((_) => <MediaItem>[]);
    _prepareSeasons();
  }

  Future<void> _prepareSeasons() async {
    if (!widget.item.isSeries) return;
    final api = ref.read(apiProvider);
    _seasons = () async {
      try {
        final details = await _details;
        return api.seasonsFor(details.media.id.isNotEmpty ? details.media : widget.item, detailsRaw: details.media.raw);
      } catch (_) {
        return api.seasonsFor(widget.item);
      }
    }();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider);
    final downloads = ref.watch(downloadProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: FutureBuilder<ContentDetails>(
        future: _details,
        builder: (context, snapshot) {
          final details = snapshot.data;
          final media = details?.media.id.isNotEmpty == true ? details!.media : widget.item;
          final watchLater = library.isWatchLater(media.id);
          final favorite = library.isFavorite(media.id);
          final downloaded = downloads.isDownloaded(media.id);
          final downloading = downloads.isDownloading(media.id);
          final downloadProgress = downloads.progressOf(media.id);
          // Cinemana's native app uses the full imgObjURL image for immersive
          // artwork. Prefer the full backdrop from videoInfo and only fall
          // back to thumbnails if no full image exists.
          final backdrop = media.backdropUrl.isNotEmpty
              ? media.backdropUrl
              : widget.item.backdropUrl.isNotEmpty
                  ? widget.item.backdropUrl
                  : media.posterUrl.isNotEmpty
                      ? media.posterUrl
                      : widget.item.posterUrl;

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _ImmersiveHero(
                  media: media,
                  details: details,
                  backdrop: backdrop,
                  watchLater: watchLater,
                  favorite: favorite,
                  downloaded: downloaded,
                  downloading: downloading,
                  downloadProgress: downloadProgress,
                  onBack: () => Navigator.pop(context),
                  onPlay: () => _play(media),
                  onWatchParty: () => _startWatchParty(media),
                  onDownload: downloading || downloaded ? null : () => _showDownloadQuality(media),
                  onWatchLater: () {
                    ref.read(libraryProvider).toggleWatchLater(media);
                    AppNotice.show(
                      context,
                      title: watchLater ? 'تمت الإزالة من المشاهدة لاحقاً' : 'تمت الإضافة للمشاهدة لاحقاً',
                      type: AppNoticeType.success,
                    );
                  },
                  onFavorite: () {
                    ref.read(libraryProvider).toggleFavorite(media);
                    AppNotice.show(
                      context,
                      title: favorite ? 'تمت الإزالة من المحفوظات' : 'تم الحفظ في المفضلة',
                      type: AppNoticeType.success,
                    );
                  },
                ),
              ),
              if (media.description.isNotEmpty) ...[
                const SliverToBoxAdapter(child: SectionHeader(title: 'القصة')),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Text(media.description, style: TextStyle(color: Colors.white.withOpacity(.74), height: 1.72, fontSize: 14.5)),
                  ),
                ),
              ],
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 4),
                  child: InkWell(
                    onTap: () => setState(() => _moreInfo = !_moreInfo),
                    borderRadius: BorderRadius.circular(18),
                    child: Ink(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(.035), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withOpacity(.07))),
                      child: Row(children: [
                        const Icon(Icons.info_outline_rounded, size: 20),
                        const SizedBox(width: 10),
                        const Expanded(child: Text('مزيد من المعلومات', style: TextStyle(fontWeight: FontWeight.w900))),
                        AnimatedRotation(turns: _moreInfo ? .5 : 0, duration: const Duration(milliseconds: 220), child: const Icon(Icons.keyboard_arrow_down_rounded)),
                      ]),
                    ),
                  ),
                ),
              ),
              if (_moreInfo)
                SliverToBoxAdapter(child: _MoreInfo(details: details, media: media)),
              if (media.isSeries && _seasons != null) ...[
                const SliverToBoxAdapter(child: SectionHeader(title: 'المواسم والحلقات', subtitle: 'اختر الموسم ثم شغّل أو نزّل أي حلقة')),
                SliverToBoxAdapter(
                  child: _SeasonsView(
                    future: _seasons!,
                    media: media,
                    onPlay: (episode) => _play(media, episode: episode),
                    onWatchPartyEpisode: (episode) =>
                        _startWatchParty(_episodeMedia(media, episode)),
                    onDownloadEpisode: (episode) => _downloadEpisode(media, episode),
                    onDownloadSeason: (episodes) => _downloadSeason(media, episodes),
                  ),
                ),
              ],
              if (details?.cast.isNotEmpty == true) ...[
                const SliverToBoxAdapter(child: SectionHeader(title: 'طاقم العمل', subtitle: 'اضغط على أي ممثل لمشاهدة أعماله')),
                SliverToBoxAdapter(
                  child: _CastRail(
                    people: details!.cast,
                    onOpen: (person) => Navigator.of(context).push(CinematyPageRoute(builder: (_) => ActorScreen(person: person))),
                  ),
                ),
              ],
              if (_recommendations != null) ...[
                const SliverToBoxAdapter(child: SectionHeader(title: 'قد يعجبك أيضاً')),
                SliverToBoxAdapter(
                  child: FutureBuilder<List<MediaItem>>(
                    future: _recommendations,
                    builder: (_, snap) {
                      final items = snap.data ?? const <MediaItem>[];
                      if (items.isEmpty) return const SizedBox(height: 20);
                      return SizedBox(
                        height: 270,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          scrollDirection: Axis.horizontal,
                          itemCount: items.take(16).length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (_, i) => MediaPosterCard(
                            item: items[i],
                            onTap: () => Navigator.of(context).push(CinematyPageRoute(builder: (_) => DetailsScreen(item: items[i]))),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 48)),
            ],
          );
        },
      ),
    );
  }

  Future<void> _startWatchParty(MediaItem media) async {
    if (FirebaseAuth.instance.currentUser == null) {
      AppNotice.show(
        context,
        title: 'سجّل الدخول أولاً',
        message: 'المشاهدة الجماعية مرتبطة بحسابك وأصدقائك ومجموعاتك.',
        type: AppNoticeType.info,
      );
      return;
    }
    try {
      final session = await WatchPartyLauncherSheet.show(
        context,
        media: media,
      );
      if (session == null || !mounted) return;
      Navigator.of(context).push(
        CinematyPageRoute(
          builder: (_) => PlayerScreen(
            media: session.media,
            watchPartySessionId: session.id,
          ),
        ),
      );
    } on WatchPartyException catch (error) {
      if (!mounted) return;
      AppNotice.show(
        context,
        title: 'تعذر بدء المشاهدة الجماعية',
        message: error.message,
        type: AppNoticeType.error,
      );
    }
  }

  Future<void> _showDownloadQuality(MediaItem media) async {
    try {
      final sources = await ref.read(apiProvider).videoSources(media.id);
      if (!mounted) return;
      if (sources.isEmpty) {
        AppNotice.show(context, title: 'لا توجد جودة للتنزيل', message: 'المصدر لم يرجع ملفاً قابلاً للتنزيل لهذا العمل.', type: AppNoticeType.error);
        return;
      }
      final selected = await showModalBottomSheet<VideoSource>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _QualitySheet(sources: sources),
      );
      if (selected == null || !mounted) return;
      AppNotice.show(context, title: 'بدأ التنزيل', message: '${media.title} • ${selected.quality}', type: AppNoticeType.download);
      List<SubtitleSource> subtitles = const <SubtitleSource>[];
      try {
        subtitles = await ref.read(apiProvider).subtitles(media.id);
      } catch (_) {}
      await ref.read(downloadProvider).download(
        media,
        selected,
        subtitles: subtitles,
      );
      if (mounted) {
        AppNotice.show(
          context,
          title: 'اكتمل التنزيل',
          message: subtitles.isEmpty
              ? media.title
              : '${media.title} • تم حفظ الترجمة أيضاً',
          type: AppNoticeType.success,
        );
      }
    } catch (_) {
      if (mounted) {
        AppNotice.show(
          context,
          title: 'تعذر التنزيل',
          message: 'تعذر بدء التنزيل حالياً. حاول مرة أخرى.',
          type: AppNoticeType.error,
        );
      }
    }
  }

  Future<void> _downloadEpisode(MediaItem series, Episode episode) async {
    final episodeMedia = _episodeMedia(series, episode);
    if (ref.read(downloadProvider).isDownloaded(episodeMedia.id)) {
      AppNotice.show(context, title: 'الحلقة محمّلة مسبقاً', type: AppNoticeType.info);
      return;
    }
    await _showDownloadQuality(episodeMedia);
  }

  Future<void> _downloadSeason(MediaItem series, List<Episode> episodes) async {
    if (episodes.isEmpty) return;
    try {
      final firstSources = await ref.read(apiProvider).videoSources(episodes.first.id);
      if (!mounted || firstSources.isEmpty) return;
      final selected = await showModalBottomSheet<VideoSource>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _QualitySheet(sources: firstSources, title: 'جودة تنزيل الموسم'),
      );
      if (selected == null || !mounted) return;
      AppNotice.show(context, title: 'بدأ تنزيل الموسم', message: '${episodes.length} حلقة • ${selected.quality}', type: AppNoticeType.download);
      for (final ep in episodes) {
        final media = _episodeMedia(series, ep);
        final store = ref.read(downloadProvider);
        if (store.isDownloaded(media.id) || store.isDownloading(media.id)) continue;
        try {
          final sources = await ref.read(apiProvider).videoSources(ep.id);
          if (sources.isEmpty) continue;
          var source = sources.first;
          for (final candidate in sources) {
            if (candidate.quality == selected.quality) {
              source = candidate;
              break;
            }
          }
          List<SubtitleSource> subtitles = const <SubtitleSource>[];
          try {
            subtitles = await ref.read(apiProvider).subtitles(ep.id);
          } catch (_) {}
          await store.download(media, source, subtitles: subtitles);
        } catch (_) {}
      }
      if (mounted) AppNotice.show(context, title: 'اكتمل تنزيل الموسم', type: AppNoticeType.success);
    } catch (_) {
      if (mounted) {
        AppNotice.show(
          context,
          title: 'تعذر تنزيل الموسم',
          message: 'لم يكتمل تنزيل الموسم. حاول مرة أخرى.',
          type: AppNoticeType.error,
        );
      }
    }
  }

  MediaItem _episodeMedia(MediaItem series, Episode episode) => MediaItem(
        id: episode.id,
        title: '${series.title} • ${episode.title}',
        description: episode.description,
        posterUrl: episode.posterUrl.isNotEmpty ? episode.posterUrl : series.posterUrl,
        backdropUrl: series.backdropUrl,
        isSeries: true,
        season: episode.seasonNumber,
        episode: episode.episodeNumber,
        raw: {...series.raw, ...episode.raw, '_seriesTitle': series.title},
      );

  void _play(MediaItem media, {Episode? episode}) {
    final target = episode == null ? media : _episodeMedia(media, episode);
    Navigator.of(context).push(CinematyPageRoute(builder: (_) => PlayerScreen(media: target)));
  }
}

class _ImmersiveHero extends StatelessWidget {
  const _ImmersiveHero({
    required this.media,
    required this.details,
    required this.backdrop,
    required this.watchLater,
    required this.favorite,
    required this.downloaded,
    required this.downloading,
    required this.downloadProgress,
    required this.onBack,
    required this.onPlay,
    required this.onWatchParty,
    required this.onDownload,
    required this.onWatchLater,
    required this.onFavorite,
  });

  final MediaItem media;
  final ContentDetails? details;
  final String backdrop;
  final bool watchLater, favorite, downloaded, downloading;
  final double downloadProgress;
  final VoidCallback onBack, onPlay, onWatchParty, onWatchLater, onFavorite;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height.clamp(560.0, 820.0).toDouble();
    final genres = details?.genres.take(3).toList() ?? const <String>[];
    return SizedBox(
      height: h,
      child: Stack(fit: StackFit.expand, children: [
        Hero(tag: 'media-${media.id}', child: CinematyNetworkImage(url: backdrop, memCacheWidth: 2200)),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
              stops: [0, .36, .72],
              colors: [Color(0xB3070505), Color(0x8F070505), Color(0x12070505)],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0, .65, 1], colors: [Color(0x55000000), Colors.transparent, AppColors.background]),
          ),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 10,
          right: 12,
          child: _GlassIcon(icon: Icons.arrow_forward_ios_rounded, onTap: onBack),
        ),
        Positioned(
          right: 20,
          left: MediaQuery.sizeOf(context).width * .36,
          bottom: 34,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(media.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 34, height: 1.05, fontWeight: FontWeight.w900, letterSpacing: -.3)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                ImdbBadge(item: media),
                if (media.year > 0) _MetaPill(text: '${media.year}'),
                ...genres.map((e) => _MetaPill(text: e)),
              ],
            ),
            if (media.description.isNotEmpty) ...[
              const SizedBox(height: 13),
              Text(media.description, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withOpacity(.72), fontSize: 13.5, height: 1.55)),
            ],
            const SizedBox(height: 18),
            Wrap(spacing: 9, runSpacing: 9, children: [
              FilledButton.icon(
                onPressed: onPlay,
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.background, minimumSize: const Size(128, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                icon: const Icon(Icons.play_arrow_rounded, size: 27),
                label: const Text('مشاهدة', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
              _HeroAction(
                icon: Icons.groups_2_rounded,
                label: 'مشاهدة جماعية',
                onTap: onWatchParty,
              ),
              _HeroAction(
                icon: downloaded ? Icons.download_done_rounded : Icons.download_rounded,
                label: downloaded ? 'تم التنزيل' : downloading ? '${(downloadProgress * 100).round()}٪' : 'تنزيل',
                progress: downloading ? downloadProgress : null,
                onTap: onDownload,
              ),
              Directionality(
                textDirection: TextDirection.rtl,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _FavoriteSaveButton(
                      selected: favorite,
                      onTap: onFavorite,
                    ),
                    const SizedBox(width: 9),
                    _HeroAction(
                      icon: watchLater ? Icons.watch_later_rounded : Icons.watch_later_outlined,
                      label: watchLater ? 'محفوظ' : 'مشاهدة لاحقاً',
                      onTap: onWatchLater,
                    ),
                  ],
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}


class _FavoriteSaveButton extends StatefulWidget {
  const _FavoriteSaveButton({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  State<_FavoriteSaveButton> createState() => _FavoriteSaveButtonState();
}

class _FavoriteSaveButtonState extends State<_FavoriteSaveButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1, end: 1.18).chain(CurveTween(curve: Curves.easeOutCubic)), weight: 42),
      TweenSequenceItem(tween: Tween<double>(begin: 1.18, end: .94).chain(CurveTween(curve: Curves.easeInOut)), weight: 20),
      TweenSequenceItem(tween: Tween<double>(begin: .94, end: 1).chain(CurveTween(curve: Curves.easeOutBack)), weight: 38),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(covariant _FavoriteSaveButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected && widget.selected) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    const yellow = Color(0xFFFFC928);

    return Tooltip(
      message: selected ? 'إزالة من المحفوظات' : 'حفظ',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: selected ? yellow.withOpacity(.16) : Colors.black.withOpacity(.34),
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? yellow.withOpacity(.55) : Colors.white.withOpacity(.13),
            ),
            boxShadow: selected
                ? [BoxShadow(color: yellow.withOpacity(.20), blurRadius: 18, spreadRadius: -4)]
                : const [],
          ),
          child: ScaleTransition(
            scale: _scale,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              ),
              child: Icon(
                selected ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                key: ValueKey(selected),
                size: 24,
                color: selected ? yellow : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroAction extends StatelessWidget {
  const _HeroAction({required this.icon, required this.label, required this.onTap, this.progress});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double? progress;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: Colors.black.withOpacity(.34), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(.13))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (progress != null)
              SizedBox(width: 22, height: 22, child: CircularProgressIndicator(value: progress!.clamp(0.0, 1.0).toDouble(), strokeWidth: 2.5, backgroundColor: Colors.white12))
            else
              Icon(icon, size: 20),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
          ]),
        ),
      );
}

class _MoreInfo extends StatelessWidget {
  const _MoreInfo({required this.details, required this.media});
  final ContentDetails? details;
  final MediaItem media;

  @override
  Widget build(BuildContext context) {
    final rows = <MapEntry<String, String>>[
      if (media.year > 0) MapEntry('سنة العرض', '${media.year}'),
      if (details?.language.isNotEmpty == true) MapEntry('اللغة', details!.language),
      if (details?.parentalRating.isNotEmpty == true) MapEntry('التصنيف العمري', details!.parentalRating),
      if (details?.directors.isNotEmpty == true) MapEntry('الإخراج', details!.directors.map((e) => e.name).join('، ')),
      if (details?.writers.isNotEmpty == true) MapEntry('الكتابة', details!.writers.map((e) => e.name).join('، ')),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white.withOpacity(.028), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(.06))),
        child: Column(children: rows.map((row) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 92, child: Text(row.key, style: TextStyle(color: Colors.white.withOpacity(.42), fontSize: 12))),
            Expanded(child: Text(row.value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
          ]),
        )).toList()),
      ),
    );
  }
}

class _GlassIcon extends StatelessWidget {
  const _GlassIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: IconButton(style: IconButton.styleFrom(backgroundColor: Colors.black.withOpacity(.32)), onPressed: onTap, icon: Icon(icon, size: 20)),
        ),
      );
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: Colors.black.withOpacity(.32), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white.withOpacity(.10))),
        child: Text(text, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)),
      );
}

class _CastRail extends StatelessWidget {
  const _CastRail({required this.people, required this.onOpen});
  final List<Person> people;
  final ValueChanged<Person> onOpen;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 142,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          scrollDirection: Axis.horizontal,
          itemCount: people.take(18).length,
          separatorBuilder: (_, __) => const SizedBox(width: 13),
          itemBuilder: (_, i) {
            final p = people[i];
            return SizedBox(
              width: 82,
              child: InkWell(
                onTap: () => onOpen(p),
                borderRadius: BorderRadius.circular(18),
                child: Column(children: [
                  SizedBox(width: 76, height: 76, child: CinematyNetworkImage(url: p.imageUrl, borderRadius: BorderRadius.circular(38))),
                  const SizedBox(height: 7),
                  Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                  if (p.role.isNotEmpty) Text(p.role, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(.38), fontSize: 9.5)),
                ]),
              ),
            );
          },
        ),
      );
}

class _SeasonsView extends ConsumerStatefulWidget {
  const _SeasonsView({
    required this.future,
    required this.media,
    required this.onPlay,
    required this.onWatchPartyEpisode,
    required this.onDownloadEpisode,
    required this.onDownloadSeason,
  });
  final Future<List<SeasonGroup>> future;
  final MediaItem media;
  final ValueChanged<Episode> onPlay;
  final ValueChanged<Episode> onWatchPartyEpisode;
  final ValueChanged<Episode> onDownloadEpisode;
  final ValueChanged<List<Episode>> onDownloadSeason;

  @override
  ConsumerState<_SeasonsView> createState() => _SeasonsViewState();
}

class _SeasonsViewState extends ConsumerState<_SeasonsView> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final downloads = ref.watch(downloadProvider);
    return FutureBuilder<List<SeasonGroup>>(
      future: widget.future,
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(18, 8, 18, 12),
            child: Column(
              children: [
                SkeletonBox(height: 44, radius: 16),
                SizedBox(height: 10),
                SkeletonBox(height: 92, radius: 18),
                SizedBox(height: 10),
                SkeletonBox(height: 92, radius: 18),
              ],
            ),
          );
        }
        final seasons = snap.data ?? const <SeasonGroup>[];
        if (seasons.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: Colors.white.withOpacity(.03), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(.06))),
              child: const Row(children: [Icon(Icons.info_outline_rounded), SizedBox(width: 10), Expanded(child: Text('المصدر لم يرجع قائمة المواسم والحلقات لهذا المسلسل حالياً.'))]),
            ),
          );
        }
        if (_selected >= seasons.length) _selected = 0;
        final current = seasons[_selected];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 44,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              scrollDirection: Axis.horizontal,
              itemCount: seasons.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(left: 8),
                child: ChoiceChip(selected: i == _selected, label: Text('الموسم ${seasons[i].number}'), onSelected: (_) => setState(() => _selected = i)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
            child: OutlinedButton.icon(
              onPressed: () => widget.onDownloadSeason(current.episodes),
              icon: const Icon(Icons.download_for_offline_outlined),
              label: Text(seasons.length == 1 ? 'تنزيل كل الحلقات' : 'تنزيل كل حلقات الموسم ${current.number}'),
            ),
          ),
          ...current.episodes.take(80).map((episode) {
            final downloaded = downloads.isDownloaded(episode.id);
            final downloading = downloads.isDownloading(episode.id);
            final progress = downloads.progressOf(episode.id);
            return InkWell(
              onTap: () => widget.onPlay(episode),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                child: Row(children: [
                  SizedBox(
                    width: 132,
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(fit: StackFit.expand, children: [
                        CinematyNetworkImage(url: episode.posterUrl.isNotEmpty ? episode.posterUrl : widget.media.backdropUrl, borderRadius: BorderRadius.circular(14)),
                        DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0x88000000)]))),
                        Positioned(
                          right: 8,
                          bottom: 7,
                          child: Container(
                            width: 31,
                            height: 31,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: Colors.black.withOpacity(.70), shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
                            child: Text('${episode.episodeNumber}', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(episode.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                    if (episode.duration.isNotEmpty) ...[const SizedBox(height: 4), Text(episode.duration, style: TextStyle(color: Colors.white.withOpacity(.42), fontSize: 11))],
                    if (episode.description.isNotEmpty) ...[const SizedBox(height: 5), Text(episode.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withOpacity(.48), fontSize: 11.5))],
                  ])),
                  const SizedBox(width: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => widget.onWatchPartyEpisode(episode),
                        icon: const Icon(Icons.groups_2_rounded),
                        tooltip: 'مشاهدة الحلقة جماعياً',
                      ),
                      if (downloaded)
                        const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.download_done_rounded, color: AppColors.success),
                            SizedBox(height: 2),
                            Text(
                              'تم تحميلها',
                              style: TextStyle(fontSize: 9.5, color: AppColors.success),
                            ),
                          ],
                        )
                      else if (downloading)
                        SizedBox(
                          width: 42,
                          height: 42,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: progress.clamp(0.0, 1.0).toDouble(),
                                strokeWidth: 2.5,
                              ),
                              Text(
                                '${(progress * 100).round()}',
                                style: const TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        IconButton(
                          onPressed: () => widget.onDownloadEpisode(episode),
                          icon: const Icon(Icons.download_rounded),
                          tooltip: 'تنزيل الحلقة',
                        ),
                    ],
                  ),
                ]),
              ),
            );
          }),
        ]);
      },
    );
  }
}

class _QualitySheet extends StatelessWidget {
  const _QualitySheet({required this.sources, this.title = 'اختيار جودة التنزيل'});
  final List<VideoSource> sources;
  final String title;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xF2151111), borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.white10)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
              child: Row(children: [
                Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            ...sources.map((s) => ListTile(
                  leading: const Icon(Icons.download_for_offline_outlined),
                  title: Text(s.quality, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: s.container.isEmpty ? null : Text(s.container),
                  onTap: () => Navigator.pop(context, s),
                )),
            const SizedBox(height: 10),
          ]),
        ),
      );
}
