import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../data/models/episode.dart';
import '../data/models/media_item.dart';
import '../data/models/video_source.dart';
import '../tv_context.dart';
import '../tv_focus.dart';
import '../tv_image.dart';
import '../tv_platform_ui.dart';
import '../tv_subtitles.dart';
import '../tv_theme.dart';

class TvPlayerScreen extends StatefulWidget {
  const TvPlayerScreen({
    super.key,
    required this.media,
    this.localPath,
  });

  final MediaItem media;
  final String? localPath;

  @override
  State<TvPlayerScreen> createState() => _TvPlayerScreenState();
}

class _TvPlayerScreenState extends State<TvPlayerScreen> {
  final FocusNode _rootFocus = FocusNode(debugLabel: 'player-root');
  final FocusNode _seekFocus = FocusNode(debugLabel: 'player-seek');
  final FocusNode _playFocus = FocusNode(debugLabel: 'player-play');
  final FocusNode _episodesFocus = FocusNode(debugLabel: 'player-episodes');
  final FocusNode _episodePanelFocus = FocusNode(debugLabel: 'player-episode-current');
  final FocusNode _seasonPanelFocus = FocusNode(debugLabel: 'player-season-current');
  final FocusNode _settingsFocus = FocusNode(debugLabel: 'player-settings');
  final FocusNode _backFocus = FocusNode(debugLabel: 'player-back');

  final TvSubtitleLoader _subtitleLoader = TvSubtitleLoader();
  final TvSubtitleStore _subtitleStore = TvSubtitleStore();

  late final Player _player;
  late final VideoController _videoController;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<bool>? _playingSub;

  Timer? _hideTimer;
  Timer? _progressSaveTimer;

  LogicalKeyboardKey? _heldSeekKey;
  DateTime? _heldSeekStartedAt;
  DateTime? _lastSeekActionAt;

  late MediaItem _media;
  List<VideoSource> _sources = const [];
  VideoSource? _selectedSource;

  List<SubtitleSource> _subtitleSources = const [];
  SubtitleSource? _selectedSubtitle;
  List<TvSubtitleCue> _subtitleCues = const [];
  TvSubtitleCue? _activeCue;
  int _subtitleCueIndex = 0;
  TvSubtitleStyle _subtitleStyle = const TvSubtitleStyle();

  List<SeasonGroup> _seasons = const [];
  int _seasonIndex = 0;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _buffering = true;
  bool _openingOrRestoring = false;
  bool _playing = false;
  bool _loading = true;
  bool _controls = true;
  bool _seekFocused = false;
  bool _seekHovered = false;
  bool _episodesOpen = false;

