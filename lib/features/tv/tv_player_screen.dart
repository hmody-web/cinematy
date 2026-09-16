import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/network_image.dart';
import 'tv_ios_native_video.dart';
import 'tv_models.dart';
import 'tv_system_pip.dart';
import 'xtream_tv_service.dart';

class TvPlayerScreen extends StatefulWidget {
  const TvPlayerScreen({
    super.key,
    required this.channel,
    required this.channels,
    required this.service,
  });

  final TvChannel channel;
  final List<TvChannel> channels;
  final XtreamTvService service;

  @override
  State<TvPlayerScreen> createState() => _TvPlayerScreenState();
}

class _TvPlayerScreenState extends State<TvPlayerScreen>
    with WidgetsBindingObserver {
  Player? _player;
  VideoController? _videoController;
  final TvIosNativeVideoController _iosController = TvIosNativeVideoController();
  final TextEditingController _searchController = TextEditingController();

  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _pipSub;

  late TvChannel _current;
  bool _buffering = true;
  bool _playing = true;
  bool _pipMode = false;
  bool _showControls = true;
  bool _showRail = false;
  Timer? _controlsTimer;
  Timer? _playbackGuardTimer;
  bool _searching = false;
  String _query = '';
  bool _userPaused = false;
  bool _openingStream = false;

  bool get _isIOS => !kIsWeb && Platform.isIOS;
  String get _streamUrl => widget.service.streamUrl(_current);

  Future<void> _enterTrueFullscreen() async {
    // Hide both the Android status bar and navigation/gesture bar.
    // immersiveSticky keeps video edge-to-edge and only reveals system UI
    // temporarily when the user explicitly swipes from an edge.
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _restoreSystemUi() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enterTrueFullscreen();
    _current = widget.channel;

    if (!_isIOS) {
      final player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 64 * 1024 * 1024,
        ),
      );
      _player = player;
      _videoController = VideoController(
        player,
        configuration: const VideoControllerConfiguration(
          hwdec: 'auto-safe',
          enableHardwareAcceleration: true,
          androidAttachSurfaceAfterVideoParameters: true,
        ),
      );
      _bufferingSub = player.stream.buffering.listen((value) {
        if (mounted) setState(() => _buffering = value);
      });
      _playingSub = player.stream.playing.listen((value) {
        if (mounted) setState(() => _playing = value);
        if (!value && !_userPaused && !_openingStream) {
          unawaited(_keepLivePlaying());
        }
      });
      _startPlaybackGuard();
      _openCurrent();
    } else {
      _buffering = false;
    }

    TvSystemPip.setActive(true);
    _pipSub = TvSystemPip.state.listen((value) {
      if (!mounted) return;
      setState(() {
        _pipMode = value;
        if (value) {
          _showControls = false;
          _showRail = false;
        } else {
          _showControls = true;
        }
      });
      if (!value) {
        _enterTrueFullscreen();
        _scheduleControlsHide();
      }
    });

    _scheduleControlsHide();
  }

  void _startPlaybackGuard() {
    _playbackGuardTimer?.cancel();
    _playbackGuardTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || _isIOS || _userPaused || _openingStream) return;
      final player = _player;
      if (player == null) return;
      if (!player.state.playing) {
        unawaited(_keepLivePlaying());
      }
    });
  }

  Future<void> _keepLivePlaying() async {
    if (!mounted || _isIOS || _userPaused || _openingStream) return;
    final player = _player;
    if (player == null || player.state.playing) return;
    try {
      await player.play();
    } catch (_) {
      // Keep the current stream/session untouched. The guard will retry play
      // without reopening or refreshing the channel.
    }
  }

  void _scheduleControlsHide() {
    _controlsTimer?.cancel();
    if (_pipMode || !_showControls) return;
    _controlsTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || _pipMode) return;
      setState(() {
        _showControls = false;
        _showRail = false;
        _searching = false;
        _query = '';
        _searchController.clear();
      });
    });
  }

  void _markInteraction() {
    if (_pipMode) return;
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    _scheduleControlsHide();
  }

  void _toggleControls() {
    if (_pipMode) return;
    _controlsTimer?.cancel();
    setState(() {
      _showControls = !_showControls;
      if (!_showControls) {
        _showRail = false;
        _searching = false;
        _query = '';
        _searchController.clear();
      }
    });
    if (_showControls) _scheduleControlsHide();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_pipMode) {
      _enterTrueFullscreen();
    }

    // On iOS the actual player is a native AVPlayerLayer. Starting PiP while
    // the app transitions away gives the same system window behavior users
    // expect from premium video apps. Android auto-enter is handled natively.
    if (_isIOS &&
        (state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused) &&
        _playing) {
      _iosController.startPip();
    }
  }

  Future<void> _openCurrent() async {
    _userPaused = false;
    _openingStream = true;
    if (_isIOS) {
      if (_iosController.isAttached) {
        await _iosController.open(_streamUrl);
      }
      if (mounted) {
        setState(() {
          _playing = true;
          _buffering = false;
        });
      }
      _openingStream = false;
      return;
    }

    try {
      setState(() {
        _buffering = true;
      });
      await _player!.open(Media(_streamUrl), play: true);
    } catch (e) {
      if (mounted) setState(() => _buffering = false);
    } finally {
      _openingStream = false;
    }
  }

  Future<void> _switchChannel(TvChannel channel) async {
    if (channel.id == _current.id) return;
    setState(() {
      _current = channel;
      _buffering = true;
      _showRail = false;
      _searching = false;
      _query = '';
      _searchController.clear();
    });
    _scheduleControlsHide();
    await _openCurrent();
  }

  Future<void> _togglePlay() async {
    if (_isIOS) {
      if (_playing) {
        _userPaused = true;
        await _iosController.pause();
      } else {
        _userPaused = false;
        await _iosController.play();
      }
      if (mounted) setState(() => _playing = !_playing);
      return;
    }

    final player = _player;
    if (player == null) return;
    if (player.state.playing) {
      _userPaused = true;
      await player.pause();
    } else {
      _userPaused = false;
      await player.play();
    }
  }

  Future<void> _enterPip() async {
    if (_isIOS) {
      await _iosController.startPip();
    } else {
      await TvSystemPip.enter();
    }
  }

  List<TvChannel> get _visibleChannels {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.channels;
    return widget.channels
        .where((item) => item.name.toLowerCase().contains(q))
        .toList(growable: false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    TvSystemPip.setActive(false);
    if (_isIOS) _iosController.stopPip();
    _bufferingSub?.cancel();
    _playingSub?.cancel();
    _pipSub?.cancel();
    _controlsTimer?.cancel();
    _playbackGuardTimer?.cancel();
    _searchController.dispose();
    _player?.dispose();
    unawaited(_restoreSystemUi());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final railWidth = MediaQuery.sizeOf(context).width < 520 ? 112.0 : 146.0;

    return PopScope(
      canPop: !_pipMode,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          top: false,
          bottom: false,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            // Do not reveal controls on pointer-down. Otherwise a hidden UI
            // becomes visible before the tap callback runs, and the same tap
            // immediately toggles it off again. While controls are already
            // visible, any touch only refreshes the 5-second inactivity timer.
            onPointerDown: (_) {
              if (_showControls && !_pipMode) {
                _scheduleControlsHide();
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Keep the native/video surface completely passive for gestures.
                // A separate transparent hit layer above it guarantees that a
                // *single tap* is received even when iOS uses a PlatformView.
                Positioned.fill(
                  child: _buildVideo(),
                ),
                if (!_pipMode)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _toggleControls,
                      child: const ColoredBox(color: Colors.transparent),
                    ),
                  ),
                if (!_pipMode && _showControls) ...[
                  _TopOverlay(
                    channel: _current,
                    railVisible: _showRail,
                    onBack: () {
                      _markInteraction();
                      Navigator.of(context).pop();
                    },
                    onPip: () {
                      _markInteraction();
                      _enterPip();
                    },
                    onRail: () {
                      _markInteraction();
                      setState(() {
                        _showRail = !_showRail;
                        if (!_showRail) {
                          _searching = false;
                          _query = '';
                          _searchController.clear();
                        }
                      });
                      _scheduleControlsHide();
                    },
                  ),
                  Positioned(
                    bottom: 22 + MediaQuery.paddingOf(context).bottom,
                    left: 0,
                    right: _showRail ? railWidth : 0,
                    child: Center(
                      child: _PlaybackButton(
                        playing: _playing,
                        onTap: () {
                          _markInteraction();
                          _togglePlay();
                        },
                      ),
                    ),
                  ),
                  if (_showRail)
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: railWidth,
                      child: _ChannelRail(
                        channels: _visibleChannels,
                        selected: _current,
                        searching: _searching,
                        searchController: _searchController,
                        onSearchToggle: () {
                          _markInteraction();
                          setState(() {
                            _searching = !_searching;
                            if (!_searching) {
                              _query = '';
                              _searchController.clear();
                            }
                          });
                          _scheduleControlsHide();
                        },
                        onSearch: (value) {
                          _markInteraction();
                          setState(() => _query = value);
                        },
                        onSelect: (channel) {
                          _markInteraction();
                          _switchChannel(channel);
                        },
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideo() {
    if (_isIOS) {
      return ColoredBox(
        color: Colors.black,
        child: TvIosNativeVideo(
          url: _streamUrl,
          controller: _iosController,
        ),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_videoController != null)
            Video(
              controller: _videoController!,
              fit: BoxFit.contain,
              controls: NoVideoControls,
            ),
          if (_buffering)
            const Center(
              child: SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ),
        ],
      ),
    );
  }
}

class _TopOverlay extends StatelessWidget {
  const _TopOverlay({
    required this.channel,
    required this.railVisible,
    required this.onBack,
    required this.onPip,
    required this.onRail,
  });

  final TvChannel channel;
  final bool railVisible;
  final VoidCallback onBack;
  final VoidCallback onPip;
  final VoidCallback onRail;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          10,
          MediaQuery.paddingOf(context).top + 8,
          10,
          26,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xD9000000), Color(0x00000000)],
          ),
        ),
        child: Row(
          children: [
            _RoundButton(icon: Icons.arrow_back_ios_new_rounded, onTap: onBack),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'بث مباشر',
                    style: TextStyle(
                      color: Colors.white.withOpacity(.58),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            _RoundButton(icon: Icons.picture_in_picture_alt_rounded, onTap: onPip),
            const SizedBox(width: 7),
            _RoundButton(
              icon: railVisible ? Icons.view_sidebar_rounded : Icons.view_stream_rounded,
              onTap: onRail,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(.52),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 19),
        ),
      ),
    );
  }
}

