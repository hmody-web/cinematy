import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/download_item.dart';
import '../../data/models/episode.dart';
import '../../data/models/media_item.dart';
import '../../data/models/video_source.dart';
import '../../data/services/cinemana_api.dart';
import '../../data/stores/library_store.dart';
import '../../providers.dart';
import '../../widgets/network_image.dart';
import '../../widgets/shimmer.dart';
import '../library/subtitle_settings_screen.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({
    super.key,
    required this.media,
    this.localPath,
  });

  final MediaItem media;
  final String? localPath;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  late final Player _player;
  Player? _previewPlayer;
  late final VideoController _controller;
  late final CinemanaApi _api;
  late final LibraryStore _libraryStore;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _bufferingSub;
  Timer? _hideTimer;
  Timer? _previewTimer;
  Timer? _progressTimer;
  Timer? _previewDisposeTimer;
  Timer? _seekFeedbackTimer;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _previewPosition = Duration.zero;
  bool _controls = true;
  bool _loading = true;
  bool _buffering = false;
  bool _scrubbing = false;
  bool _previewReady = false;
  bool _switchingSource = false;
  bool _navigatingNext = false;
  String? _error;
  Uint8List? _previewBytes;

  final LinkedHashMap<int, Uint8List> _previewCache =
      LinkedHashMap<int, Uint8List>();
  static const int _previewCacheLimit = 14;
  int _previewGeneration = 0;
  bool _previewCaptureBusy = false;
  Duration? _pendingPreviewTarget;
  DateTime? _lastPreviewCaptureAt;

  List<VideoSource> _sources = const <VideoSource>[];
  List<SubtitleSource> _subtitles = const <SubtitleSource>[];
  VideoSource? _selectedSource;
  SubtitleSource? _selectedSubtitle;
  String? _currentMediaUrl;

  BoxFit _videoFit = BoxFit.contain;
  double _playbackRate = 1.0;

  String? _seekFeedback;
  Alignment _seekFeedbackAlignment = Alignment.center;
  int _seekFeedbackSerial = 0;

  List<SeasonGroup> _seasons = const <SeasonGroup>[];
  bool _episodesLoading = false;
  Episode? _nextEpisode;
  bool _nextEpisodeVisible = false;
  double _nextEpisodeProgress = 0;
  bool _nextEpisodeDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _api = ref.read(apiProvider);
    _libraryStore = ref.read(libraryProvider);
    _player = Player();
    _controller = VideoController(_player);

    _positionSub = _player.stream.position.listen((value) {
      if (!mounted || _scrubbing || _switchingSource) return;
      setState(() => _position = value);
      _handleNearEnd(value);
      if (_duration.inMilliseconds > 0 &&
          value.inMilliseconds >= (_duration.inMilliseconds * .985)) {
        _libraryStore.clearProgress(widget.media.id);
      }
    });

    _durationSub = _player.stream.duration.listen((value) {
      if (!mounted || _switchingSource) return;
      setState(() => _duration = value);
    });

    _bufferingSub = _player.stream.buffering.listen((value) {
      if (mounted) setState(() => _buffering = value);
    });

    _progressTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _persistProgress(),
    );

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(
      const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
    );

    if (widget.media.isSeries) _loadEpisodes();
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _persistProgress();
    }
  }

  Future<void> _load() async {
    try {
      if (widget.localPath?.isNotEmpty == true) {
        _currentMediaUrl = widget.localPath!;
        await _player.open(Media(widget.localPath!), play: true);
        await _preparePreview(widget.localPath!);

        final downloaded = ref.read(downloadProvider).itemFor(widget.media.id);
        _subtitles = _localSubtitleSources(downloaded);
        if (_subtitles.isEmpty) {
          try {
            _subtitles = await _api.subtitles(widget.media.id);
          } catch (_) {}
        }
      } else {
        final values = await Future.wait<dynamic>([
          _api.videoSources(widget.media.id),
          _api.subtitles(widget.media.id).catchError(
                (_) => <SubtitleSource>[],
              ),
        ]);
        _sources = values[0] as List<VideoSource>;
        _subtitles = values[1] as List<SubtitleSource>;
        if (_sources.isEmpty) {
          throw Exception('لم يرجع المصدر رابط تشغيل صالح');
        }
        _selectedSource = _bestSource(_sources);
        await _openSource(
          _selectedSource!,
          preservePosition: false,
          forcePlay: true,
        );
      }

      await _selectArabicByDefault();
      await _player.setRate(_playbackRate);

      final progress = _libraryStore.watchProgress(widget.media.id);
      if (progress != null &&
          progress.positionMs >= 5000 &&
          progress.ratio < .97) {
        final target = Duration(milliseconds: progress.positionMs);
        await _player.seek(target);
        _position = target;
      }

      _scheduleHide();
      if (mounted) {
        setState(() {
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  List<SubtitleSource> _localSubtitleSources(DownloadItem? item) {
    if (item == null || item.subtitles.isEmpty) return const <SubtitleSource>[];
    return item.subtitles
        .where((sub) => File(sub.localPath).existsSync())
        .map(
          (sub) => SubtitleSource(
            url: Uri.file(sub.localPath).toString(),
            language: sub.language,
            label: sub.label,
          ),
        )
        .toList();
  }

  Future<void> _loadEpisodes() async {
    if (_episodesLoading) return;
    _episodesLoading = true;
    if (mounted) setState(() {});
    try {
      final data = await _api.seasonsFor(
        widget.media,
        detailsRaw: widget.media.raw,
      );
      if (!mounted) return;
      setState(() {
        _seasons = data;
        _nextEpisode = _findNextEpisode(data);
      });
    } catch (_) {
      if (mounted) setState(() => _seasons = const <SeasonGroup>[]);
    } finally {
      _episodesLoading = false;
      if (mounted) setState(() {});
    }
  }

  Episode? _findNextEpisode(List<SeasonGroup> seasons) {
    final flat = seasons.expand((s) => s.episodes).toList();
    if (flat.isEmpty) return null;
    var index = flat.indexWhere((e) => e.id == widget.media.id);
    if (index < 0) {
      index = flat.indexWhere(
        (e) =>
            e.seasonNumber == (widget.media.season ?? -1) &&
            e.episodeNumber == (widget.media.episode ?? -1),
      );
    }
    if (index >= 0 && index + 1 < flat.length) return flat[index + 1];
    return null;
  }

  Future<void> _preparePreview(String url) async {
    _previewDisposeTimer?.cancel();
    _previewReady = false;
    _previewCache.clear();
    _previewGeneration++;
    _pendingPreviewTarget = null;
    _previewCaptureBusy = false;
    _lastPreviewCaptureAt = null;
    final old = _previewPlayer;
    _previewPlayer = null;
    if (old != null) {
      try {
        await old.dispose();
      } catch (_) {}
    }
  }

  Future<Player?> _ensurePreviewPlayer() async {
    if (_previewPlayer != null && _previewReady) return _previewPlayer;
    final url = _currentMediaUrl;
    if (url == null || url.isEmpty) return null;
    try {
      final player = Player();
      _previewPlayer = player;
      await player.open(Media(url), play: false);
      await player.setVolume(0);
      _previewReady = true;
      return player;
    } catch (_) {
      _previewReady = false;
      try {
        await _previewPlayer?.dispose();
      } catch (_) {}
      _previewPlayer = null;
      return null;
    }
  }

  Future<void> _selectArabicByDefault() async {
    if (_subtitles.isEmpty) return;
    SubtitleSource? arabic;
    for (final sub in _subtitles) {
      final label = '${sub.label} ${sub.language} ${sub.url}'.toLowerCase();
      if (label.contains('arab') ||
          label.contains('عرب') ||
          label.contains('_ar.') ||
          label.contains('/ar/') ||
          label.endsWith(' ar')) {
        arabic = sub;
        break;
      }
    }
    arabic ??= _subtitles.first;
    _selectedSubtitle = arabic;
    await _applySubtitle(arabic);
  }

  Future<void> _applySubtitle(SubtitleSource source) async {
    await _player.setSubtitleTrack(
      SubtitleTrack.uri(
        source.url,
        title: _subtitleLabel(source, _subtitles.indexOf(source)),
        language: source.language,
      ),
    );
  }

  VideoSource _bestSource(List<VideoSource> sources) {
    int score(VideoSource s) {
      final q = '${s.quality} ${s.resolution}'.toLowerCase();
      if (q.contains('2160')) return 2160;
      if (q.contains('1440')) return 1440;
      if (q.contains('1080')) return 1080;
      if (q.contains('720')) return 720;
      if (q.contains('480')) return 480;
      if (q.contains('360')) return 360;
      return 1;
    }

    final copy = [...sources]..sort((a, b) => score(b).compareTo(score(a)));
    return copy.first;
  }

  Future<void> _openSource(
    VideoSource source, {
    required bool preservePosition,
    bool forcePlay = false,
  }) async {
    final oldPosition = preservePosition ? _player.state.position : Duration.zero;
    final wasPlaying = forcePlay || _player.state.playing;
    final subtitle = _selectedSubtitle;

    _switchingSource = true;
    if (mounted) setState(() {});
    try {
      _currentMediaUrl = source.url;
      await _player.open(Media(source.url), play: false);
      await _preparePreview(source.url);

      if (oldPosition > Duration.zero) {
        await _player.seek(oldPosition);
      }
      await _player.setRate(_playbackRate);
      if (subtitle != null) {
        try {
          await _applySubtitle(subtitle);
        } catch (_) {}
      }
      if (wasPlaying) {
        await _player.play();
      } else {
        await _player.pause();
      }

      if (mounted) {
        setState(() {
          _position = oldPosition;
          _selectedSource = source;
        });
      }
    } finally {
      _switchingSource = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _persistProgress() async {
    if (_duration.inMilliseconds <= 0 || _position.inMilliseconds <= 0) return;
    if (_position.inMilliseconds >= (_duration.inMilliseconds * .97)) {
      await _libraryStore.clearProgress(widget.media.id);
    } else {
      await _libraryStore.saveProgress(widget.media, _position, _duration);
    }
  }

  void _toggleControls() {
    if (!mounted) return;
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted &&
          _player.state.playing &&
          !_scrubbing &&
          !_nextEpisodeVisible) {
        setState(() => _controls = false);
      }
    });
  }

  Future<void> _seekRelative(int seconds) async {
    final max = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds
        : _position.inMilliseconds + 10000;
    final target = (_position.inMilliseconds + seconds * 1000)
        .clamp(0, max)
        .toInt();
    await _player.seek(Duration(milliseconds: target));
    if (mounted) setState(() => _position = Duration(milliseconds: target));
    _scheduleHide();
  }

  void _doubleTapAt(TapDownDetails details) {
    final width = MediaQuery.sizeOf(context).width;
    final isRight = details.localPosition.dx > width / 2;
    // نحافظ على السلوك المتعارف عليه في المشغلات: يمين = تقديم، يسار = رجوع
    // حتى لو كانت واجهة التطبيق RTL.
    final seconds = isRight ? 10 : -10;
    _seekRelative(seconds);
    _showSeekFeedback(
      seconds > 0 ? '+10 ثانية' : '-10 ثانية',
      isRight ? Alignment.centerRight : Alignment.centerLeft,
    );
  }

  void _showSeekFeedback(String text, Alignment alignment) {
    _seekFeedbackTimer?.cancel();
    setState(() {
      _seekFeedback = text;
      _seekFeedbackAlignment = alignment;
      _seekFeedbackSerial++;
      _controls = true;
    });
    _seekFeedbackTimer = Timer(const Duration(milliseconds: 780), () {
      if (mounted) setState(() => _seekFeedback = null);
    });
  }

  void _previewAt(double value) {
    final target = Duration(milliseconds: value.toInt());
    setState(() {
      _position = target;
      _previewPosition = target;
      _scrubbing = true;
      _controls = true;
    });

    final bucket = target.inSeconds ~/ 4;
    final cached = _previewCache.remove(bucket);
    if (cached != null) {
      _previewCache[bucket] = cached;
      setState(() => _previewBytes = cached);
    }

    _pendingPreviewTarget = target;
    _schedulePreviewCapture();
  }

  void _schedulePreviewCapture() {
    if (!_scrubbing || _previewCaptureBusy || _previewTimer?.isActive == true) {
      return;
    }
    final now = DateTime.now();
    final sinceLast = _lastPreviewCaptureAt == null
        ? 999
        : now.difference(_lastPreviewCaptureAt!).inMilliseconds;
    final waitMs = (90 - sinceLast).clamp(0, 90).toInt();
    _previewTimer = Timer(Duration(milliseconds: waitMs), _drainPreviewCapture);
  }

  Future<void> _drainPreviewCapture() async {
    if (!_scrubbing || _previewCaptureBusy) return;
    final target = _pendingPreviewTarget;
    if (target == null) return;
    _pendingPreviewTarget = null;
    _previewCaptureBusy = true;
    final generation = _previewGeneration;
    final bucket = target.inSeconds ~/ 4;

    try {
      final cached = _previewCache.remove(bucket);
      if (cached != null) {
        _previewCache[bucket] = cached;
        if (mounted &&
            _scrubbing &&
            generation == _previewGeneration &&
            (_previewPosition.inSeconds ~/ 4) == bucket) {
          setState(() => _previewBytes = cached);
        }
        return;
      }

      final previewPlayer = await _ensurePreviewPlayer();
      if (previewPlayer == null ||
          !_scrubbing ||
          generation != _previewGeneration) {
        return;
      }

      await previewPlayer.seek(target);
      await Future<void>.delayed(const Duration(milliseconds: 42));
      if (!_scrubbing || generation != _previewGeneration) return;
      final bytes = await previewPlayer.screenshot(format: 'image/jpeg');
      if (bytes == null || bytes.isEmpty) return;

      _previewCache[bucket] = bytes;
      while (_previewCache.length > _previewCacheLimit) {
        _previewCache.remove(_previewCache.keys.first);
      }
      if (mounted &&
          _scrubbing &&
          generation == _previewGeneration &&
          (_previewPosition.inSeconds ~/ 4) == bucket) {
        setState(() => _previewBytes = bytes);
      }
    } catch (_) {
      // المعاينة ميزة مساعدة ولا ينبغي أن تؤثر على التشغيل الأساسي.
    } finally {
      _previewCaptureBusy = false;
      _lastPreviewCaptureAt = DateTime.now();
      if (_scrubbing && _pendingPreviewTarget != null) {
        _schedulePreviewCapture();
      }
    }
  }

  Future<void> _finishScrub(double value) async {
    _previewTimer?.cancel();
    _previewGeneration++;
    _pendingPreviewTarget = null;
    final target = Duration(milliseconds: value.toInt());
    await _player.seek(target);
    if (mounted) {
      setState(() {
        _position = target;
        _scrubbing = false;
        _previewBytes = null;
      });
    }
    _previewDisposeTimer?.cancel();
    _previewDisposeTimer = Timer(const Duration(seconds: 5), () async {
      final player = _previewPlayer;
      _previewPlayer = null;
      _previewReady = false;
      if (player != null) {
        try {
          await player.dispose();
        } catch (_) {}
      }
    });
    _handleNearEnd(target);
    _scheduleHide();
  }

  void _handleNearEnd(Duration position) {
    final next = _nextEpisode;
    if (next == null || _duration.inMilliseconds <= 0) {
      _hideNextEpisodeCountdown();
      return;
    }

    final remainingMs = _duration.inMilliseconds - position.inMilliseconds;
    final shouldShow = position > Duration.zero &&
        remainingMs >= 0 &&
        remainingMs <= 10000;

    if (!shouldShow) {
      _nextEpisodeDismissed = false;
      _hideNextEpisodeCountdown();
      return;
    }
    if (_nextEpisodeDismissed) return;

    final progress = ((10000 - remainingMs) / 10000)
        .clamp(0.0, 1.0)
        .toDouble();
    if (!_nextEpisodeVisible) {
      setState(() {
        _nextEpisodeVisible = true;
        _nextEpisodeProgress = progress;
        _controls = true;
      });
    } else if ((_nextEpisodeProgress - progress).abs() >= .004) {
      setState(() => _nextEpisodeProgress = progress);
    }

    // التقدم مربوط بزمن الفيديو نفسه: يتوقف إذا توقف الفيديو أو حدث buffering،
    // ولا يسبق نهاية الحلقة بسبب مؤقت مستقل عن المشغل.
    if (progress >= .995 && !_navigatingNext) {
      _goToNextEpisode();
    }
  }

  void _hideNextEpisodeCountdown() {
    if (mounted && (_nextEpisodeVisible || _nextEpisodeProgress != 0)) {
      setState(() {
        _nextEpisodeVisible = false;
        _nextEpisodeProgress = 0;
      });
    }
  }

  void _dismissNextEpisodeCountdown() {
    _nextEpisodeDismissed = true;
    _hideNextEpisodeCountdown();
  }

  Future<void> _goToNextEpisode() async {
    final next = _nextEpisode;
    if (next == null || _navigatingNext || !mounted) return;
    _navigatingNext = true;
    await _persistProgress();
    if (!mounted) return;
    _goToEpisode(next);
  }

  void _goToEpisode(Episode episode) {
    if (!mounted) return;
    final media = _episodeMedia(episode);
    final downloaded = ref.read(downloadProvider).itemFor(episode.id);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          media: media,
          localPath: downloaded?.localPath,
        ),
      ),
    );
  }

  MediaItem _episodeMedia(Episode episode) {
    final seriesTitle = (widget.media.raw['_seriesTitle'] ?? '')
        .toString()
        .trim();
    final fallbackSeriesTitle = widget.media.title.split('•').first.trim();
    final title = seriesTitle.isNotEmpty ? seriesTitle : fallbackSeriesTitle;
    return MediaItem(
      id: episode.id,
      title: '$title • ${episode.title}',
      description: episode.description,
      posterUrl: episode.posterUrl.isNotEmpty
          ? episode.posterUrl
          : widget.media.posterUrl,
      backdropUrl: widget.media.backdropUrl,
      isSeries: true,
      season: episode.seasonNumber,
      episode: episode.episodeNumber,
      raw: {
        ...widget.media.raw,
        ...episode.raw,
        '_seriesTitle': title,
      },
    );
  }

  void _cycleFit() {
    setState(() {
      if (_videoFit == BoxFit.contain) {
        _videoFit = BoxFit.cover;
      } else if (_videoFit == BoxFit.cover) {
        _videoFit = BoxFit.fill;
      } else {
        _videoFit = BoxFit.contain;
      }
      _controls = true;
    });
    _scheduleHide();
  }

  String get _fitLabel {
    if (_videoFit == BoxFit.cover) return 'ملء وقص';
    if (_videoFit == BoxFit.fill) return 'تمديد';
    return 'احتواء';
  }

  IconData get _fitIcon {
    if (_videoFit == BoxFit.cover) return Icons.crop_16_9_rounded;
    if (_videoFit == BoxFit.fill) return Icons.aspect_ratio_rounded;
    return Icons.fit_screen_rounded;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _previewTimer?.cancel();
    _progressTimer?.cancel();
    _previewDisposeTimer?.cancel();
    _seekFeedbackTimer?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferingSub?.cancel();
    _persistProgress();
    _previewPlayer?.dispose();
    _player.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = ref.watch(subtitleSettingsProvider);
    final shadowColor = subtitle.outlineColor.withOpacity(subtitle.outlineOpacity);
    final shadows = List<Shadow>.generate(
      subtitle.outlineWidth <= 0 ? 0 : 8,
      (i) {
        final a = i * 0.785398;
        final d = subtitle.outlineWidth;
        return Shadow(
          color: shadowColor,
          blurRadius: .45,
          offset: Offset(d * _cos(a), d * _sin(a)),
        );
      },
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onDoubleTapDown: _doubleTapAt,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: Video(
                key: ValueKey(_videoFit),
                controller: _controller,
                fit: _videoFit,
                controls: NoVideoControls,
                subtitleViewConfiguration: SubtitleViewConfiguration(
                  style: TextStyle(
                    fontFamily: subtitle.fontFamily,
                    fontSize: subtitle.fontSize,
                    color: subtitle.textColor,
                    height: 1.35,
                    shadows: shadows,
                    backgroundColor: subtitle.backgroundEnabled
                        ? subtitle.backgroundColor.withOpacity(
                            subtitle.backgroundOpacity,
                          )
                        : Colors.transparent,
                  ),
                  textAlign: TextAlign.center,
                  padding: const EdgeInsets.fromLTRB(32, 24, 32, 42),
                ),
              ),
            ),
            if (_loading || _switchingSource)
              _PlayerLoadingOverlay(
                label: _switchingSource
                    ? 'جاري تبديل الجودة بدون فقدان موضعك…'
                    : 'جاري تجهيز المشاهدة…',
              )
            else if (_buffering && _error == null)
              const _PlayerBufferingHint(),
            if (_error != null) _ErrorOverlay(onRetry: _retry),
            _DoubleTapFeedback(
              text: _seekFeedback,
              alignment: _seekFeedbackAlignment,
              serial: _seekFeedbackSerial,
            ),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: _controls ? 1 : 0,
              child: IgnorePointer(
                ignoring: !_controls,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xBC000000),
                        Color(0x08000000),
                        Color(0xBC000000),
                      ],
                      stops: [0, .48, 1],
                    ),
                  ),
                  child: SafeArea(
                    child: Column(
                      children: [
                        _buildTopControls(),
                        const Spacer(),
                        _buildCenterControls(),
                        const Spacer(),
                        _buildBottomControls(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_nextEpisodeVisible && _nextEpisode != null)
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 22, bottom: 74),
                    child: _NextEpisodeButton(
                      episode: _nextEpisode!,
                      progress: _nextEpisodeProgress,
                      onTap: _goToNextEpisode,
                      onCancel: _dismissNextEpisodeCountdown,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _retry() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await _load();
  }

  Widget _buildTopControls() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Row(
            children: [
              _TinyPlayerAction(
                icon: Icons.arrow_forward_ios_rounded,
                tooltip: 'رجوع',
                onTap: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.media.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    if (widget.media.isSeries &&
                        ((widget.media.season ?? 0) > 0 ||
                            (widget.media.episode ?? 0) > 0))
                      Text(
                        [
                          if ((widget.media.season ?? 0) > 0)
                            'الموسم ${widget.media.season}',
                          if ((widget.media.episode ?? 0) > 0)
                            'الحلقة ${widget.media.episode}',
                        ].join(' • '),
                        style: TextStyle(
                          color: Colors.white.withOpacity(.52),
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.media.isSeries)
                _TinyPlayerAction(
                  icon: Icons.video_library_rounded,
                  tooltip: 'الحلقات والمواسم',
                  onTap: _showEpisodes,
                ),
              _TinyPlayerAction(
                icon: Icons.subtitles_rounded,
                tooltip: 'الترجمة',
                onTap: _showSubtitles,
              ),
              _TinyPlayerAction(
                icon: Icons.text_fields_rounded,
                tooltip: 'شكل الترجمة',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SubtitleSettingsScreen(),
                  ),
                ),
              ),
              _SpeedAction(
                rate: _playbackRate,
                onTap: _showSpeed,
              ),
              _TinyPlayerAction(
                icon: _fitIcon,
                tooltip: 'طريقة عرض الفيديو: $_fitLabel',
                onTap: _cycleFit,
              ),
              if (widget.localPath == null)
                _TinyPlayerAction(
                  icon: Icons.high_quality_rounded,
                  tooltip: 'الجودة',
                  onTap: _showQuality,
                ),
            ],
          ),
        ),
      );

  Widget _buildCenterControls() => Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _RoundPlayerButton(
              icon: Icons.replay_10_rounded,
              size: 52,
              onTap: () {
                _seekRelative(-10);
                _showSeekFeedback('-10 ثانية', Alignment.centerLeft);
              },
            ),
            const SizedBox(width: 28),
            StreamBuilder<bool>(
              stream: _player.stream.playing,
              initialData: _player.state.playing,
              builder: (_, snap) => _RoundPlayerButton(
                icon: snap.data == true
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 72,
                filled: true,
                onTap: () {
                  _player.playOrPause();
                  _scheduleHide();
                },
              ),
            ),
            const SizedBox(width: 28),
            _RoundPlayerButton(
              icon: Icons.forward_10_rounded,
              size: 52,
              onTap: () {
                _seekRelative(10);
                _showSeekFeedback('+10 ثانية', Alignment.centerRight);
              },
            ),
          ],
        ),
      );

  Widget _buildBottomControls() => Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
        child: Column(
          children: [
            _ProgressScrubber(
              position: _position,
              duration: _duration,
              scrubbing: _scrubbing,
              previewBytes: _previewBytes,
              previewPosition: _previewPosition,
              fallback: widget.media.backdropUrl.isNotEmpty
                  ? widget.media.backdropUrl
                  : widget.media.posterUrl,
              onChanged: _previewAt,
              onChangeEnd: _finishScrub,
            ),
            const SizedBox(height: 3),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                children: [
                  Text(
                    '${formatDuration(_position)} / ${formatDuration(_duration)}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_playbackRate.toStringAsFixed(_playbackRate == _playbackRate.roundToDouble() ? 0 : 2)}x • $_fitLabel',
                    style: TextStyle(
                      color: Colors.white.withOpacity(.48),
                      fontSize: 10.5,
                    ),
                  ),
                  if (_selectedSource != null) ...[
                    const SizedBox(width: 10),
                    Text(
                      _selectedSource!.quality,
                      style: TextStyle(
                        color: Colors.white.withOpacity(.68),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  double _sin(double x) {
    const v = [0.0, .7071, 1.0, .7071, 0.0, -.7071, -1.0, -.7071];
    return v[((x / .785398).round()) % 8];
  }

  double _cos(double x) {
    const v = [1.0, .7071, 0.0, -.7071, -1.0, -.7071, 0.0, .7071];
    return v[((x / .785398).round()) % 8];
  }

  void _showQuality() {
    if (_sources.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _QualitySheet(
        sources: _sources,
        selected: _selectedSource,
        onSelected: (source) async {
          Navigator.pop(context);
          if (source.url == _selectedSource?.url) return;
          await _openSource(source, preservePosition: true);
        },
      ),
    );
  }

  void _showSubtitles() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PlayerSheet(
        title: 'الترجمة',
        subtitle: 'اختر ملف الترجمة بدون إيقاف المشاهدة',
        children: [
          _SheetChoiceTile(
            icon: Icons.subtitles_off_rounded,
            title: 'بدون ترجمة',
            selected: _selectedSubtitle == null,
            onTap: () async {
              Navigator.pop(context);
              setState(() => _selectedSubtitle = null);
              await _player.setSubtitleTrack(SubtitleTrack.no());
            },
          ),
          ..._subtitles.asMap().entries.map((entry) {
            final sub = entry.value;
            final label = _subtitleLabel(sub, entry.key);
            return _SheetChoiceTile(
              icon: Icons.closed_caption_rounded,
              title: label,
              subtitle: sub.url.startsWith('file:')
                  ? 'محفوظة مع التنزيل'
                  : 'ملف ترجمة خارجي',
              selected: _selectedSubtitle?.url == sub.url,
              onTap: () async {
                Navigator.pop(context);
                setState(() => _selectedSubtitle = sub);
                await _applySubtitle(sub);
              },
            );
          }),
        ],
      ),
    );
  }

  void _showSpeed() {
    const speeds = <double>[.5, .75, 1, 1.25, 1.5, 1.75, 2];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlayerSheet(
        title: 'سرعة التشغيل',
        subtitle: 'تتغير فوراً بدون إعادة الفيديو',
        children: speeds
            .map(
              (speed) => _SheetChoiceTile(
                icon: speed == 1
                    ? Icons.speed_rounded
                    : Icons.play_arrow_rounded,
                title: speed == 1 ? 'عادية • 1x' : '${speed}x',
                selected: _playbackRate == speed,
                onTap: () async {
                  Navigator.pop(context);
                  await _player.setRate(speed);
                  if (mounted) setState(() => _playbackRate = speed);
                },
              ),
            )
            .toList(),
      ),
    );
  }

  Future<void> _showEpisodes() async {
    if (_seasons.isEmpty) {
      await _loadEpisodes();
    }
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _EpisodesSheet(
        seasons: _seasons,
        loading: false,
        currentMedia: widget.media,
        onEpisode: (episode) {
          Navigator.pop(context);
          _goToEpisode(episode);
        },
      ),
    );
  }

  String _subtitleLabel(SubtitleSource sub, int index) {
    final raw = '${sub.label} ${sub.language} ${sub.url}'.trim();
    final lower = raw.toLowerCase();
    if (lower.contains('english') ||
        lower.contains('_en.') ||
        lower.contains('/en/') ||
        lower.endsWith(' en')) {
      return 'الإنجليزية';
    }
    if (lower.contains('arab') ||
        lower.contains('عرب') ||
        lower.contains('_ar.') ||
        lower.contains('/ar/') ||
        lower.endsWith(' ar')) {
      final arabicCount = _subtitles.where((s) {
        final x = '${s.label} ${s.language} ${s.url}'.toLowerCase();
        return x.contains('arab') ||
            x.contains('عرب') ||
            x.contains('_ar.') ||
            x.contains('/ar/');
      }).length;
      return arabicCount > 1 ? 'العربية ${index + 1}' : 'العربية';
    }
    return raw.isEmpty
        ? 'ترجمة ${index + 1}'
        : (sub.label.isNotEmpty ? sub.label : sub.language);
  }
}

class _ProgressScrubber extends StatelessWidget {
  const _ProgressScrubber({
    required this.position,
    required this.duration,
    required this.scrubbing,
    required this.previewBytes,
    required this.previewPosition,
    required this.fallback,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final Duration position;
  final Duration duration;
  final Duration previewPosition;
  final bool scrubbing;
  final Uint8List? previewBytes;
  final String fallback;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final maxMs =
        duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
    final value = position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();
    final ratio = (value / maxMs).clamp(0.0, 1.0).toDouble();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: scrubbing ? 146 : 38,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const previewWidth = 184.0;
          final thumbX = constraints.maxWidth * ratio;
          final maxLeft = (constraints.maxWidth - previewWidth)
              .clamp(0.0, double.infinity)
              .toDouble();
          final left = (thumbX - previewWidth / 2)
              .clamp(0.0, maxLeft)
              .toDouble();

          return Stack(
            clipBehavior: Clip.none,
            children: [
              if (scrubbing)
                Positioned(
                  left: left,
                  top: 0,
                  child: _SeekPreview(
                    bytes: previewBytes,
                    position: previewPosition,
                    fallback: fallback,
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Directionality(
                  // مهم: التطبيق RTL لكن قيمة الفيديو زمنية من اليسار إلى اليمين.
                  // هذا يمنع انعكاس الصورة المصغرة والدائرة أثناء السحب.
                  textDirection: TextDirection.ltr,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3.5,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6.5),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 16),
                      activeTrackColor: Colors.white,
                      thumbColor: Colors.white,
                      inactiveTrackColor: Colors.white24,
                      overlayColor: AppColors.redBright.withOpacity(.14),
                    ),
                    child: Slider(
                      min: 0,
                      max: maxMs,
                      value: value,
                      onChanged: onChanged,
                      onChangeEnd: onChangeEnd,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SeekPreview extends StatelessWidget {
  const _SeekPreview({
    required this.bytes,
    required this.position,
    required this.fallback,
  });

  final Uint8List? bytes;
  final Duration position;
  final String fallback;

  @override
  Widget build(BuildContext context) => Container(
        width: 184,
        height: 110,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white.withOpacity(.22)),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 18),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (bytes != null)
              Image.memory(bytes!, fit: BoxFit.cover, gaplessPlayback: true)
            else if (fallback.isNotEmpty)
              CinematyNetworkImage(url: fallback)
            else
              const CinematyShimmer(
                child: ColoredBox(color: Color(0xFF111111)),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54],
                ),
              ),
            ),
            Positioned(
              bottom: 7,
              right: 0,
              left: 0,
              child: Text(
                formatDuration(position),
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
}

class _RoundPlayerButton extends StatelessWidget {
  const _RoundPlayerButton({
    required this.icon,
    required this.size,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final double size;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: IconButton(
              onPressed: onTap,
              style: IconButton.styleFrom(
                backgroundColor: filled
                    ? Colors.white
                    : Colors.white.withOpacity(.12),
                foregroundColor:
                    filled ? AppColors.background : Colors.white,
              ),
              icon: Icon(icon, size: filled ? 38 : 28),
            ),
          ),
        ),
      );
}

class _TinyPlayerAction extends StatelessWidget {
  const _TinyPlayerAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: IconButton(
          onPressed: onTap,
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withOpacity(.075),
            minimumSize: const Size(40, 40),
            padding: EdgeInsets.zero,
          ),
          icon: Icon(icon, size: 20),
        ),
      );
}

class _SpeedAction extends StatelessWidget {
  const _SpeedAction({required this.rate, required this.onTap});
  final double rate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'سرعة التشغيل',
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.white.withOpacity(.075),
            minimumSize: const Size(44, 40),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: Text(
            '${rate.toStringAsFixed(rate == rate.roundToDouble() ? 0 : 2)}x',
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900),
          ),
        ),
      );
}

