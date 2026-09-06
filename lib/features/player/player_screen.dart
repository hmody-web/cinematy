import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/media_item.dart';
import '../../data/models/video_source.dart';
import '../../data/services/cinemana_api.dart';
import '../../data/stores/library_store.dart';
import '../../providers.dart';
import '../library/subtitle_settings_screen.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.media, this.localPath});
  final MediaItem media;
  final String? localPath;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> with WidgetsBindingObserver {
  late final Player _player;
  Player? _previewPlayer;
  late final VideoController _controller;
  late final CinemanaApi _api;
  late final LibraryStore _libraryStore;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  Timer? _hideTimer;
  Timer? _previewTimer;
  Timer? _progressTimer;
  Timer? _previewDisposeTimer;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _previewPosition = Duration.zero;
  Duration _positionBeforeScrub = Duration.zero;
  bool _controls = true;
  bool _loading = true;
  bool _scrubbing = false;
  bool _previewReady = false;
  String? _error;
  Uint8List? _previewBytes;

  final LinkedHashMap<int, Uint8List> _previewCache = LinkedHashMap<int, Uint8List>();
  static const int _previewCacheLimit = 12;

  List<VideoSource> _sources = const [];
  List<SubtitleSource> _subtitles = const [];
  VideoSource? _selectedSource;
  SubtitleSource? _selectedSubtitle;
  String? _currentMediaUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _api = ref.read(apiProvider);
    _libraryStore = ref.read(libraryProvider);
    _player = Player();
    _controller = VideoController(_player);

    _positionSub = _player.stream.position.listen((value) {
      if (!mounted || _scrubbing) return;
      setState(() => _position = value);
      if (_duration.inMilliseconds > 0 && value.inMilliseconds >= (_duration.inMilliseconds * .985)) {
        _libraryStore.clearProgress(widget.media.id);
      }
    });
    _durationSub = _player.stream.duration.listen((value) {
      if (mounted) setState(() => _duration = value);
    });

    _progressTimer = Timer.periodic(const Duration(seconds: 8), (_) => _persistProgress());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _persistProgress();
    }
  }

  Future<void> _load() async {
    try {
      if (widget.localPath?.isNotEmpty == true) {
        _currentMediaUrl = widget.localPath!;
        await _player.open(Media(widget.localPath!), play: true);
        await _preparePreview(widget.localPath!);
        try {
          _subtitles = await _api.subtitles(widget.media.id);
        } catch (_) {}
      } else {
        final values = await Future.wait([_api.videoSources(widget.media.id), _api.subtitles(widget.media.id)]);
        _sources = values[0] as List<VideoSource>;
        _subtitles = values[1] as List<SubtitleSource>;
        if (_sources.isEmpty) throw Exception('لم يرجع المصدر رابط تشغيل صالح');
        _selectedSource = _bestSource(_sources);
        await _open(_selectedSource!);
      }

      await _selectArabicByDefault();
      final progress = _libraryStore.watchProgress(widget.media.id);
      if (progress != null && progress.positionMs >= 5000 && progress.ratio < .97) {
        await _player.seek(Duration(milliseconds: progress.positionMs));
        _position = Duration(milliseconds: progress.positionMs);
      }
      _scheduleHide();
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _preparePreview(String url) async {
    _previewDisposeTimer?.cancel();
    _previewReady = false;
    _previewCache.clear();
    final old = _previewPlayer;
    _previewPlayer = null;
    if (old != null) {
      try { await old.dispose(); } catch (_) {}
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
      try { await _previewPlayer?.dispose(); } catch (_) {}
      _previewPlayer = null;
      return null;
    }
  }

  Future<void> _selectArabicByDefault() async {
    if (_subtitles.isEmpty) return;
    SubtitleSource? arabic;
    for (final sub in _subtitles) {
      final label = '${sub.label} ${sub.language} ${sub.url}'.toLowerCase();
      if (label.contains('arab') || label.contains('عرب') || label.contains('_ar.') || label.contains('/ar/') || label.endsWith(' ar')) {
        arabic = sub;
        break;
      }
    }
    arabic ??= _subtitles.first;
    _selectedSubtitle = arabic;
    await _player.setSubtitleTrack(SubtitleTrack.uri(arabic.url, title: _subtitleLabel(arabic, _subtitles.indexOf(arabic)), language: arabic.language));
  }

  VideoSource _bestSource(List<VideoSource> sources) {
    int score(VideoSource s) {
      final q = '${s.quality} ${s.resolution}'.toLowerCase();
      if (q.contains('2160')) return 2160;
      if (q.contains('1080')) return 1080;
      if (q.contains('720')) return 720;
      if (q.contains('480')) return 480;
      if (q.contains('360')) return 360;
      return 1;
    }
    final copy = [...sources]..sort((a, b) => score(b).compareTo(score(a)));
    return copy.first;
  }

  Future<void> _open(VideoSource source) async {
    final wasPlaying = _player.state.playing;
    final oldPosition = _position;
    _currentMediaUrl = source.url;
    await _player.open(Media(source.url), play: true);
    await _preparePreview(source.url);
    if (oldPosition > Duration.zero) await _player.seek(oldPosition);
    if (!wasPlaying && oldPosition > Duration.zero) await _player.pause();
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
      if (mounted && _player.state.playing && !_scrubbing) setState(() => _controls = false);
    });
  }

  Future<void> _seekRelative(int seconds) async {
    final max = _duration.inMilliseconds > 0 ? _duration.inMilliseconds : _position.inMilliseconds + 10000;
    final target = (_position.inMilliseconds + seconds * 1000).clamp(0, max).toInt();
    await _player.seek(Duration(milliseconds: target));
    if (mounted) setState(() => _position = Duration(milliseconds: target));
    _scheduleHide();
  }

  void _doubleTapAt(TapDownDetails details) {
    final width = MediaQuery.sizeOf(context).width;
    // حسب طلب الواجهة العربية: يمين = رجوع 10 ثوانٍ، يسار = تقديم 10 ثوانٍ.
    if (details.localPosition.dx > width / 2) {
      _seekRelative(-10);
    } else {
      _seekRelative(10);
    }
  }

  void _previewAt(double value) {
    final target = Duration(milliseconds: value.toInt());
    if (!_scrubbing) _positionBeforeScrub = _position;
    setState(() {
      _position = target;
      _previewPosition = target;
      _scrubbing = true;
    });
    _previewTimer?.cancel();
    _previewTimer = Timer(const Duration(milliseconds: 110), () => _capturePreview(target));
  }

  Future<void> _capturePreview(Duration target) async {
    if (!_scrubbing) return;
    final previewPlayer = await _ensurePreviewPlayer();
    if (previewPlayer == null || !_scrubbing) return;
    final bucket = target.inSeconds ~/ 5;
    final cached = _previewCache.remove(bucket);
    if (cached != null) {
      _previewCache[bucket] = cached;
      if (mounted && _scrubbing) setState(() => _previewBytes = cached);
      return;
    }
    try {
      await previewPlayer.seek(target);
      // مهلة صغيرة تسمح للمشغل الثانوي بعرض الفريم المطلوب دون لمس المشغل الرئيسي.
      await Future<void>.delayed(const Duration(milliseconds: 45));
      final bytes = await previewPlayer.screenshot(format: 'image/jpeg');
      if (bytes == null || bytes.isEmpty) return;
      _previewCache[bucket] = bytes;
      while (_previewCache.length > _previewCacheLimit) {
        _previewCache.remove(_previewCache.keys.first);
      }
      if (mounted && _scrubbing) setState(() => _previewBytes = bytes);
    } catch (_) {}
  }

  Future<void> _finishScrub(double value) async {
    _previewTimer?.cancel();
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
      if (player != null) { try { await player.dispose(); } catch (_) {} }
    });
    _scheduleHide();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _previewTimer?.cancel();
    _progressTimer?.cancel();
    _previewDisposeTimer?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
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
        return Shadow(color: shadowColor, blurRadius: .45, offset: Offset(d * _cos(a), d * _sin(a)));
      },
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onDoubleTapDown: _doubleTapAt,
        child: Stack(fit: StackFit.expand, children: [
          Video(
            controller: _controller,
            fit: BoxFit.contain,
            controls: NoVideoControls,
            subtitleViewConfiguration: SubtitleViewConfiguration(
              style: TextStyle(
                fontFamily: subtitle.fontFamily,
                fontSize: subtitle.fontSize,
                color: subtitle.textColor,
                height: 1.35,
                shadows: shadows,
                backgroundColor: subtitle.backgroundEnabled ? subtitle.backgroundColor.withOpacity(subtitle.backgroundOpacity) : Colors.transparent,
              ),
              textAlign: TextAlign.center,
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 42),
            ),
          ),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline_rounded, size: 44),
                  const SizedBox(height: 12),
                  const Text('تعذر تشغيل الفيديو', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text('المصدر لم يرجع رابط تشغيل متاح لهذه المادة.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(.55))),
                  const SizedBox(height: 16),
                  FilledButton.tonal(onPressed: () { setState(() { _loading = true; _error = null; }); _load(); }, child: const Text('إعادة المحاولة')),
                ]),
              ),
            ),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: _controls ? 1 : 0,
            child: IgnorePointer(
              ignoring: !_controls,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xB0000000), Color(0x08000000), Color(0xB0000000)], stops: [0, .48, 1]),
                ),
                child: SafeArea(
                  child: Column(children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(children: [
                        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_forward_ios_rounded)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(widget.media.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                            if (widget.media.isSeries && ((widget.media.season ?? 0) > 0 || (widget.media.episode ?? 0) > 0))
                              Text(
                                [if ((widget.media.season ?? 0) > 0) 'الموسم ${widget.media.season}', if ((widget.media.episode ?? 0) > 0) 'الحلقة ${widget.media.episode}'].join(' • '),
                                style: TextStyle(color: Colors.white.withOpacity(.52), fontSize: 11),
                              ),
                          ]),
                        ),
                        IconButton(onPressed: _showSubtitles, icon: const Icon(Icons.subtitles_rounded), tooltip: 'الترجمة'),
                        IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SubtitleSettingsScreen())), icon: const Icon(Icons.text_fields_rounded), tooltip: 'شكل الترجمة'),
                        if (widget.localPath == null) IconButton(onPressed: _showQuality, icon: const Icon(Icons.tune_rounded), tooltip: 'الجودة'),
                      ]),
                    ),
                    const Spacer(),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      _RoundPlayerButton(icon: Icons.replay_10_rounded, size: 52, onTap: () => _seekRelative(-10)),
                      const SizedBox(width: 28),
                      StreamBuilder<bool>(
                        stream: _player.stream.playing,
                        initialData: _player.state.playing,
                        builder: (_, snap) => _RoundPlayerButton(
                          icon: snap.data == true ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          size: 72,
                          filled: true,
                          onTap: () { _player.playOrPause(); _scheduleHide(); },
                        ),
                      ),
                      const SizedBox(width: 28),
                      _RoundPlayerButton(icon: Icons.forward_10_rounded, size: 52, onTap: () => _seekRelative(10)),
                    ]),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
                      child: Column(children: [
                        _ProgressScrubber(
                          position: _position,
                          duration: _duration,
                          scrubbing: _scrubbing,
                          previewBytes: _previewBytes,
                          previewPosition: _previewPosition,
                          fallback: widget.media.backdropUrl.isNotEmpty ? widget.media.backdropUrl : widget.media.posterUrl,
                          onChanged: _previewAt,
                          onChangeEnd: _finishScrub,
                        ),
                        const SizedBox(height: 3),
                        Row(children: [
                          Text('${formatDuration(_position)} / ${formatDuration(_duration)}', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                          const Spacer(),
                          if (_selectedSource != null) Text(_selectedSource!.quality, style: TextStyle(color: Colors.white.withOpacity(.62), fontSize: 11)),
                        ]),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlayerSheet(
        title: 'جودة الفيديو',
        children: _sources.map((source) => RadioListTile<VideoSource>(
          value: source,
          groupValue: _selectedSource,
          title: Text(source.quality),
          subtitle: source.container.isEmpty ? null : Text(source.container),
          onChanged: (value) async {
            if (value == null) return;
            Navigator.pop(context);
            setState(() => _selectedSource = value);
            await _open(value);
          },
        )).toList(),
      ),
    );
  }

  void _showSubtitles() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlayerSheet(
        title: 'الترجمة',
        children: [
          RadioListTile<SubtitleSource?>(
            value: null,
            groupValue: _selectedSubtitle,
            title: const Text('بدون ترجمة'),
            onChanged: (_) async {
              Navigator.pop(context);
              setState(() => _selectedSubtitle = null);
              await _player.setSubtitleTrack(SubtitleTrack.no());
            },
          ),
          ..._subtitles.asMap().entries.map((entry) {
            final sub = entry.value;
            final label = _subtitleLabel(sub, entry.key);
            return RadioListTile<SubtitleSource?>(
              value: sub,
              groupValue: _selectedSubtitle,
              title: Text(label),
              onChanged: (value) async {
                if (value == null) return;
                Navigator.pop(context);
                setState(() => _selectedSubtitle = value);
                await _player.setSubtitleTrack(SubtitleTrack.uri(value.url, title: label, language: value.language));
              },
            );
          }),
        ],
      ),
    );
  }

  String _subtitleLabel(SubtitleSource sub, int index) {
    final raw = '${sub.label} ${sub.language} ${sub.url}'.trim();
    final lower = raw.toLowerCase();
    if (lower.contains('english') || lower.contains('_en.') || lower.contains('/en/') || lower.endsWith(' en')) return 'الإنجليزية';
    if (lower.contains('arab') || lower.contains('عرب') || lower.contains('_ar.') || lower.contains('/ar/') || lower.endsWith(' ar')) {
      final arabicCount = _subtitles.where((s) {
        final x = '${s.label} ${s.language} ${s.url}'.toLowerCase();
        return x.contains('arab') || x.contains('عرب') || x.contains('_ar.') || x.contains('/ar/');
      }).length;
      return arabicCount > 1 ? 'العربية ${index + 1}' : 'العربية';
    }
    return raw.isEmpty ? 'ترجمة ${index + 1}' : (sub.label.isNotEmpty ? sub.label : sub.language);
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

  final Duration position, duration, previewPosition;
  final bool scrubbing;
  final Uint8List? previewBytes;
  final String fallback;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final maxMs = duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
    final value = position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();
    final ratio = maxMs <= 0 ? 0.0 : (value / maxMs).clamp(0.0, 1.0).toDouble();
    return SizedBox(
      height: scrubbing ? 142 : 38,
      child: LayoutBuilder(builder: (context, constraints) {
        const previewWidth = 180.0;
        final usable = (constraints.maxWidth - previewWidth).clamp(0.0, double.infinity).toDouble();
        final left = usable * ratio;
        return Stack(clipBehavior: Clip.none, children: [
          if (scrubbing)
            Positioned(
              left: left,
              top: 0,
              child: _SeekPreview(bytes: previewBytes, position: previewPosition, fallback: fallback),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: Colors.white,
                thumbColor: Colors.white,
                inactiveTrackColor: Colors.white24,
              ),
              child: Slider(min: 0, max: maxMs, value: value, onChanged: onChanged, onChangeEnd: onChangeEnd),
            ),
          ),
        ]);
      }),
    );
  }
}

