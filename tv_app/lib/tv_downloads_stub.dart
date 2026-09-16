import 'package:flutter/foundation.dart';

import 'data/models/media_item.dart';
import 'data/models/video_source.dart';

class TvDownloadedSubtitle {
  const TvDownloadedSubtitle({
    required this.localPath,
    required this.language,
    required this.label,
  });

  final String localPath;
  final String language;
  final String label;
}

class TvDownloadedItem {
  const TvDownloadedItem({
    required this.id,
    required this.media,
    required this.localPath,
    required this.quality,
    required this.createdAt,
    this.subtitles = const <TvDownloadedSubtitle>[],
  });

  final String id;
  final MediaItem media;
  final String localPath;
  final String quality;
  final DateTime createdAt;
  final List<TvDownloadedSubtitle> subtitles;
}

class TvActiveDownload {
  const TvActiveDownload({
    required this.media,
    required this.progress,
    required this.isPaused,
  });

  final MediaItem media;
  final double progress;
  final bool isPaused;
}

class TvDownloadStore extends ChangeNotifier {
  List<TvDownloadedItem> get items => const [];
  List<TvActiveDownload> get activeItems => const [];
  bool isDownloaded(String id) => false;
  bool isDownloading(String id) => false;
  bool isPaused(String id) => false;
  double progressOf(String id) => 0;
  TvDownloadedItem? itemFor(String id) => null;

  Future<void> load() async {}

  Future<void> download(
    MediaItem media,
    VideoSource source, {
    List<SubtitleSource> subtitles = const <SubtitleSource>[],
  }) async {
    throw UnsupportedError(
      'التنزيل متاح في نسخة Android TV النهائية فقط.',
    );
  }

  Future<void> pause(String id) async {}
  Future<void> resume(String id) async {}
  Future<void> cancel(String id) async {}
  Future<void> remove(String id) async {}
}