class _DoubleTapFeedback extends StatelessWidget {
  const _DoubleTapFeedback({
    required this.text,
    required this.alignment,
    required this.serial,
  });

  final String? text;
  final Alignment alignment;
  final int serial;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          child: text == null
              ? const SizedBox.shrink()
              : Align(
                  key: ValueKey(serial),
                  alignment: alignment,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 72),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: .68, end: 1),
                      duration: const Duration(milliseconds: 360),
                      curve: Curves.elasticOut,
                      builder: (_, value, child) => Transform.scale(
                        scale: value,
                        child: child,
                      ),
                      child: Container(
                        width: 108,
                        height: 108,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withOpacity(.42),
                          border: Border.all(color: Colors.white.withOpacity(.16)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.touch_app_rounded, size: 27),
                            const SizedBox(height: 7),
                            Text(
                              text!,
                              textDirection: TextDirection.rtl,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      );
}

class _PlayerLoadingOverlay extends StatelessWidget {
  const _PlayerLoadingOverlay({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 250,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(.55),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.movie_filter_rounded, size: 30),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
              ),
              const SizedBox(height: 12),
              const SkeletonBox(height: 4, radius: 8),
            ],
          ),
        ),
      );
}

class _PlayerBufferingHint extends StatelessWidget {
  const _PlayerBufferingHint();

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 65),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(.55),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 36,
                    child: SkeletonBox(height: 4, radius: 4),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'جاري تجهيز الصورة',
                    style: TextStyle(
                      color: Colors.white.withOpacity(.74),
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _ErrorOverlay extends StatelessWidget {
  const _ErrorOverlay({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xE8121010),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white.withOpacity(.08)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 40),
                const SizedBox(height: 12),
                const Text(
                  'تعذر تشغيل الفيديو',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  'المصدر لم يرجع رابط تشغيل متاح لهذه المادة.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(.55)),
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: onRetry,
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ),
      );
}