  @override
  void initState() {
    super.initState();
    _media = widget.media;

    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 64 * 1024 * 1024,
      ),
    );
    _videoController = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        // Keep the exact Android TV decode path that was smooth before:
        // native MediaCodec + delayed surface attach. Do not force a custom VO.
        hwdec: 'mediacodec',
        enableHardwareAcceleration: true,
        androidAttachSurfaceAfterVideoParameters: true,
      ),
    );

    _positionSub = _player.stream.position.listen((value) {
      _position = value;
      final cue = _cueFor(value);
      final cueChanged = cue?.text != _activeCue?.text;
      _activeCue = cue;
      if (mounted && (_controls || cueChanged)) setState(() {});
    });
    _durationSub = _player.stream.duration.listen((value) {
      _duration = value;
      if (mounted && _controls) setState(() {});
    });
    _bufferingSub = _player.stream.buffering.listen((value) {
      _buffering = value;
      if (mounted) setState(() {});
    });
    _playingSub = _player.stream.playing.listen((value) {
      _playing = value;
      if (!value && !_openingOrRestoring) {
        unawaited(_saveProgress());
      }
      if (mounted && _controls) setState(() {});
    });
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    _subtitleStyle = await _subtitleStore.load();
    await _enterFullscreen();
    await _openMedia(
      _media,
      localPath: widget.localPath,
      restoreSavedProgress: true,
    );
    _scheduleHide();
    _progressSaveTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_saveProgress()),
    );

    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _rootFocus.requestFocus();
      });
    }
  }

  Future<void> _enterFullscreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _openMedia(
    MediaItem media, {
    String? localPath,
    bool restoreSavedProgress = false,
  }) async {
    _openingOrRestoring = true;
    if (mounted) {
      setState(() {
        _loading = true;
        _buffering = true;
        _sources = const [];
        _selectedSource = null;
        _subtitleSources = const [];
        _selectedSubtitle = null;
        _subtitleCues = const [];
        _activeCue = null;
        _subtitleCueIndex = 0;
        _seasons = const [];
        _seasonIndex = 0;
      });
    }

    try {
      Duration? resume;
      if (restoreSavedProgress) {
        final saved = tvLibrary.progress(media.id);
        if (saved != null &&
            saved.positionMs > 3000 &&
            saved.ratio < .97) {
          resume = Duration(milliseconds: saved.positionMs);
        }
      }

      final path = (localPath ?? '').trim();
      if (path.isNotEmpty) {
        final downloaded = tvDownloads.itemFor(media.id);
        if (downloaded != null && downloaded.subtitles.isNotEmpty) {
          _subtitleSources = downloaded.subtitles
              .map(
                (subtitle) => SubtitleSource(
                  url: subtitle.localPath,
                  language: subtitle.language,
                  label: subtitle.label,
                ),
              )
              .toList(growable: false);
        }

        await _openRaw(path, resume: resume);
        await _enableArabicSubtitleByDefault();
      } else {
        final values = await Future.wait<dynamic>([
          tvApi.videoSources(media.id),
          tvApi.subtitles(media.id).catchError(
            (_) => <SubtitleSource>[],
          ),
        ]);

        _sources = values[0] as List<VideoSource>;
        _subtitleSources = values[1] as List<SubtitleSource>;

        if (_sources.isEmpty) {
          throw StateError('لم يرجع المصدر رابط تشغيل صالح');
        }

        _selectedSource = _preferredSource(_sources);
        await _openRaw(_selectedSource!.url, resume: resume);
        await _enableArabicSubtitleByDefault();
      }

      if (media.isSeries) {
        try {
          _seasons = await tvApi.seasonsFor(media);
          final currentSeason = media.season ?? 0;
          final index =
              _seasons.indexWhere((s) => s.number == currentSeason);
          _seasonIndex = index >= 0 ? index : 0;
        } catch (_) {
          _seasons = const [];
        }
      }

      if (!mounted) return;
      _openingOrRestoring = false;
      setState(() {
        _loading = false;
      });
    } catch (error) {
      _openingOrRestoring = false;
      if (!mounted) return;
      setState(() {
        _loading = false;
        _buffering = false;
      });
    }
  }

  int _sourcePixels(VideoSource source) {
    final match = RegExp(r'(2160|1440|1080|720|480|360|320|240)')
        .firstMatch('${source.quality} ${source.resolution}');
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  VideoSource _preferredSource(List<VideoSource> sources) {
    final preferred = tvPlaybackPreferences.preferredQuality;
    final exact = sources.where((source) => _sourcePixels(source) == preferred);
    if (exact.isNotEmpty) return exact.first;

    final below = sources
        .where((source) => _sourcePixels(source) > 0 && _sourcePixels(source) <= preferred)
        .toList()
      ..sort((a, b) => _sourcePixels(b).compareTo(_sourcePixels(a)));
    if (below.isNotEmpty) return below.first;

    final ordered = [...sources]
      ..sort((a, b) => _sourcePixels(a).compareTo(_sourcePixels(b)));
    return ordered.first;
  }


  Future<void> _openRaw(
    String url, {
    Duration? resume,
  }) async {
    _position = Duration.zero;
    _duration = Duration.zero;
    _buffering = true;

    await _player.open(Media(url), play: false);
    await _waitForPlayable();

    if (resume != null && resume > const Duration(seconds: 3)) {
      await _restorePlaybackPosition(resume, autoplay: true);
    } else {
      await _player.play();
    }
  }

  Future<void> _waitForPlayable() async {
    for (var i = 0; i < 50; i++) {
      if (_player.state.duration > Duration.zero) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<bool> _waitUntilNear(
    Duration target, {
    Duration tolerance = const Duration(seconds: 3),
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final current = _player.state.position;
      if ((current - target).abs() <= tolerance) return true;
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    return false;
  }

  Future<void> _restorePlaybackPosition(
    Duration target, {
    required bool autoplay,
  }) async {
    if (target <= const Duration(seconds: 2)) {
      if (autoplay) await _player.play();
      return;
    }

    _openingOrRestoring = true;

    try {
      await _player.pause();

      // First restore while paused. Some TV decoders need more than one
      // seek while the stream metadata is settling.
      var restored = false;
      for (var attempt = 0; attempt < 7 && !restored; attempt++) {
        await _player.seek(target);
        restored = await _waitUntilNear(
          target,
          tolerance: const Duration(seconds: 2),
          timeout: const Duration(milliseconds: 1000),
        );

        if (!restored) {
          await Future<void>.delayed(
            const Duration(milliseconds: 120),
          );
        }
      }

      if (autoplay) {
        await _player.play();

        // A few HLS/remote streams jump back to 0 exactly when playback
        // starts. Verify the REAL player position, then force the saved
        // position again if the decoder reset it.
        for (var attempt = 0; attempt < 6; attempt++) {
          await Future<void>.delayed(
            const Duration(milliseconds: 280),
          );

          final actual = _player.state.position;
          if (actual >= target - const Duration(seconds: 4)) {
            break;
          }

          await _player.seek(target);
        }
      }
    } finally {
      _openingOrRestoring = false;
    }
  }


  Future<void> _switchSource(VideoSource source) async {
    if (_selectedSource?.url == source.url) return;

    final oldPosition = _player.state.position;
    final wasPlaying = _player.state.playing;

    await _saveProgress();
    if (mounted) setState(() => _loading = true);

    try {
      await _player.open(Media(source.url), play: false);
      await _waitForPlayable();

      if (oldPosition > const Duration(seconds: 2)) {
        await _restorePlaybackPosition(
          oldPosition,
          autoplay: wasPlaying,
        );
      } else if (wasPlaying) {
        await _player.play();
      }

      _selectedSource = source;
      final pixels = _sourcePixels(source);
      if (pixels > 0) {
        await tvPlaybackPreferences.setPreferredQuality(pixels);
      }

      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }


  Future<void> _enableArabicSubtitleByDefault() async {
    if (_subtitleSources.isEmpty) return;

    bool isArabic(SubtitleSource source) {
      final value =
          '${source.language} ${source.label}'.toLowerCase().trim();
      return value.contains('العرب') ||
          value.contains('arabic') ||
          value == 'ar' ||
          value.startsWith('ar ') ||
          value.contains(' ar ');
    }

    final source = _subtitleSources.firstWhere(
      isArabic,
      orElse: () => _subtitleSources.first,
    );

    try {
      final cues = await _subtitleLoader.load(source);
      _selectedSubtitle = source;
      _subtitleCues = cues;
      _subtitleCueIndex = 0;
      _activeCue = null;
    } catch (_) {
      // Playback must never fail just because a subtitle endpoint failed.
    }
  }

  Future<void> _selectSubtitle(SubtitleSource source) async {
    if (mounted) setState(() => _loading = true);
    try {
      final cues = await _subtitleLoader.load(source);
      _selectedSubtitle = source;
      _subtitleCues = cues;
      _subtitleCueIndex = 0;
      _activeCue = null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  TvSubtitleCue? _cueFor(Duration position) {
    if (_subtitleCues.isEmpty) return null;

    if (_subtitleCueIndex >= _subtitleCues.length) {
      _subtitleCueIndex = _subtitleCues.length - 1;
    }

    while (_subtitleCueIndex > 0 &&
        position < _subtitleCues[_subtitleCueIndex].start) {
      _subtitleCueIndex--;
    }
    while (_subtitleCueIndex < _subtitleCues.length - 1 &&
        position >= _subtitleCues[_subtitleCueIndex].end) {
      _subtitleCueIndex++;
    }

    final cue = _subtitleCues[_subtitleCueIndex];
    if (position >= cue.start && position < cue.end) return cue;
    return null;
  }

  Future<void> _saveProgress() async {
    if (_openingOrRestoring) return;

    final playerDuration = _player.state.duration;
    final playerPosition = _player.state.position;

    final duration = playerDuration > Duration.zero
        ? playerDuration
        : _duration;
    final position = playerPosition > Duration.zero
        ? playerPosition
        : _position;

    if (duration <= Duration.zero) return;

    final previous = tvLibrary.progress(_media.id);

    // Opening a stream can briefly report 0:00 even though the user has a
    // valid saved continue point. Never let that transient state erase it.
    if (position < const Duration(seconds: 5) &&
        previous != null &&
        previous.positionMs > 30000 &&
        previous.ratio < .97) {
      return;
    }

    await tvLibrary.saveProgress(
      _media,
      position,
      duration,
    );
  }


  Future<void> _seekBy(int seconds) async {
    if (_duration <= Duration.zero) return;
    var next = _player.state.position + Duration(seconds: seconds);
    if (next < Duration.zero) next = Duration.zero;
    if (next > _duration) next = _duration;
    await _player.seek(next);
    _position = next;
    _showControls();
  }

  Future<void> _seekToFraction(double fraction) async {
    if (_duration <= Duration.zero) return;
    final safe = fraction.clamp(0.0, 1.0);
    final target = Duration(
      milliseconds: (_duration.inMilliseconds * safe).round(),
    );
    await _player.seek(target);
    _position = target;
    _showControls();
    if (mounted) setState(() {});
  }

  int _seekStepForHold(Duration held) {
    final ms = held.inMilliseconds;
    if (ms < 650) return 10;
    if (ms < 1300) return 20;
    if (ms < 2200) return 30;
    if (ms < 3200) return 45;
    if (ms < 4500) return 60;
    if (ms < 6000) return 90;
    if (ms < 8000) return 120;
    return 180;
  }

  Future<void> _seekFromRemote(
    LogicalKeyboardKey key, {
    required bool repeated,
  }) async {
    final now = DateTime.now();

    if (!repeated || _heldSeekKey != key || _heldSeekStartedAt == null) {
      _heldSeekKey = key;
      _heldSeekStartedAt = now;
      _lastSeekActionAt = now;
      await _seekBy(key == LogicalKeyboardKey.arrowRight ? 10 : -10);
      return;
    }

    // TV remotes can emit key-repeat events extremely quickly. Throttle the
    // actual seek operation while still increasing the seek distance the
    // longer the button remains held.
    final last = _lastSeekActionAt;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 220)) {
      return;
    }

    _lastSeekActionAt = now;
    final held = now.difference(_heldSeekStartedAt!);
    final step = _seekStepForHold(held);
    await _seekBy(key == LogicalKeyboardKey.arrowRight ? step : -step);
  }

  void _resetHeldSeek() {
    _heldSeekKey = null;
    _heldSeekStartedAt = null;
    _lastSeekActionAt = null;
  }

  void _showControls() {
    if (!_controls && mounted) setState(() => _controls = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _episodesOpen || _seekFocused) return;
      setState(() => _controls = false);
    });
  }

  bool get _topControlsFocused =>
      _episodesFocus.hasFocus ||
      _settingsFocus.hasFocus ||
      _backFocus.hasFocus;

  void _moveTopFocus(int direction) {
    final nodes = <FocusNode>[
      if (_media.isSeries && _seasons.isNotEmpty) _episodesFocus,
      _settingsFocus,
      _backFocus,
    ];
    if (nodes.isEmpty) return;

    var index = nodes.indexWhere((node) => node.hasFocus);
    if (index < 0) index = nodes.indexOf(_settingsFocus);
    index = (index + direction).clamp(0, nodes.length - 1);
    nodes[index].requestFocus();
  }

  Future<void> _playEpisode(Episode episode) async {
    await _saveProgress();

    final media = MediaItem(
      id: episode.id,
      title: episode.title,
      description: episode.description,
      posterUrl: episode.posterUrl,
      backdropUrl: episode.posterUrl,
      year: _media.year,
      rating: episode.rating,
      isSeries: true,
      season: episode.seasonNumber,
      episode: episode.episodeNumber,
      raw: episode.raw,
    );

    setState(() {
      _media = media;
      _episodesOpen = false;
    });

    await _openMedia(
      media,
      restoreSavedProgress: true,
    );
    _rootFocus.requestFocus();
    _scheduleHide();
  }

  KeyEventResult _keys(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;

    if (event is KeyUpEvent) {
      if (key == _heldSeekKey) _resetHeldSeek();
      return KeyEventResult.ignored;
    }

    final isPress =
        event is KeyDownEvent || event is KeyRepeatEvent;
    if (!isPress) return KeyEventResult.ignored;

    final repeated = event is KeyRepeatEvent;

    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.browserBack) {
      if (_episodesOpen) {
        setState(() => _episodesOpen = false);
        _rootFocus.requestFocus();
      } else if (_controls) {
        _hideTimer?.cancel();
        setState(() {
          _controls = false;
          _seekFocused = false;
        });
        _rootFocus.requestFocus();
      } else {
        Navigator.of(context).maybePop();
      }
      return KeyEventResult.handled;
    }

    if (_episodesOpen) return KeyEventResult.ignored;

    if (_topControlsFocused) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        _moveTopFocus(1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        _moveTopFocus(-1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _showControls();
        _playFocus.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (_playFocus.hasFocus) {
      if (key == LogicalKeyboardKey.arrowUp) {
        _showControls();
        _settingsFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _showControls();
        _seekFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight) {
        unawaited(_seekFromRemote(key, repeated: repeated));
        return KeyEventResult.handled;
      }
    }

    if (_seekFocus.hasFocus) {
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowLeft) {
      unawaited(_seekFromRemote(key, repeated: repeated));
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      _showControls();
      _seekFocus.requestFocus();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      _showControls();
      _playFocus.requestFocus();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      _player.state.playing ? _player.pause() : _player.play();
      _showControls();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.mediaFastForward) {
      unawaited(
        _seekFromRemote(
          LogicalKeyboardKey.arrowRight,
          repeated: repeated,
        ),
      );
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.mediaRewind) {
      unawaited(
        _seekFromRemote(
          LogicalKeyboardKey.arrowLeft,
          repeated: repeated,
        ),
      );
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    unawaited(_saveProgress());
    _hideTimer?.cancel();
    _progressSaveTimer?.cancel();

    unawaited(_positionSub?.cancel());
    unawaited(_durationSub?.cancel());
    unawaited(_bufferingSub?.cancel());
    unawaited(_playingSub?.cancel());

    _rootFocus.dispose();
    _seekFocus.dispose();
    _playFocus.dispose();
    _episodesFocus.dispose();
    _episodePanelFocus.dispose();
    _seasonPanelFocus.dispose();
    _settingsFocus.dispose();
    _backFocus.dispose();

    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_episodesOpen) {
          setState(() => _episodesOpen = false);
          _rootFocus.requestFocus();
          return false;
        }
        if (_controls) {
          _hideTimer?.cancel();
          setState(() {
            _controls = false;
            _seekFocused = false;
          });
          _rootFocus.requestFocus();
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _rootFocus,
          autofocus: true,
          onKeyEvent: _keys,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _showControls,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Video(
                  controller: _videoController,
                  fit: BoxFit.contain,
                  controls: NoVideoControls,
                ),
                if (_activeCue != null)
                  _subtitleOverlay(_activeCue!),
                if (_loading || _buffering)
                  const Center(
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                if (_controls) _controlsOverlay(),
                if (_episodesOpen) _episodesPanel(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _subtitleOverlay(TvSubtitleCue cue) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment(
          _subtitleStyle.positionX.clamp(-1.0, 1.0),
          _subtitleStyle.positionY.clamp(-1.0, 1.0),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1200),
          margin: const EdgeInsets.symmetric(horizontal: 90),
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(
              _subtitleStyle.backgroundOpacity.clamp(0.0, 1.0).toDouble(),
            ),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            cue.text,
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              color: _subtitleStyle.textColor,
              fontFamily: _subtitleStyle.fontFamily == 'app'
                  ? 'Monadi'
                  : 'Roboto',
              fontSize: _subtitleStyle.fontSize,
              height: 1.25,
              fontWeight: _subtitleStyle.bold
                  ? FontWeight.w800
                  : FontWeight.normal,
              shadows: tvSubtitleShadows(_subtitleStyle),
            ),
          ),
        ),
      ),
    );
  }

  Widget _controlsOverlay() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Color(0xEE000000),
            Color(0x05000000),
            Color(0xB3000000),
          ],
          stops: [0, .48, 1],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(30, 22, 30, 24),
        child: Column(
          children: [
            _topControls(),
            const Spacer(),
            TvFocus(
              focusNode: _playFocus,
              borderRadius: 999,
              onPressed: () {
                _player.state.playing
                    ? _player.pause()
                    : _player.play();
                _showControls();
              },
              onArrowUp: () {
                _showControls();
                _settingsFocus.requestFocus();
              },
              onArrowDown: () {
                _showControls();
                _seekFocus.requestFocus();
              },
              child: Container(
                width: 76,
                height: 76,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.32),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white12),
                ),
                child: Icon(
                  _playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 48,
                ),
              ),
            ),
            const Spacer(),
            _seekBar(),
          ],
        ),
      ),
    );
  }

  Widget _topControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          textDirection: TextDirection.rtl,
          children: [
            if (_media.isSeries && _seasons.isNotEmpty) ...[
              TvFocus(
                focusNode: _episodesFocus,
                onPressed: () {
                  _hideTimer?.cancel();
                  setState(() => _episodesOpen = true);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _episodePanelFocus.requestFocus();
                  });
                },
                child: const _TopButton(
                  icon: Icons.video_library_rounded,
                  label: 'الحلقات',
                ),
              ),
              const SizedBox(width: 10),
            ],
            TvFocus(
              focusNode: _settingsFocus,
              onPressed: _showPlaybackSettings,
              child: const _TopButton(
                icon: Icons.tune_rounded,
                label: 'الإعدادات',
              ),
            ),
            const SizedBox(width: 10),
            TvFocus(
              focusNode: _backFocus,
              onPressed: () => Navigator.of(context).maybePop(),
              child: const _TopButton(
                icon: Icons.arrow_forward_rounded,
                label: 'رجوع',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: Text(
            _media.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            textDirection: TextDirection.rtl,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (_media.isSeries)
          SizedBox(
            width: double.infinity,
            child: Text(
              'الموسم ${_media.season ?? '-'} • الحلقة ${_media.episode ?? '-'}',
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  Widget _seekBar() {
    final total =
        _duration.inMilliseconds <= 0 ? 1 : _duration.inMilliseconds;
    final progress =
        (_position.inMilliseconds / total).clamp(0.0, 1.0);
    final seekActive =
        _seekFocused || (tvIsWindowsDesktop && _seekHovered);

    return Focus(
      focusNode: _seekFocus,
      onFocusChange: (value) {
        if (!mounted) return;
        setState(() => _seekFocused = value);
        if (value) {
          _hideTimer?.cancel();
        } else {
          _scheduleHide();
        }
      },
      onKeyEvent: (node, event) {
        final key = event.logicalKey;

        if (event is KeyUpEvent) {
          if (key == _heldSeekKey) _resetHeldSeek();
          return KeyEventResult.ignored;
        }

        final isPress =
            event is KeyDownEvent || event is KeyRepeatEvent;
        if (!isPress) return KeyEventResult.ignored;
        final repeated = event is KeyRepeatEvent;

        if (key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.arrowLeft) {
          unawaited(_seekFromRemote(key, repeated: repeated));
          return KeyEventResult.handled;
        }

        if (key == LogicalKeyboardKey.arrowUp) {
          _showControls();
          _playFocus.requestFocus();
          return KeyEventResult.handled;
        }

        if (key == LogicalKeyboardKey.arrowDown) {
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: tvIsWindowsDesktop
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        onEnter: (_) {
          if (tvIsWindowsDesktop && !_seekHovered) {
            setState(() => _seekHovered = true);
            _hideTimer?.cancel();
          }
        },
        onExit: (_) {
          if (_seekHovered) {
            setState(() => _seekHovered = false);
            if (!_seekFocused) _scheduleHide();
          }
        },
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        padding: EdgeInsets.symmetric(
          horizontal: seekActive ? 10 : 3,
          vertical: seekActive ? 8 : 4,
        ),
        decoration: BoxDecoration(
          color: seekActive
              ? Colors.white.withOpacity(.075)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: seekActive ? Colors.white : Colors.transparent,
            width: seekActive ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                const previewWidth = 210.0;
                final previewLeft = ((width - previewWidth) * progress)
                    .clamp(0.0, width - previewWidth);

                final track = SizedBox(
                  height: seekActive ? 132 : 16,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (seekActive)
                        Positioned(
                          left: previewLeft,
                          top: 0,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 95),
                            width: previewWidth,
                            height: 100,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: const Color(0xEF0D0D0D),
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(
                                color: Colors.white.withOpacity(.82),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(.48),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                TvImage(
                                  _media.backdropUrl.isNotEmpty
                                      ? _media.backdropUrl
                                      : _media.posterUrl,
                                  cacheWidth: 420,
                                  borderRadius: 0,
                                  fit: BoxFit.cover,
                                ),
                                const DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.center,
                                      colors: [
                                        Color(0xD6000000),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 11,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xD9000000),
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                      child: Text(
                                        _format(_position),
                                        textDirection: TextDirection.ltr,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: SizedBox(
                          height: 16,
                          child: Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              Container(
                                width: width,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.white24,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                              Container(
                                width: width * progress,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: TvColors.red,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                              Positioned(
                                left: (width - 14) * progress,
                                child: Container(
                                  width: seekActive ? 14 : 10,
                                  height: seekActive ? 14 : 10,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
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

                if (!tvIsWindowsDesktop) return track;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    unawaited(_seekToFraction(details.localPosition.dx / width));
                  },
                  onHorizontalDragStart: (details) {
                    _hideTimer?.cancel();
                    unawaited(_seekToFraction(details.localPosition.dx / width));
                  },
                  onHorizontalDragUpdate: (details) {
                    unawaited(_seekToFraction(details.localPosition.dx / width));
                  },
                  onHorizontalDragEnd: (_) => _scheduleHide(),
                  child: track,
                );
              },
            ),
            const SizedBox(height: 3),
            Row(
              textDirection: TextDirection.ltr,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _format(_position),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
                Text(
                  _format(_duration),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  String _episodeArtwork(Episode episode) {
    for (final key in const [
      'seasonPoster',
      'seriesPoster',
      'poster',
      'episodePoster',
      'imgMediumThumbObjUrl',
      'imgThumbObjUrl',
    ]) {
      final value = episode.raw[key];
      if (value != null && '$value'.trim().isNotEmpty) {
        return normalizeMediaUrl('$value'.trim());
      }
    }
    return episode.posterUrl.isNotEmpty
        ? episode.posterUrl
        : _media.posterUrl;
  }

  Widget _episodesPanel() {
    if (_seasons.isEmpty) return const SizedBox.shrink();
    final season =
        _seasons[_seasonIndex.clamp(0, _seasons.length - 1)];
    final hasCurrent =
        season.episodes.any((episode) => episode.id == _media.id);

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: 485,
        height: double.infinity,
        color: const Color(0xF5101010),
        child: SafeArea(
          child: FocusTraversalGroup(
            policy: ReadingOrderTraversalPolicy(),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      const Expanded(
                        child: Text(
                          'الحلقات',
                          textAlign: TextAlign.right,
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      TvFocus(
                        onPressed: () {
                          setState(() => _episodesOpen = false);
                          _episodesFocus.requestFocus();
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(7),
                          child: Icon(Icons.close_rounded, size: 24),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 56,
                  child: ListView.separated(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12),
                    scrollDirection: Axis.horizontal,
                    itemCount: _seasons.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final active = index == _seasonIndex;
                      return TvFocus(
                        focusNode:
                            active ? _seasonPanelFocus : null,
                        onArrowDown: () =>
                            _episodePanelFocus.requestFocus(),
                        onPressed: () {
                          setState(() => _seasonIndex = index);
                          WidgetsBinding.instance
                              .addPostFrameCallback((_) {
                            if (mounted) {
                              _episodePanelFocus.requestFocus();
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: active
                                ? TvColors.red
                                : Colors.white10,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'الموسم ${_seasons[index].number}',
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
                      ListView.separated(
                        padding:
                            const EdgeInsets.fromLTRB(12, 12, 12, 76),
                        itemCount: season.episodes.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final episode = season.episodes[index];
                          final current = episode.id == _media.id;
                          final focusThis =
                              current || (!hasCurrent && index == 0);

                          return TvFocus(
                            focusNode:
                                focusThis ? _episodePanelFocus : null,
                            onArrowUp: index == 0
                                ? () =>
                                    _seasonPanelFocus.requestFocus()
                                : null,
                            onPressed: () =>
                                _playEpisode(episode),
                            child: SizedBox(
                              height: 190,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  TvImage(
                                    _episodeArtwork(episode),
                                    cacheWidth: 700,
                                    borderRadius: 14,
                                    fit: BoxFit.cover,
                                  ),
                                  const DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin:
                                            Alignment.bottomCenter,
                                        end: Alignment.center,
                                        colors: [
                                          Color(0xA8000000),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 11,
                                    bottom: 11,
                                    child: Container(
                                      padding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 11,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: current
                                            ? Colors.white
                                            : TvColors.red,
                                        borderRadius:
                                            BorderRadius.circular(99),
                                      ),
                                      child: Text(
                                        'الحلقة ${episode.episodeNumber}',
                                        style: TextStyle(
                                          color: current
                                              ? Colors.black
                                              : Colors.white,
                                          fontSize: 12,
                                          fontWeight:
                                              FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (current)
                                    const Positioned(
                                      left: 11,
                                      bottom: 13,
                                      child: Text(
                                        'أنت هنا الآن',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight:
                                              FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 78,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Color(0xFA101010),
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
          ),
        ),
      ),
    );
  }

  Future<void> _showPlaybackSettings() async {
    _hideTimer?.cancel();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171717),
        title: const Text(
          'إعدادات المشغل',
          textAlign: TextAlign.right,
        ),
        content: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TvFocus(
                autofocus: true,
                onPressed: () {
                  Navigator.pop(context);
                  _showQuality();
                },
                child: const _SettingsTile(
                  icon: Icons.high_quality_rounded,
                  title: 'الدقة والجودة',
                  subtitle: 'اختيار جودة تشغيل الفيديو',
                ),
              ),
              const SizedBox(height: 8),
              TvFocus(
                onPressed: () {
                  Navigator.pop(context);
                  _showSubtitleSettings();
                },
                child: _SettingsTile(
                  icon: Icons.subtitles_rounded,
                  title: 'الترجمة',
                  subtitle: _selectedSubtitle?.label.isNotEmpty == true
                      ? _selectedSubtitle!.label
                      : 'العربية • مفعلة تلقائياً',
                ),
              ),
            ],
          ),
        ),
      ),
    );

    _showControls();
  }

  Future<void> _showQuality() async {
    if (_sources.isEmpty) return;

    final source = await showDialog<VideoSource>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171717),
        title: const Text('الدقة والجودة'),
        content: SizedBox(
          width: 390,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _sources.length,
            separatorBuilder: (_, __) => const SizedBox(height: 5),
            itemBuilder: (context, index) {
              final source = _sources[index];
              final selected = source.url == _selectedSource?.url;

              return TvFocus(
                autofocus: selected,
                onPressed: () => Navigator.pop(context, source),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? TvColors.red.withOpacity(.18)
                        : Colors.white.withOpacity(.04),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Expanded(
                        child: Text(
                          source.quality,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (selected)
                        const Icon(
                          Icons.check_circle_rounded,
                          color: TvColors.red,
                          size: 20,
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

    if (source != null &&
        source.url != _selectedSource?.url) {
      await _switchSource(source);
    }
  }

  Future<void> _showSubtitleSettings() async {
    var draft = _subtitleStyle;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF171717),
            title: const Text('إعدادات الترجمة'),
            content: SizedBox(
              width: 560,
              height: 560,
              child: FocusTraversalGroup(
                policy: ReadingOrderTraversalPolicy(),
                child: ListView(
                  children: [
                    const Text(
                      'الترجمة العربية مفعلة تلقائياً',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._subtitleSources.map(
                      (source) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: TvFocus(
                          autofocus:
                              _selectedSubtitle?.url == source.url,
                          onPressed: () async {
                            await _selectSubtitle(source);
                            if (mounted) setDialogState(() {});
                          },
                          child: _subtitleOption(
                            source.label.isEmpty
                                ? source.language
                                : source.label,
                            _selectedSubtitle?.url == source.url,
                          ),
                        ),
                      ),
                    ),
                    if (_subtitleSources.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'لا توجد ترجمة متاحة لهذا المحتوى',
                          textAlign: TextAlign.right,
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    const Divider(height: 22),
                    _TvSettingSlider(
                      label: 'حجم الخط',
                      value: draft.fontSize,
                      min: 30,
                      max: 76,
                      step: 2,
                      display: '${draft.fontSize.round()}',
                      onChanged: (value) {
                        setDialogState(
                          () => draft =
                              draft.copyWith(fontSize: value),
                        );
                      },
                    ),
                    _TvSettingSlider(
                      label: 'سمك الحواف',
                      value: draft.edgeThickness,
                      min: 0,
                      max: 2,
                      step: .1,
                      display:
                          draft.edgeThickness.toStringAsFixed(1),
                      onChanged: (value) {
                        setDialogState(
                          () => draft = draft.copyWith(
                            edgeThickness: value,
                          ),
                        );
                      },
                    ),
                    _TvSettingSlider(
                      label: 'شفافية الحواف',
                      value: draft.edgeOpacity,
                      min: 0,
                      max: 1,
                      step: .05,
                      display:
                          '${(draft.edgeOpacity * 100).round()}%',
                      onChanged: (value) {
                        setDialogState(
                          () => draft = draft.copyWith(
                            edgeOpacity: value,
                          ),
                        );
                      },
                    ),
                    _TvSettingSlider(
                      label: 'خلفية الترجمة',
                      value: draft.backgroundOpacity,
                      min: 0,
                      max: .8,
                      step: .05,
                      display:
                          '${(draft.backgroundOpacity * 100).round()}%',
                      onChanged: (value) {
                        setDialogState(
                          () => draft = draft.copyWith(
                            backgroundOpacity: value,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 3),
                    TvFocus(
                      onPressed: () {
                        setDialogState(() {
                          draft = draft.copyWith(
                            fontFamily:
                                draft.fontFamily == 'system'
                                    ? 'app'
                                    : 'system',
                          );
                        });
                      },
                      child: _subtitleOption(
                        draft.fontFamily == 'system'
                            ? 'نوع الخط: خط النظام'
                            : 'نوع الخط: خط التطبيق',
                        true,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TvFocus(
                      onPressed: () {
                        setDialogState(() {
                          draft =
                              draft.copyWith(bold: !draft.bold);
                        });
                      },
                      child: _subtitleOption(
                        draft.bold
                            ? 'وزن الخط: عريض'
                            : 'وزن الخط: عادي',
                        true,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TvFocus(
                      onPressed: () async {
                        final position = await _editSubtitlePosition(
                          Offset(draft.positionX, draft.positionY),
                        );
                        if (position != null) {
                          setDialogState(() {
                            draft = draft.copyWith(
                              positionX: position.dx,
                              positionY: position.dy,
                            );
                          });
                        }
                      },
                      child: _subtitleOption('موضع الترجمة', true),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(
                          draft.backgroundOpacity,
                        ),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        'معاينة الترجمة العربية',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: draft.textColor,
                          fontFamily:
                              draft.fontFamily == 'app'
                                  ? 'Monadi'
                                  : 'Roboto',
                          fontSize:
                              draft.fontSize.clamp(30, 46),
                          fontWeight: draft.bold
                              ? FontWeight.w800
                              : FontWeight.normal,
                          shadows: tvSubtitleShadows(draft),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () async {
                  setState(() => _subtitleStyle = draft);
                  await _subtitleStore.save(draft);
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }
                },
                child: const Text('حفظ'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<Offset?> _editSubtitlePosition(Offset start) async {
    var value = start;

    final result = await showDialog<Offset>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.black,
              insetPadding: const EdgeInsets.all(26),
              child: Focus(
                autofocus: true,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                    return KeyEventResult.ignored;
                  }
                  const step = .04;
                  final key = event.logicalKey;

                  if (key == LogicalKeyboardKey.arrowUp) {
                    setDialogState(() {
                      value = Offset(value.dx, (value.dy - step).clamp(-1.0, 1.0));
                    });
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.arrowDown) {
                    setDialogState(() {
                      value = Offset(value.dx, (value.dy + step).clamp(-1.0, 1.0));
                    });
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.arrowLeft) {
                    setDialogState(() {
                      value = Offset((value.dx - step).clamp(-1.0, 1.0), value.dy);
                    });
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.arrowRight) {
                    setDialogState(() {
                      value = Offset((value.dx + step).clamp(-1.0, 1.0), value.dy);
                    });
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.escape ||
                      key == LogicalKeyboardKey.browserBack) {
                    Navigator.pop(dialogContext, value);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF171717), Color(0xFF050505)],
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment(value.dx, value.dy),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(_subtitleStyle.backgroundOpacity),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          _activeCue?.text.isNotEmpty == true
                              ? _activeCue!.text
                              : 'هذا هو موضع الترجمة — حرّكه بأسهم الريموت',
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            color: _subtitleStyle.textColor,
                            fontSize: _subtitleStyle.fontSize.clamp(24, 42),
                            fontFamily: _subtitleStyle.fontFamily == 'app'
                                ? 'Monadi'
                                : 'Roboto',
                            shadows: tvSubtitleShadows(_subtitleStyle),
                          ),
                        ),
                      ),
                    ),
                    const Positioned(
                      top: 20,
                      left: 20,
                      right: 20,
                      child: Text(
                        'حرّك الموضع بالأسهم • زر الرجوع يحفظ',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result != null) {
      final updated = _subtitleStyle.copyWith(
        positionX: result.dx,
        positionY: result.dy,
      );
      setState(() => _subtitleStyle = updated);
      await _subtitleStore.save(updated);
    }
    return result;
  }

  Widget _subtitleOption(String title, bool selected) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: selected
            ? TvColors.red.withOpacity(.16)
            : Colors.white.withOpacity(.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (selected)
            const Icon(
              Icons.check_circle_rounded,
              color: TvColors.red,
              size: 19,
            ),
        ],
      ),
    );
  }

  String _format(Duration value) {
    final h = value.inHours;
    final m =
        value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s =
        value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '${value.inMinutes}:$s';
  }
}

class _TvSettingSlider extends StatefulWidget {
  const _TvSettingSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  State<_TvSettingSlider> createState() =>
      _TvSettingSliderState();
}

class _TvSettingSliderState extends State<_TvSettingSlider> {
  bool _focused = false;

  void _change(double direction) {
    final next = (widget.value + widget.step * direction)
        .clamp(widget.min, widget.max)
        .toDouble();
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (value) {
        if (_focused != value) setState(() => _focused = value);
      },
      onKeyEvent: (node, event) {
        final isPress =
            event is KeyDownEvent || event is KeyRepeatEvent;
        if (!isPress) return KeyEventResult.ignored;

        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _change(1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _change(-1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          node.nextFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          node.previousFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
        decoration: BoxDecoration(
          color: _focused
              ? TvColors.red.withOpacity(.09)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _focused ? Colors.white : Colors.transparent,
            width: _focused ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Row(
              textDirection: TextDirection.rtl,
              children: [
                Expanded(
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  widget.display,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            ExcludeFocus(
              child: Slider(
                value: widget.value
                    .clamp(widget.min, widget.max)
                    .toDouble(),
                min: widget.min,
                max: widget.max,
                onChanged: widget.onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopButton extends StatelessWidget {
  const _TopButton({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.40),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withOpacity(.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: TextDirection.rtl,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Icon(icon, size: 25, color: TvColors.red),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_left_rounded,
            color: Colors.white38,
            size: 20,
          ),
        ],
      ),
    );
  }
}
