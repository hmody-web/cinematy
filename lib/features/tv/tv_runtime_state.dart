import 'package:flutter/foundation.dart';

/// True while the live-TV player is on screen.
///
/// The TV section uses this only when low-end optimization is enabled, so
/// scoreboard artwork/timers can sleep completely behind the player without
/// changing stream quality or decoder settings.
final ValueNotifier<bool> tvLivePlaybackActive = ValueNotifier<bool>(false);
