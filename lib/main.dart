import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  MediaKit.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSize = 180;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 64 << 20;
  runApp(const ProviderScope(child: CinematyApp()));
}
