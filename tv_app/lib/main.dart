import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'tv_app.dart';
import 'tv_context.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // TV-only runtime: no Firebase, no splash video, no native glass, no
  // secondary preview players. Keep both Dart heap and GPU texture pressure low.
  PaintingBinding.instance.imageCache.maximumSize = 110;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 48 << 20;

  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await Future.wait([
    tvLibrary.load(),
    tvDownloads.load(),
    tvPlaybackPreferences.load(),
    tvChannelFavorites.load(),
  ]);

  runApp(const CinematyTvApp());
}
