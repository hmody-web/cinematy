import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/glass_navigation_bar.dart';
import '../shell/cinematy_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const Duration _splashDuration = Duration(seconds: 3);

  late final Player _player;
  late final VideoController _controller;
  StreamSubscription<bool>? _playingSubscription;
  Timer? _exactEndTimer;

  bool _timerStarted = false;
  bool _videoVisible = true;
  bool _finished = false;

  @override
  void initState() {
    super.initState();

    NativeIosTabBarController.setRouteVisible(false);
    NativeAndroidLiquidGlassController.setRouteVisible(false);

    _player = Player();
    _controller = VideoController(_player);

    // Start one fixed 3-second clock only when playback actually starts.
    // We do not depend on media duration/completed callbacks because those can
    // arrive late on some devices.
    _playingSubscription = _player.stream.playing.listen((playing) {
      if (!playing || _timerStarted || _finished) return;
      _timerStarted = true;
      _exactEndTimer = Timer(_splashDuration, _hideAndOpenApp);
    });

    _startVideo();
  }

  Future<void> _startVideo() async {
    try {
      await _player.open(
        Media('asset:///assets/splash/intro.mp4'),
        play: true,
      );
    } catch (_) {
      _hideAndOpenApp();
    }
  }

  void _hideAndOpenApp() {
    if (_finished || !mounted) return;
    _finished = true;
    _exactEndTimer?.cancel();

    // Hide the video immediately at exactly 3 seconds. Navigation happens on
    // the following frame, so any work needed to build CinematyShell can never
    // leave the final video frame hanging on screen.
    setState(() {
      _videoVisible = false;
    });

    _player.pause();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, __, ___) => const CinematyShell(),
        ),
      );
    });
  }

  @override
  void dispose() {
    _exactEndTimer?.cancel();
    _playingSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ColoredBox(
        color: AppColors.background,
        child: Center(
          child: _videoVisible
              ? Video(
                  controller: _controller,
                  fit: BoxFit.contain,
                  controls: NoVideoControls,
                  fill: AppColors.background,
                )
              : const SizedBox.expand(),
        ),
      ),
    );
  }
}