class _NextEpisodeButton extends StatelessWidget {
  const _NextEpisodeButton({
    required this.episode,
    required this.progress,
    required this.onTap,
    required this.onCancel,
  });

  final Episode episode;
  final double progress;
  final VoidCallback onTap;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onCancel,
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withOpacity(.55),
            ),
            icon: const Icon(Icons.close_rounded, size: 18),
            tooltip: 'إلغاء الانتقال التلقائي',
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: 225,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xE8181414),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withOpacity(.15)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: FractionallySizedBox(
                        widthFactor: progress.clamp(0.0, 1.0).toDouble(),
                        heightFactor: 1,
                        alignment: Alignment.centerRight,
                        child: ColoredBox(
                          color: AppColors.redBright.withOpacity(.28),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          const Icon(Icons.skip_next_rounded, size: 25),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'الحلقة التالية',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12.5,
                                  ),
                                ),
                                Text(
                                  'ح ${episode.episodeNumber} • الانتقال خلال ${(10 - progress * 10).ceil().clamp(0, 10)} ث',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(.58),
                                    fontSize: 9.5,
                                  ),
                                ),
                              ],
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
        ],
      );
}

class _QualitySheet extends StatelessWidget {
  const _QualitySheet({
    required this.sources,
    required this.selected,
    required this.onSelected,
  });

