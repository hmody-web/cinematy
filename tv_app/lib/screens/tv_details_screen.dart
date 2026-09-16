import 'package:flutter/material.dart';

import '../data/models/content_details.dart';
import '../data/models/episode.dart';
import '../data/models/media_item.dart';
import '../data/models/video_source.dart';
import '../tv_context.dart';
import '../tv_focus.dart';
import '../tv_image.dart';
import '../tv_nav.dart';
import '../tv_platform_ui.dart';
import '../tv_theme.dart';
import '../widgets/tv_imdb_badge.dart';
import '../widgets/tv_section.dart';
import 'tv_player_screen.dart';

class TvDetailsScreen extends StatefulWidget {
  const TvDetailsScreen({super.key, required this.item});

  final MediaItem item;

  @override
  State<TvDetailsScreen> createState() => _TvDetailsScreenState();
}

class _TvDetailsScreenState extends State<TvDetailsScreen> {
  late final MediaItem _entryItem;
  late final int? _resumeSeason;
  late final int? _resumeEpisode;
  late Future<_Bundle> _future;
  int _seasonIndex = 0;
  final ScrollController _pageController = ScrollController();

  void _snapPageToTop() {
    if (!_pageController.hasClients) return;
    if (_pageController.offset == 0) return;
    _pageController.animateTo(
      0,
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void initState() {
    super.initState();
    _entryItem = widget.item.seriesRootForResume;
    final resumingEpisode = _entryItem.id != widget.item.id;
    _resumeSeason = resumingEpisode ? widget.item.season : null;
    _resumeEpisode = resumingEpisode ? widget.item.episode : null;
    _future = _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpTo(0);
      }
    });
  }

  Future<_Bundle> _load() async {
    ContentDetails? details;
    List<SeasonGroup> seasons = const [];
    List<MediaItem> recommendations = const [];

    final first = await Future.wait<dynamic>([
      tvApi.details(_entryItem.id).catchError((_) => null),
      tvApi.recommendations(_entryItem.id).catchError(
        (_) => <MediaItem>[],
      ),
    ]);

    details = first[0] as ContentDetails?;
    recommendations = first[1] as List<MediaItem>;

    final media = details?.media ?? _entryItem;
    if (media.isSeries || _entryItem.isSeries) {
      try {
        seasons = await tvApi.seasonsFor(
          media,
          detailsRaw: details?.media.raw ?? const {},
        );
      } catch (_) {}
    }

    final wantedSeason = _resumeSeason;
    if (wantedSeason != null && seasons.isNotEmpty) {
      final index = seasons.indexWhere((season) => season.number == wantedSeason);
      if (index >= 0) _seasonIndex = index;
    }

    return _Bundle(
      details: details,
      seasons: seasons,
      recommendations: recommendations,
    );
  }

  MediaItem _episodeMedia(Episode episode) => MediaItem(
        id: episode.id,
        title: episode.title,
        description: episode.description,
        posterUrl: episode.posterUrl,
        backdropUrl: episode.posterUrl,
        year: _entryItem.year,
        rating: episode.rating,
        isSeries: true,
        season: episode.seasonNumber,
        episode: episode.episodeNumber,
        raw: {
          ..._entryItem.raw,
          ...episode.raw,
          'rootSeries': _entryItem.id,
          'rootSeriesNb': _entryItem.id,
          '_seriesId': _entryItem.id,
          '_seriesTitle': _entryItem.title,
          '_seriesDescription': _entryItem.description,
          '_seriesPoster': _entryItem.posterUrl,
          '_seriesBackdrop': _entryItem.backdropUrl,
          '_seriesYear': _entryItem.year,
          '_seriesRating': _entryItem.rating,
        },
      );

  void _play(MediaItem media, {String? localPath}) {
    Navigator.of(context).push(
      tvVideoRoute(
        TvPlayerScreen(
          media: media,
          localPath: localPath,
        ),
      ),
    );
  }

  int _sourcePixels(VideoSource source) {
    final match = RegExp(
      r'(2160|1440|1080|720|480|360|320|240)',
    ).firstMatch('${source.quality} ${source.resolution}');
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  bool _isDirectDownload(VideoSource source) {
    final path = Uri.tryParse(source.url)?.path.toLowerCase() ?? '';
    return source.url.trim().isNotEmpty && !path.endsWith('.m3u8');
  }

  Future<VideoSource?> _chooseDownloadQuality(
    List<VideoSource> rawSources,
  ) async {
    final sources = rawSources.where(_isDirectDownload).toList()
      ..sort((a, b) => _sourcePixels(b).compareTo(_sourcePixels(a)));

    if (sources.isEmpty) return null;

    return showDialog<VideoSource>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF151414),
        title: const Text(
          'اختر جودة التنزيل',
          textAlign: TextAlign.right,
          textDirection: TextDirection.rtl,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: SizedBox(
          width: 500,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: sources.length,
            separatorBuilder: (_, __) => const SizedBox(height: 9),
            itemBuilder: (context, index) {
              final source = sources[index];
              return TvFocus(
                autofocus: index == 0,
                onPressed: () => Navigator.pop(dialogContext, source),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 17,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.05),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      const Icon(
                        Icons.download_rounded,
                        color: TvColors.red,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          source.quality.isEmpty
                              ? 'جودة تلقائية'
                              : source.quality,
                          textAlign: TextAlign.right,
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (source.resolution.isNotEmpty)
                        Text(
                          source.resolution,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _download(MediaItem media) async {
    if (tvDownloads.isDownloaded(media.id) ||
        tvDownloads.isDownloading(media.id)) {
      return;
    }

    try {
      final values = await Future.wait<dynamic>([
        tvApi.videoSources(media.id),
        tvApi.subtitles(media.id).catchError(
          (_) => <SubtitleSource>[],
        ),
      ]);

      final sources = values[0] as List<VideoSource>;
      final subtitles = values[1] as List<SubtitleSource>;
      if (sources.isEmpty) throw StateError('NO_SOURCE');

      final source = await _chooseDownloadQuality(sources);
      if (source == null) return;

      await tvDownloads.download(
        media,
        source,
        subtitles: subtitles,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر بدء التنزيل. اختر جودة أخرى.',
            textAlign: TextAlign.right,
          ),
        ),
      );
    }
  }

  String _runtimeLabel(MediaItem media) {
    dynamic findDuration(dynamic value) {
      if (value is Map) {
        final map = Map<String, dynamic>.from(value);
        for (final key in const [
          'duration',
          'videoDuration',
          'video_duration',
          'runtime',
          'runTime',
          'length',
          'time',
        ]) {
          final candidate = map[key];
          if (candidate != null && '$candidate'.trim().isNotEmpty) {
            return candidate;
          }
        }
        for (final nested in map.values) {
          final found = findDuration(nested);
          if (found != null) return found;
        }
      } else if (value is List) {
        for (final nested in value) {
          final found = findDuration(nested);
          if (found != null) return found;
        }
      }
      return null;
    }

    final value = findDuration(media.raw);
    if (value == null) return '';

    final text = '$value'.trim();
    final hms = RegExp(r'^(\d{1,2}):(\d{1,2}):(\d{1,2})$')
        .firstMatch(text);
    if (hms != null) {
      final h = int.tryParse(hms.group(1)!) ?? 0;
      final m = int.tryParse(hms.group(2)!) ?? 0;
      return h > 0 ? '$h س ${m > 0 ? '$m د' : ''}'.trim() : '$m د';
    }

    final number = double.tryParse(
      text.replaceAll(RegExp(r'[^0-9.]'), ''),
    );
    if (number == null || number <= 0) return '';

    int minutes;
    if (number > 100000) {
      minutes = (number / 60000).round();
    } else if (number > 600) {
      minutes = (number / 60).round();
    } else {
      minutes = number.round();
    }

    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0) return '$h س ${m > 0 ? '$m د' : ''}'.trim();
    return '$minutes د';
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Bundle>(
      future: _future,
      builder: (context, snapshot) {
        final bundle = snapshot.data ??
            const _Bundle(
              details: null,
              seasons: <SeasonGroup>[],
              recommendations: <MediaItem>[],
            );

        final details = bundle.details;
        final media = details?.media ?? _entryItem;
        MediaItem? firstEpisode;
        if (bundle.seasons.isNotEmpty) {
          final season = bundle.seasons[
              _seasonIndex.clamp(0, bundle.seasons.length - 1)];
          if (season.episodes.isNotEmpty) {
            Episode episode = season.episodes.first;
            final wantedEpisode = _resumeEpisode;
            if (wantedEpisode != null) {
              final match = season.episodes.where(
                (candidate) => candidate.episodeNumber == wantedEpisode,
              );
              if (match.isNotEmpty) episode = match.first;
            }
            firstEpisode = _episodeMedia(episode);
          }
        }
        final runtime = _runtimeLabel(media);

        return AnimatedBuilder(
          animation: Listenable.merge([tvLibrary, tvDownloads]),
          builder: (context, _) {
            final playTarget = firstEpisode ?? media;
            final downloaded = tvDownloads.itemFor(playTarget.id);

            return Scaffold(
              backgroundColor: TvColors.background,
              body: CustomScrollView(
                controller: _pageController,
                cacheExtent: 900,
                slivers: [
                  SliverToBoxAdapter(
                    child: _CinematicHero(
                      media: media,
                      details: details,
                      runtime: runtime,
                      isFavorite: tvLibrary.isFavorite(media.id),
                      isLater: tvLibrary.isWatchLater(media.id),
                      isDownloaded:
                          tvDownloads.isDownloaded(playTarget.id),
                      isDownloading:
                          tvDownloads.isDownloading(playTarget.id),
                      downloadProgress:
                          tvDownloads.progressOf(playTarget.id),
                      onBack: () => Navigator.of(context).maybePop(),
                      playLabel: _resumeSeason != null && _resumeEpisode != null
                          ? 'متابعة • الموسم $_resumeSeason • الحلقة $_resumeEpisode'
                          : 'مشاهدة الآن',
                      onPlay: () => _play(
                        playTarget,
                        localPath: downloaded?.localPath,
                      ),
                      onFavorite: () => tvLibrary.toggleFavorite(media),
                      onLater: () => tvLibrary.toggleWatchLater(media),
                      onDownload: () => _download(playTarget),
                      seasons: bundle.seasons,
                      seasonIndex: _seasonIndex,
                      onSeasonChanged: (index) =>
                          setState(() => _seasonIndex = index),
                      onEpisode: (episode) {
                        final episodeMedia = _episodeMedia(episode);
                        final item = tvDownloads.itemFor(episodeMedia.id);
                        _play(
                          episodeMedia,
                          localPath: item?.localPath,
                        );
                      },
                      onEpisodeDownload: (episode) =>
                          _download(_episodeMedia(episode)),
                      initialEpisode: _resumeEpisode,
                      onHeroFocused: _snapPageToTop,
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 36),
                  ),
                  if (details?.cast.isNotEmpty == true)
                    SliverToBoxAdapter(
                      child: _CastSection(cast: details!.cast),
                    ),
                  if (bundle.recommendations.isNotEmpty)
                    SliverToBoxAdapter(
                      child: TvSectionRow(
                        section: MediaSection(
                          id: 'recommendations-${media.id}',
                          title: 'قد يعجبك أيضاً',
                          items: bundle.recommendations,
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 50),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _CinematicHero extends StatefulWidget {
  const _CinematicHero({
    required this.media,
    required this.details,
    required this.runtime,
    required this.isFavorite,
    required this.isLater,
    required this.isDownloaded,
    required this.isDownloading,
    required this.downloadProgress,
    required this.onBack,
    required this.playLabel,
    required this.onPlay,
    required this.onFavorite,
    required this.onLater,
    required this.onDownload,
    required this.seasons,
    required this.seasonIndex,
    required this.onSeasonChanged,
    required this.onEpisode,
    required this.onEpisodeDownload,
    required this.initialEpisode,
    required this.onHeroFocused,
  });

  final MediaItem media;
  final ContentDetails? details;
  final String runtime;
  final bool isFavorite;
  final bool isLater;
  final bool isDownloaded;
  final bool isDownloading;
  final double downloadProgress;
  final VoidCallback onBack;
  final String playLabel;
  final VoidCallback onPlay;
  final VoidCallback onFavorite;
  final VoidCallback onLater;
  final VoidCallback onDownload;
  final List<SeasonGroup> seasons;
  final int seasonIndex;
  final ValueChanged<int> onSeasonChanged;
  final ValueChanged<Episode> onEpisode;
  final ValueChanged<Episode> onEpisodeDownload;
  final int? initialEpisode;
  final VoidCallback onHeroFocused;

  @override
  State<_CinematicHero> createState() => _CinematicHeroState();
}

class _CinematicHeroState extends State<_CinematicHero> {
  final FocusNode _backFocus = FocusNode(debugLabel: 'details-back');
  final FocusNode _playFocus = FocusNode(debugLabel: 'details-play');
  final FocusNode _favoriteFocus = FocusNode(debugLabel: 'details-favorite');
  final FocusNode _laterFocus = FocusNode(debugLabel: 'details-later');
  final FocusNode _downloadFocus = FocusNode(debugLabel: 'details-download');
  final GlobalKey<_SeriesSidePanelState> _seriesKey =
      GlobalKey<_SeriesSidePanelState>();

  void _focusAndTop(FocusNode node) {
    widget.onHeroFocused();
    node.requestFocus();
  }

  @override
  void dispose() {
    _backFocus.dispose();
    _playFocus.dispose();
    _favoriteFocus.dispose();
    _laterFocus.dispose();
    _downloadFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    final details = widget.details;
    final backdrop =
        media.backdropUrl.isNotEmpty ? media.backdropUrl : media.posterUrl;
    final genres = details?.genres ?? const <String>[];
    final desktop = tvIsWindowsDesktop;
    final desktopScale = tvWindowsScale(context);
    final heroHeight = desktop ? MediaQuery.sizeOf(context).height : 810.0;
    final copyWidth = desktop
        ? (860.0 * desktopScale).clamp(720.0, MediaQuery.sizeOf(context).width * .48)
        : (media.isSeries ? 690.0 : 760.0);
    final titleSize = desktop ? 56.0 * desktopScale.clamp(.9, 1.08) : 50.0;
    final descSize = desktop ? 17.5 * desktopScale.clamp(.9, 1.08) : 16.0;
    final playWidth = desktop ? 225.0 * desktopScale.clamp(.9, 1.08) : 190.0;
    final playHeight = desktop ? 58.0 * desktopScale.clamp(.9, 1.08) : 52.0;

    return SizedBox(
      height: heroHeight,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Stack(
          fit: StackFit.expand,
          children: [
            TvImage(
              backdrop,
              fit: BoxFit.cover,
              cacheWidth: 1440,
              borderRadius: 0,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [
                    Color(0xFC050505),
                    Color(0xE7070707),
                    Color(0x9A070707),
                    Color(0x25000000),
                    Color(0x08000000),
                  ],
                  stops: [0, .28, .52, .78, 1],
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    TvColors.background,
                    Color(0x66000000),
                    Colors.transparent,
                  ],
                  stops: [0, .20, .58],
                ),
              ),
            ),

            Positioned(
              top: 24,
              right: 28,
              child: TvFocus(
                focusNode: _backFocus,
                onFocused: widget.onHeroFocused,
                onArrowDown: () => _focusAndTop(_playFocus),
                onPressed: widget.onBack,
                child: Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xB20A0909),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    size: 26,
                  ),
                ),
              ),
            ),

            Positioned(
              right: 44,
              top: 92,
              bottom: 62,
              width: copyWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      TvImdbBadge(item: media),
                      const SizedBox(width: 10),
                      if (media.year > 0)
                        _MetaPill(
                          icon: Icons.calendar_today_rounded,
                          text: '${media.year}',
                        ),
                      if (widget.runtime.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        _MetaPill(
                          icon: Icons.schedule_rounded,
                          text: widget.runtime,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 17),
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      media.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontSize: titleSize,
                        height: 1.04,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (genres.isNotEmpty) ...[
                    const SizedBox(height: 15),
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        textDirection: TextDirection.rtl,
                        alignment: WrapAlignment.start,
                        spacing: 8,
                        runSpacing: 8,
                        children: genres
                            .take(5)
                            .map(
                              (genre) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 13,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(.075),
                                  borderRadius: BorderRadius.circular(99),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(.12),
                                  ),
                                ),
                                child: Text(
                                  genre,
                                  textDirection: TextDirection.rtl,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                  if (media.description.isNotEmpty) ...[
                    const SizedBox(height: 21),
                    SizedBox(
                      width: double.infinity,
                      child: Text(
                        media.description,
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          fontSize: descSize,
                          height: 1.68,
                          color: Colors.white.withOpacity(.80),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 25),
                  SizedBox(
                    width: double.infinity,
                    child: Row(
                      textDirection: TextDirection.rtl,
                      children: [
                        SizedBox(
                          width: playWidth,
                          child: TvFocus(
                            autofocus: true,
                            focusNode: _playFocus,
                            onFocused: widget.onHeroFocused,
                            onArrowUp: () => _focusAndTop(_backFocus),
                            onArrowLeft: () =>
                                _focusAndTop(_favoriteFocus),
                            onArrowDown: () =>
                                _focusAndTop(_downloadFocus),
                            onPressed: widget.onPlay,
                            child: Container(
                              height: playHeight,
                              decoration: BoxDecoration(
                                color: TvColors.red,
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Row(
                                textDirection: TextDirection.rtl,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.play_arrow_rounded, size: 28),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      widget.playLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _HeroAction(
                          focusNode: _favoriteFocus,
                          icon: widget.isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          label: 'المفضلة',
                          active: widget.isFavorite,
                          onFocused: widget.onHeroFocused,
                          onArrowRight: () =>
                              _focusAndTop(_playFocus),
                          onArrowLeft: () =>
                              _focusAndTop(_laterFocus),
                          onArrowUp: () =>
                              _focusAndTop(_backFocus),
                          onArrowDown: () =>
                              _focusAndTop(_downloadFocus),
                          onPressed: widget.onFavorite,
                        ),
                        const SizedBox(width: 9),
                        _HeroAction(
                          focusNode: _laterFocus,
                          icon: widget.isLater
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                          label: 'لاحقاً',
                          active: widget.isLater,
                          onFocused: widget.onHeroFocused,
                          onArrowRight: () =>
                              _focusAndTop(_favoriteFocus),
                          onArrowLeft: () =>
                              _focusAndTop(_downloadFocus),
                          onArrowUp: () =>
                              _focusAndTop(_backFocus),
                          onArrowDown: () =>
                              _focusAndTop(_downloadFocus),
                          onPressed: widget.onLater,
                        ),
                        const SizedBox(width: 9),
                        _HeroAction(
                          focusNode: _downloadFocus,
                          icon: widget.isDownloaded
                              ? Icons.download_done_rounded
                              : Icons.download_rounded,
                          label: widget.isDownloading
                              ? '${(widget.downloadProgress * 100).round()}%'
                              : widget.isDownloaded
                                  ? 'منزّل'
                                  : 'تنزيل',
                          active:
                              widget.isDownloaded || widget.isDownloading,
                          onFocused: widget.onHeroFocused,
                          onArrowRight: () =>
                              _focusAndTop(_laterFocus),
                          onArrowUp: () =>
                              _focusAndTop(_playFocus),
                          onArrowDown: media.isSeries &&
                                  widget.seasons.isNotEmpty
                              ? () {
                                  widget.onHeroFocused();
                                  _seriesKey.currentState
                                      ?.focusFirstEpisode();
                                }
                              : null,
                          onPressed: widget.onDownload,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  _CreditsLine(
                    title: 'الإخراج',
                    names: (details?.directors ?? const [])
                        .map((person) => person.name)
                        .take(3)
                        .toList(),
                  ),
                  const SizedBox(height: 9),
                  _CreditsLine(
                    title: 'الكتابة',
                    names: (details?.writers ?? const [])
                        .map((person) => person.name)
                        .take(3)
                        .toList(),
                  ),
                  const SizedBox(height: 9),
                  _CreditsLine(
                    title: 'بطولة',
                    names: (details?.cast ?? const [])
                        .map((person) => person.name)
                        .take(4)
                        .toList(),
                  ),
                ],
              ),
            ),

            if (media.isSeries && widget.seasons.isNotEmpty)
              Positioned(
                left: 34,
                top: 72,
                bottom: 56,
                width: 520,
                child: _SeriesSidePanel(
                  key: _seriesKey,
                  seasons: widget.seasons,
                  seasonIndex: widget.seasonIndex,
                  onSeasonChanged: widget.onSeasonChanged,
                  onEpisode: widget.onEpisode,
                  onEpisodeDownload: widget.onEpisodeDownload,
                  initialEpisode: widget.initialEpisode,
                  onLeaveUp: () => _focusAndTop(_downloadFocus),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xA5141212),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 6),
          Text(
            text,
            textDirection: TextDirection.rtl,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroAction extends StatelessWidget {
  const _HeroAction({
    required this.icon,
    required this.label,
    required this.active,
    required this.onPressed,
    required this.focusNode,
    required this.onFocused,
    this.onArrowUp,
    this.onArrowDown,
    this.onArrowLeft,
    this.onArrowRight,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onPressed;
  final FocusNode focusNode;
  final VoidCallback onFocused;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowRight;

  @override
  Widget build(BuildContext context) {
    return TvFocus(
      focusNode: focusNode,
      onFocused: onFocused,
      onArrowUp: onArrowUp,
      onArrowDown: onArrowDown,
      onArrowLeft: onArrowLeft,
      onArrowRight: onArrowRight,
      onPressed: onPressed,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: active
              ? TvColors.red.withOpacity(.22)
              : const Color(0xA3141212),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: active
                ? TvColors.red.withOpacity(.75)
                : Colors.white12,
          ),
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            Icon(icon, size: 21),
            const SizedBox(width: 7),
            Text(
              label,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreditsLine extends StatelessWidget {
  const _CreditsLine({
    required this.title,
    required this.names,
  });

  final String title;
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      width: double.infinity,
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              title,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              names.join('  •  '),
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeriesSidePanel extends StatefulWidget {
  const _SeriesSidePanel({
    super.key,
    required this.seasons,
    required this.seasonIndex,
    required this.onSeasonChanged,
    required this.onEpisode,
    required this.onEpisodeDownload,
    required this.initialEpisode,
    required this.onLeaveUp,
  });

  final List<SeasonGroup> seasons;
  final int seasonIndex;
  final ValueChanged<int> onSeasonChanged;
  final ValueChanged<Episode> onEpisode;
  final ValueChanged<Episode> onEpisodeDownload;
  final int? initialEpisode;
  final VoidCallback onLeaveUp;

  @override
  State<_SeriesSidePanel> createState() => _SeriesSidePanelState();
}

class _SeriesSidePanelState extends State<_SeriesSidePanel> {
  final ScrollController _episodeScroll = ScrollController();
  final List<FocusNode> _episodeNodes = <FocusNode>[];
  final List<FocusNode> _downloadNodes = <FocusNode>[];
  final List<FocusNode> _seasonNodes = <FocusNode>[];

  SeasonGroup get _selected =>
      widget.seasons[
        widget.seasonIndex.clamp(0, widget.seasons.length - 1)
      ];

  void focusFirstEpisode() {
    if (_episodeNodes.isEmpty) return;
    _episodeNodes.first.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    _syncNodes();
  }

  @override
  void didUpdateWidget(covariant _SeriesSidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncNodes();
  }

  void _syncNodes() {
    final episodeCount = _selected.episodes.length;
    while (_episodeNodes.length < episodeCount) {
      _episodeNodes.add(
        FocusNode(debugLabel: 'details-episode-${_episodeNodes.length}'),
      );
    }
    while (_episodeNodes.length > episodeCount) {
      _episodeNodes.removeLast().dispose();
    }

    while (_downloadNodes.length < episodeCount) {
      _downloadNodes.add(
        FocusNode(debugLabel: 'details-episode-download-${_downloadNodes.length}'),
      );
    }
    while (_downloadNodes.length > episodeCount) {
      _downloadNodes.removeLast().dispose();
    }

    while (_seasonNodes.length < widget.seasons.length) {
      _seasonNodes.add(
        FocusNode(debugLabel: 'details-season-${_seasonNodes.length}'),
      );
    }
    while (_seasonNodes.length > widget.seasons.length) {
      _seasonNodes.removeLast().dispose();
    }
  }

  void _focusEpisode(int index) {
    if (_episodeNodes.isEmpty) return;
    final safe = index.clamp(0, _episodeNodes.length - 1);
    _episodeNodes[safe].requestFocus();
  }

  void _focusDownload(int index) {
    if (_downloadNodes.isEmpty) return;
    final safe = index.clamp(0, _downloadNodes.length - 1);
    _downloadNodes[safe].requestFocus();
  }

  void _selectSeason(int index) {
    widget.onSeasonChanged(index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncNodes();
      _focusEpisode(0);
    });
  }

  @override
  void dispose() {
    _episodeScroll.dispose();
    for (final node in _episodeNodes) {
      node.dispose();
    }
    for (final node in _downloadNodes) {
      node.dispose();
    }
    for (final node in _seasonNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x82070707),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withOpacity(.075),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: tvIsWindowsDesktop ? 74 : 62,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 9),
              scrollDirection: Axis.horizontal,
              itemCount: widget.seasons.length,
              separatorBuilder: (_, __) => const SizedBox(width: 9),
              itemBuilder: (context, index) {
                final active = index == widget.seasonIndex;

                return TvFocus(
                  focusNode: _seasonNodes[index],
                  autofocus: active && widget.initialEpisode == null,
                  onArrowUp: widget.onLeaveUp,
                  onArrowDown: () => _focusEpisode(0),
                  onPressed: () => _selectSeason(index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 17,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? TvColors.red
                          : Colors.white.withOpacity(.07),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: active
                            ? TvColors.red
                            : Colors.white.withOpacity(.05),
                      ),
                    ),
                    child: Text(
                      'الموسم ${widget.seasons[index].number}',
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                GridView.builder(
                  controller: _episodeScroll,
                  primary: false,
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 92),
                  gridDelegate:
                      SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisExtent: tvIsWindowsDesktop ? 340 : 278,
                    crossAxisSpacing: tvIsWindowsDesktop ? 18 : 13,
                    mainAxisSpacing: tvIsWindowsDesktop ? 20 : 15,
                  ),
                  itemCount: selected.episodes.length,
                  itemBuilder: (context, index) {
                    final episode = selected.episodes[index];

                    // TV navigation for the two-column episode grid:
                    // DOWN: episode -> its download -> next row episode.
                    // LEFT/RIGHT: move between neighboring episode cards.
                    final next = index + 1;
                    final previous = index - 1;
                    final nextRow = index + 2;
                    final previousRow = index - 2;

                    return SizedBox(
                      height: tvIsWindowsDesktop ? 340 : 278,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: TvFocus(
                              focusNode: _episodeNodes[index],
                              autofocus: false,
                              onArrowLeft: next < selected.episodes.length
                                  ? () => _focusEpisode(next)
                                  : null,
                              onArrowRight: previous >= 0
                                  ? () => _focusEpisode(previous)
                                  : null,
                              onArrowDown: () => _focusDownload(index),
                              onArrowUp: () {
                                if (previousRow >= 0) {
                                  _focusDownload(previousRow);
                                } else {
                                  _seasonNodes[
                                    widget.seasonIndex.clamp(
                                      0,
                                      _seasonNodes.length - 1,
                                    )
                                  ].requestFocus();
                                }
                              },
                              onPressed: () => widget.onEpisode(episode),
                              borderRadius: 18,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  TvImage(
                                    episode.posterUrl,
                                    cacheWidth: 420,
                                    borderRadius: 18,
                                    fit: BoxFit.cover,
                                  ),
                                  const DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        colors: [
                                          Color(0xD8000000),
                                          Color(0x59000000),
                                          Colors.transparent,
                                        ],
                                        stops: [0, .34, 1],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 10,
                                    left: 10,
                                    child: TvFocus(
                                      focusNode: _downloadNodes[index],
                                      onArrowUp: () => _focusEpisode(index),
                                      onArrowDown: nextRow < selected.episodes.length
                                          ? () => _focusEpisode(nextRow)
                                          : null,
                                      onArrowLeft: next < selected.episodes.length
                                          ? () => _focusDownload(next)
                                          : null,
                                      onArrowRight: previous >= 0
                                          ? () => _focusDownload(previous)
                                          : null,
                                      onPressed: () => widget.onEpisodeDownload(episode),
                                      borderRadius: 12,
                                      child: Container(
                                        width: 46,
                                        height: 46,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: const Color(0xD9151212),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Colors.white.withOpacity(.15),
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Colors.black45,
                                              blurRadius: 10,
                                              offset: Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.download_rounded,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 10,
                                    bottom: 10,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: TvColors.red,
                                        borderRadius: BorderRadius.circular(99),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Colors.black54,
                                            blurRadius: 10,
                                            offset: Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        'الحلقة ${episode.episodeNumber}',
                                        textDirection: TextDirection.rtl,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 96,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Color(0xF3070707),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _CastSection extends StatelessWidget {
  const _CastSection({required this.cast});

  final List<Person> cast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 0, 26, 38),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'طاقم العمل',
            textAlign: TextAlign.right,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: tvIsWindowsDesktop ? 154 : 122,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cast.take(14).length,
              separatorBuilder: (_, __) => const SizedBox(width: 15),
              itemBuilder: (context, index) {
                final person = cast[index];
                return Container(
                  width: tvIsWindowsDesktop ? 260 : 210,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.045),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      SizedBox(
                        width: tvIsWindowsDesktop ? 82 : 66,
                        height: tvIsWindowsDesktop ? 116 : 92,
                        child: TvImage(
                          person.imageUrl,
                          cacheWidth: 150,
                          borderRadius: 11,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          person.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Bundle {
  const _Bundle({
    required this.details,
    required this.seasons,
    required this.recommendations,
  });

  final ContentDetails? details;
  final List<SeasonGroup> seasons;
  final List<MediaItem> recommendations;
}