class _PlaybackButton extends StatelessWidget {
  const _PlaybackButton({required this.playing, required this.onTap});
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(.58),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 54,
          height: 54,
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 31,
          ),
        ),
      ),
    );
  }
}

class _ChannelRail extends StatelessWidget {
  const _ChannelRail({
    required this.channels,
    required this.selected,
    required this.searching,
    required this.searchController,
    required this.onSearchToggle,
    required this.onSearch,
    required this.onSelect,
  });

  final List<TvChannel> channels;
  final TvChannel selected;
  final bool searching;
  final TextEditingController searchController;
  final VoidCallback onSearchToggle;
  final ValueChanged<String> onSearch;
  final ValueChanged<TvChannel> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xE3120E0E),
        border: Border(
          left: BorderSide(color: Colors.white.withOpacity(.07)),
        ),
      ),
      child: SafeArea(
        left: false,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      searching ? 'بحث' : 'القنوات',
                      maxLines: 1,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: onSearchToggle,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(searching ? Icons.close_rounded : Icons.search_rounded, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            if (searching)
              Padding(
                padding: const EdgeInsets.fromLTRB(7, 5, 7, 6),
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: searchController,
                    autofocus: true,
                    onChanged: onSearch,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      hintText: 'اسم القناة',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 0),
                      filled: true,
                      fillColor: Colors.white.withOpacity(.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(11),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
            Divider(height: 1, color: Colors.white.withOpacity(.07)),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(6, 7, 6, 18),
                itemCount: channels.length,
                itemBuilder: (context, index) {
                  final item = channels[index];
                  final active = item.id == selected.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Material(
                      color: active
                          ? AppColors.redBright.withOpacity(.16)
                          : Colors.white.withOpacity(.025),
                      borderRadius: BorderRadius.circular(13),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => onSelect(item),
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: Column(
                            children: [
                              AspectRatio(
                                aspectRatio: 16 / 9,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(.32),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: CinematyNetworkImage(
                                    url: item.icon,
                                    fit: BoxFit.contain,
                                    memCacheWidth: 220,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                item.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 8.5,
                                  height: 1.2,
                                  fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                                  color: active ? Colors.white : Colors.white.withOpacity(.7),
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
          ],
        ),
      ),
    );
  }
}