  final List<VideoSource> sources;
  final VideoSource? selected;
  final ValueChanged<VideoSource> onSelected;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          constraints: const BoxConstraints(maxHeight: 430),
          decoration: BoxDecoration(
            color: const Color(0xF2161212),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withOpacity(.10)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'جودة الفيديو',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'تتبدل الجودة ويستمر الفيلم من نفس الثانية',
                            style: TextStyle(
                              color: Colors.white.withOpacity(.46),
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 190,
                    mainAxisExtent: 88,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: sources.length,
                  itemBuilder: (_, i) {
                    final source = sources[i];
                    final isSelected = selected?.url == source.url;
                    final qualityNumber = int.tryParse(
                      source.quality.replaceAll(RegExp(r'[^0-9]'), ''),
                    );
                    return InkWell(
                      onTap: () => onSelected(source),
                      borderRadius: BorderRadius.circular(18),
                      child: Ink(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.redBright.withOpacity(.13)
                              : Colors.white.withOpacity(.045),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.redBright.withOpacity(.60)
                                : Colors.white.withOpacity(.07),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(.055),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Icon(
                                qualityNumber != null && qualityNumber >= 1080
                                    ? Icons.hd_rounded
                                    : Icons.high_quality_rounded,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    source.quality,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (source.container.isNotEmpty)
                                    Text(
                                      source.container.toUpperCase(),
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(.42),
                                        fontSize: 9.5,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle_rounded,
                                color: AppColors.redBright,
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
}

class _PlayerSheet extends StatelessWidget {
  const _PlayerSheet({
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          constraints: const BoxConstraints(maxHeight: 430),
          decoration: BoxDecoration(
            color: const Color(0xF2161212),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withOpacity(.10)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              style: TextStyle(
                                color: Colors.white.withOpacity(.46),
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
                  children: children,
                ),
              ),
            ],
          ),
        ),
      );
}

class _SheetChoiceTile extends StatelessWidget {
  const _SheetChoiceTile({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.redBright.withOpacity(.12)
                  : Colors.white.withOpacity(.035),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? AppColors.redBright.withOpacity(.48)
                    : Colors.white.withOpacity(.06),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: TextStyle(
                            color: Colors.white.withOpacity(.42),
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.redBright,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      );
}

class _EpisodesSheet extends StatefulWidget {
  const _EpisodesSheet({
    required this.seasons,
    required this.loading,
    required this.currentMedia,
    required this.onEpisode,
  });

  final List<SeasonGroup> seasons;
  final bool loading;
  final MediaItem currentMedia;
  final ValueChanged<Episode> onEpisode;

  @override
  State<_EpisodesSheet> createState() => _EpisodesSheetState();
}

class _EpisodesSheetState extends State<_EpisodesSheet> {
  late int _seasonIndex;

  @override
  void initState() {
    super.initState();
    final currentSeason = widget.currentMedia.season;
    final found = currentSeason == null
        ? -1
        : widget.seasons.indexWhere((s) => s.number == currentSeason);
    _seasonIndex = found >= 0 ? found : 0;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading && widget.seasons.isEmpty) {
      return SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xF2161212),
            borderRadius: BorderRadius.circular(30),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SkeletonBox(height: 18, radius: 8),
              SizedBox(height: 14),
              SkeletonBox(height: 54, radius: 18),
              SizedBox(height: 10),
              SkeletonBox(height: 54, radius: 18),
            ],
          ),
        ),
      );
    }

    if (widget.seasons.isEmpty) {
      return _PlayerSheet(
        title: 'الحلقات والمواسم',
        subtitle: 'المصدر لم يرجع قائمة الحلقات حالياً',
        children: const [
          Padding(
            padding: EdgeInsets.all(18),
            child: Text('لا توجد حلقات متاحة من المصدر لهذه المادة.'),
          ),
        ],
      );
    }

    if (_seasonIndex >= widget.seasons.length) _seasonIndex = 0;
    final current = widget.seasons[_seasonIndex];

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxHeight: 470),
        decoration: BoxDecoration(
          color: const Color(0xF2161212),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withOpacity(.10)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'الحلقات والمواسم',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'أنت الآن في الموسم ${widget.currentMedia.season ?? current.number} • الحلقة ${widget.currentMedia.episode ?? '-'}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(.46),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                scrollDirection: Axis.horizontal,
                itemCount: widget.seasons.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ChoiceChip(
                  selected: i == _seasonIndex,
                  label: Text('الموسم ${widget.seasons[i].number}'),
                  onSelected: (_) => setState(() => _seasonIndex = i),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                itemCount: current.episodes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final episode = current.episodes[i];
                  final isCurrent = episode.id == widget.currentMedia.id ||
                      (episode.seasonNumber == widget.currentMedia.season &&
                          episode.episodeNumber == widget.currentMedia.episode);
                  return InkWell(
                    onTap: () => widget.onEpisode(episode),
                    borderRadius: BorderRadius.circular(18),
                    child: Ink(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? AppColors.redBright.withOpacity(.12)
                            : Colors.white.withOpacity(.035),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isCurrent
                              ? AppColors.redBright.withOpacity(.45)
                              : Colors.white.withOpacity(.06),
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 86,
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: CinematyNetworkImage(
                                url: episode.posterUrl,
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 11),
                          Container(
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(.055),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${episode.episodeNumber}',
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              episode.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight:
                                    isCurrent ? FontWeight.w900 : FontWeight.w700,
                              ),
                            ),
                          ),
                          if (isCurrent)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                'تشاهدها الآن',
                                style: TextStyle(
                                  color: AppColors.redBright,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            )
                          else
                            const Icon(Icons.play_arrow_rounded, size: 22),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