class _SeekPreview extends StatelessWidget {
  const _SeekPreview({required this.bytes, required this.position, required this.fallback});
  final Uint8List? bytes;
  final Duration position;
  final String fallback;

  @override
  Widget build(BuildContext context) => Container(
        width: 180,
        height: 108,
        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white24), boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 18)]),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          if (bytes != null)
            Image.memory(bytes!, fit: BoxFit.cover, gaplessPlayback: true)
          else if (fallback.isNotEmpty)
            Image.network(fallback, fit: BoxFit.cover)
          else
            const ColoredBox(color: Color(0xFF111111)),
          const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black54]))),
          Positioned(bottom: 7, right: 0, left: 0, child: Text(formatDuration(position), textAlign: TextAlign.center, textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12))),
        ]),
      );
}

class _RoundPlayerButton extends StatelessWidget {
  const _RoundPlayerButton({required this.icon, required this.size, required this.onTap, this.filled = false});
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
              style: IconButton.styleFrom(backgroundColor: filled ? Colors.white : Colors.white.withOpacity(.12), foregroundColor: filled ? AppColors.background : Colors.white),
              icon: Icon(icon, size: filled ? 38 : 28),
            ),
          ),
        ),
      );
}

class _PlayerSheet extends StatelessWidget {
  const _PlayerSheet({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          constraints: const BoxConstraints(maxHeight: 430),
          decoration: BoxDecoration(color: const Color(0xF2151111), borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.white.withOpacity(.10))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Row(children: [
                Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            Flexible(child: ListView(shrinkWrap: true, children: children)),
          ]),
        ),
      );
}
