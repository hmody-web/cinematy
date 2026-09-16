
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../features/tv/tv_models.dart';
import '../features/tv/xtream_tv_service.dart';
import '../tv_context.dart';
import '../tv_focus.dart';
import '../tv_image.dart';
import '../tv_theme.dart';

class TvLivePlayerScreen extends StatefulWidget {
  const TvLivePlayerScreen({
    super.key,
    required this.channel,
    required this.url,
    this.channels = const <TvChannel>[],
    this.initialIndex = 0,
  });

  final TvChannel channel;
  final String url;
  final List<TvChannel> channels;
  final int initialIndex;

  @override
  State<TvLivePlayerScreen> createState() => _TvLivePlayerScreenState();
}

class _TvLivePlayerScreenState extends State<TvLivePlayerScreen> {
  final FocusNode _rootFocus = FocusNode(debugLabel: 'live-player-root');
  final FocusNode _playFocus = FocusNode(debugLabel: 'live-player-play');
  final FocusNode _favoriteFocus = FocusNode(debugLabel: 'live-player-favorite');
  final FocusNode _backFocus = FocusNode(debugLabel: 'live-player-back');
  final XtreamTvService _service = XtreamTvService();
  final ValueNotifier<bool> _controlsVisible = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _buffering = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _playing = ValueNotifier<bool>(false);

  late final Player _player;
  late final VideoController _videoController;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<bool>? _playingSub;
  Timer? _hideTimer;
  Timer? _playbackGuardTimer;
  bool _userPaused = false;
  bool _openingStream = false;

  late List<TvChannel> _channels;
  late int _index;
  TvChannel? _current;

