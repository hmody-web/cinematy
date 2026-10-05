import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
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
  // Keep already-decoded posters in memory while the user moves between
  // Home, search and details. Disk caching handles longer-term persistence.
  PaintingBinding.instance.imageCache.maximumSize = kIsWeb ? 1600 : 1000;
  PaintingBinding.instance.imageCache.maximumSizeBytes = (kIsWeb ? 256 : 192) << 20;
  runApp(const ProviderScope(child: CinematyApp()));
}