  @override
  void initState() {
    super.initState();
    _channels = widget.channels.isEmpty ? [widget.channel] : widget.channels;
    _index = widget.initialIndex.clamp(0, _channels.length - 1);
    _current = _channels[_index];

    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 64 * 1024 * 1024,
      ),
    );
    _videoController = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        hwdec: 'auto-safe',
        enableHardwareAcceleration: true,
        androidAttachSurfaceAfterVideoParameters: true,
      ),
    );

    _bufferingSub = _player.stream.buffering.listen((value) {
      _buffering.value = value;
    });
    _playingSub = _player.stream.playing.listen((value) {
      _playing.value = value;
      if (!value && !_userPaused && !_openingStream) {
        unawaited(_keepLivePlaying());
      }
    });
    _startPlaybackGuard();
    unawaited(_openCurrent(first: true));
  }

  void _startPlaybackGuard() {
    _playbackGuardTimer?.cancel();
    _playbackGuardTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || _userPaused || _openingStream) return;
      if (!_player.state.playing) {
        unawaited(_keepLivePlaying());
      }
    });
  }

  Future<void> _keepLivePlaying() async {
    if (!mounted || _userPaused || _openingStream || _player.state.playing) {
      return;
    }
    try {
      await _player.play();
    } catch (_) {
      // Do not refresh/reopen the channel here. Keep the current live session
      // intact and retry play on the next guard tick.
    }
  }

  Future<void> _openCurrent({bool first = false}) async {
    _userPaused = false;
    _openingStream = true;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    final channel = _current ?? widget.channel;
    final url = first && channel.id == widget.channel.id
        ? widget.url
        : _service.streamUrl(channel);
    _buffering.value = true;
    try {
      await _player.open(Media(url), play: true);
    } catch (_) {
      _buffering.value = false;
    } finally {
      _openingStream = false;
    }
    _showControls();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rootFocus.requestFocus();
    });
  }

  void _showControls() {
    _controlsVisible.value = true;
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) _controlsVisible.value = false;
    });
  }

  Future<void> _switchTo(int index) async {
    if (_channels.isEmpty) return;
    final safe = index.clamp(0, _channels.length - 1);
    if (safe == _index) return;
    setState(() {
      _index = safe;
      _current = _channels[safe];
    });
    await _openCurrent();
  }

  KeyEventResult _keys(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.browserBack) {
      if (_controlsVisible.value) {
        _controlsVisible.value = false;
        _rootFocus.requestFocus();
      } else {
        Navigator.of(context).maybePop();
      }
      return KeyEventResult.handled;
    }

    if (_favoriteFocus.hasFocus || _backFocus.hasFocus) {
      if (key == LogicalKeyboardKey.arrowDown) {
        _playFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        _backFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        _favoriteFocus.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (_playFocus.hasFocus) {
      if (key == LogicalKeyboardKey.arrowUp) {
        _favoriteFocus.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      _showControls();
      _playFocus.requestFocus();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      _showControls();
      if (_index > 0) unawaited(_switchTo(_index - 1));
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      _showControls();
      if (_index < _channels.length - 1) {
        unawaited(_switchTo(_index + 1));
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      _showControls();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      if (_player.state.playing) {
        _userPaused = true;
        unawaited(_player.pause());
      } else {
        _userPaused = false;
        unawaited(_player.play());
      }
      _showControls();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _playbackGuardTimer?.cancel();
    unawaited(_bufferingSub?.cancel());
    unawaited(_playingSub?.cancel());
    _controlsVisible.dispose();
    _buffering.dispose();
    _playing.dispose();
    _rootFocus.dispose();
    _playFocus.dispose();
    _favoriteFocus.dispose();
    _backFocus.dispose();
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              RepaintBoundary(
                child: Video(
                  key: const ValueKey('live-video-surface'),
                  controller: _videoController,
                  fit: BoxFit.contain,
                  controls: NoVideoControls,
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: _buffering,
                builder: (context, value, _) => value
                    ? const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: _controlsVisible,
                builder: (context, visible, _) => IgnorePointer(
                  ignoring: !visible,
                  child: AnimatedOpacity(
                    opacity: visible ? 1 : 0,
                    duration: const Duration(milliseconds: 100),
                    child: _overlay(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _overlay() {
    final current = _current ?? widget.channel;
    final start = (_index - 2).clamp(0, _channels.length);
    final end = (_index + 3).clamp(0, _channels.length);
    final nearby = _channels.sublist(start, end);

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xA5000000), Colors.transparent, Color(0x70000000)],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              SizedBox(
                width: 300,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xD90D0D0D),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    children: [
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'القنوات',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: nearby.map((channel) {
                            final actual = _channels.indexOf(channel);
                            final selected = channel.id == current.id;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: TvFocus(
                                autofocus: selected,
                                onPressed: () => unawaited(_switchTo(actual)),
                                child: Container(
                                  padding: const EdgeInsets.all(9),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? TvColors.red.withOpacity(.20)
                                        : Colors.white.withOpacity(.04),
                                    borderRadius: BorderRadius.circular(11),
                                    border: Border.all(
                                      color: selected
                                          ? TvColors.red.withOpacity(.65)
                                          : Colors.transparent,
                                    ),
                                  ),
                                  child: Row(
                                    textDirection: TextDirection.rtl,
                                    children: [
                                      SizedBox(
                                        width: 42,
                                        height: 42,
                                        child: TvImage(channel.icon, cacheWidth: 100, borderRadius: 8),
                                      ),
                                      const SizedBox(width: 9),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              channel.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.right,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                                              ),
                                            ),
                                            if (selected)
                                              const Text(
                                                'أنت هنا الآن',
                                                style: TextStyle(
                                                  color: TvColors.red,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  children: [
                    Row(
                      textDirection: TextDirection.rtl,
                      children: [
                        Expanded(
                          child: Text(
                            current.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                          ),
                        ),
                        TvFocus(
                          focusNode: _favoriteFocus,
                          onPressed: () => tvChannelFavorites.toggle(current),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Icon(
                              tvChannelFavorites.contains(current)
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: tvChannelFavorites.contains(current)
                                  ? TvColors.red
                                  : Colors.white70,
                            ),
                          ),
                        ),
                        TvFocus(
                          focusNode: _backFocus,
                          onPressed: () => Navigator.of(context).maybePop(),
                          child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(Icons.arrow_forward_rounded),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    ValueListenableBuilder<bool>(
                      valueListenable: _playing,
                      builder: (context, playing, _) => TvFocus(
                        focusNode: _playFocus,
                        onPressed: () {
                          if (playing) {
                            _userPaused = true;
                            unawaited(_player.pause());
                          } else {
                            _userPaused = false;
                            unawaited(_player.play());
                          }
                          _showControls();
                        },
                        borderRadius: 999,
                        child: Container(
                          width: 66,
                          height: 66,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(.35),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            size: 42,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
