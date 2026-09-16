import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Map<String, dynamic> toJson() => {
        'localPath': localPath,
        'language': language,
        'label': label,
      };

  factory TvDownloadedSubtitle.fromJson(Map<String, dynamic> json) =>
      TvDownloadedSubtitle(
        localPath: '${json['localPath'] ?? ''}',
        language: '${json['language'] ?? 'العربية'}',
        label: '${json['label'] ?? ''}',
      );
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'media': media.toJson(),
        'localPath': localPath,
        'quality': quality,
        'createdAt': createdAt.toIso8601String(),
        'subtitles': subtitles.map((e) => e.toJson()).toList(),
      };

  factory TvDownloadedItem.fromJson(Map<String, dynamic> json) =>
      TvDownloadedItem(
        id: '${json['id'] ?? ''}',
        media: MediaItem.fromJson(
          Map<String, dynamic>.from((json['media'] as Map?) ?? const {}),
        ),
        localPath: '${json['localPath'] ?? ''}',
        quality: '${json['quality'] ?? 'تلقائي'}',
        createdAt:
            DateTime.tryParse('${json['createdAt'] ?? ''}') ?? DateTime.now(),
        subtitles: ((json['subtitles'] as List?) ?? const [])
            .whereType<Map>()
            .map(
              (e) => TvDownloadedSubtitle.fromJson(
                Map<String, dynamic>.from(e),
              ),
            )
            .toList(growable: false),
      );
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

class _TvDownloadJob {
  _TvDownloadJob({
    required this.media,
    required this.source,
    required this.subtitles,
    required this.partFile,
    required this.finalFile,
  });

  final MediaItem media;
  final VideoSource source;
  final List<SubtitleSource> subtitles;
  final File partFile;
  final File finalFile;
}

class TvDownloadStore extends ChangeNotifier {
  static const _key = 'cinematy_tv_downloads_v2';

  final Dio _dio = Dio();
  final Map<String, TvDownloadedItem> _items = {};
  final Map<String, TvActiveDownload> _active = {};
  final Map<String, _TvDownloadJob> _jobs = {};
  final Map<String, CancelToken> _tokens = {};
  final Set<String> _paused = <String>{};
  final Set<String> _cancelled = <String>{};

  List<TvDownloadedItem> get items {
    final result = _items.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  List<TvActiveDownload> get activeItems =>
      _active.values.toList(growable: false);

  bool isDownloaded(String id) => _items.containsKey(id);
  bool isDownloading(String id) => _active.containsKey(id);
  bool isPaused(String id) => _active[id]?.isPaused ?? false;
  double progressOf(String id) => _active[id]?.progress ?? 0;
  TvDownloadedItem? itemFor(String id) => _items[id];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = jsonDecode(
        prefs.getString(_key) ??
            prefs.getString('cinematy_tv_downloads_v1') ??
            '[]',
      );
      if (raw is List) {
        for (final value in raw.whereType<Map>()) {
          final item = TvDownloadedItem.fromJson(
            Map<String, dynamic>.from(value),
          );
          if (item.id.isNotEmpty &&
              item.localPath.isNotEmpty &&
              File(item.localPath).existsSync()) {
            _items[item.id] = item;
          }
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> download(
    MediaItem media,
    VideoSource source, {
    List<SubtitleSource> subtitles = const <SubtitleSource>[],
  }) async {
    if (media.id.isEmpty ||
        source.url.isEmpty ||
        isDownloading(media.id) ||
        isDownloaded(media.id)) {
      return;
    }

    final urlPath = Uri.tryParse(source.url)?.path.toLowerCase() ?? '';
    if (urlPath.endsWith('.m3u8')) {
      throw StateError('هذه الجودة بث HLS وليست ملف تنزيل مباشر.');
    }

    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}CinematyTV'
      '${Platform.pathSeparator}Downloads',
    );
    if (!await dir.exists()) await dir.create(recursive: true);

    final extension = _extension(source.url);
    final safeId = _safe(media.id);
    final safeQuality = _safe(
      source.quality.isEmpty ? 'auto' : source.quality,
    );
    final finalFile = File(
      '${dir.path}${Platform.pathSeparator}$safeId-$safeQuality.$extension',
    );
    final partFile = File('${finalFile.path}.part');

    final job = _TvDownloadJob(
      media: media,
      source: source,
      subtitles: subtitles,
      partFile: partFile,
      finalFile: finalFile,
    );

    _jobs[media.id] = job;
    _paused.remove(media.id);
    _cancelled.remove(media.id);
    _active[media.id] = TvActiveDownload(
      media: media,
      progress: 0,
      isPaused: false,
    );
    notifyListeners();

    unawaited(_run(job));
  }

  Future<void> pause(String id) async {
    if (!_active.containsKey(id) || _paused.contains(id)) return;
    _paused.add(id);
    final current = _active[id]!;
    _active[id] = TvActiveDownload(
      media: current.media,
      progress: current.progress,
      isPaused: true,
    );
    _tokens[id]?.cancel('pause');
    notifyListeners();
  }

  Future<void> resume(String id) async {
    final job = _jobs[id];
    if (job == null || !_paused.contains(id)) return;

    _paused.remove(id);
    final current = _active[id];
    _active[id] = TvActiveDownload(
      media: current?.media ?? job.media,
      progress: current?.progress ?? 0,
      isPaused: false,
    );
    notifyListeners();
    unawaited(_run(job));
  }

  Future<void> cancel(String id) async {
    _cancelled.add(id);
    _paused.remove(id);
    _tokens[id]?.cancel('cancel');
    final job = _jobs.remove(id);

    if (job != null) {
      try {
        if (await job.partFile.exists()) await job.partFile.delete();
      } catch (_) {}
    }

    _active.remove(id);
    notifyListeners();
  }

  Future<void> _run(_TvDownloadJob job) async {
    final id = job.media.id;
    if (_cancelled.contains(id) || _paused.contains(id)) return;

    final token = CancelToken();
    _tokens[id] = token;
    RandomAccessFile? raf;

    try {
      var existing =
          await job.partFile.exists() ? await job.partFile.length() : 0;

      final response = await _dio.get<ResponseBody>(
        job.source.url,
        cancelToken: token,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 45),
          headers: existing > 0 ? {'Range': 'bytes=$existing-'} : null,
        ),
      );

      final status = response.statusCode ?? 200;
      if (existing > 0 && status != 206) {
        try {
          await job.partFile.delete();
        } catch (_) {}
        existing = 0;
      }

      final remaining =
          int.tryParse(response.headers.value(Headers.contentLengthHeader) ?? '');
      final total = remaining == null || remaining <= 0
          ? 0
          : existing + remaining;

      raf = await job.partFile.open(
        mode: existing > 0 ? FileMode.append : FileMode.write,
      );

      var received = existing;
      final stream = response.data?.stream;
      if (stream == null) throw StateError('EMPTY_DOWNLOAD_STREAM');

      await for (final chunk in stream) {
        if (_cancelled.contains(id)) throw StateError('DOWNLOAD_CANCELLED');
        if (_paused.contains(id)) throw StateError('DOWNLOAD_PAUSED');

        await raf.writeFrom(chunk);
        received += chunk.length;

        final progress =
            total > 0 ? (received / total).clamp(0.0, 1.0).toDouble() : 0.0;
        _active[id] = TvActiveDownload(
          media: job.media,
          progress: progress,
          isPaused: false,
        );
        notifyListeners();
      }

      await raf.close();
      raf = null;

      if (_paused.contains(id) || _cancelled.contains(id)) return;

      if (await job.finalFile.exists()) {
        await job.finalFile.delete();
      }
      await job.partFile.rename(job.finalFile.path);

      final downloadedSubtitles =
          await _downloadSubtitles(job, job.finalFile.parent);

      _items[id] = TvDownloadedItem(
        id: id,
        media: job.media,
        localPath: job.finalFile.path,
        quality: job.source.quality,
        createdAt: DateTime.now(),
        subtitles: downloadedSubtitles,
      );

      _active.remove(id);
      _jobs.remove(id);
      _tokens.remove(id);
      await _save();
      notifyListeners();
    } on DioException catch (error) {
      try {
        await raf?.close();
      } catch (_) {}

      if (CancelToken.isCancel(error)) return;

      if (!_paused.contains(id) && !_cancelled.contains(id)) {
        _active.remove(id);
        _jobs.remove(id);
        try {
          if (await job.partFile.exists()) await job.partFile.delete();
        } catch (_) {}
        notifyListeners();
      }
    } catch (_) {
      try {
        await raf?.close();
      } catch (_) {}

      if (_paused.contains(id) || _cancelled.contains(id)) return;

      _active.remove(id);
      _jobs.remove(id);
      try {
        if (await job.partFile.exists()) await job.partFile.delete();
      } catch (_) {}
      notifyListeners();
    } finally {
      if (_tokens[id] == token) _tokens.remove(id);
    }
  }

  Future<List<TvDownloadedSubtitle>> _downloadSubtitles(
    _TvDownloadJob job,
    Directory dir,
  ) async {
    if (job.subtitles.isEmpty) return const <TvDownloadedSubtitle>[];

    final result = <TvDownloadedSubtitle>[];
    final safeId = _safe(job.media.id);

    for (var i = 0; i < job.subtitles.length; i++) {
      final source = job.subtitles[i];
      final url = source.url.trim();
      if (url.isEmpty) continue;

      try {
        final extension = _subtitleExtension(url);
        final file = File(
          '${dir.path}${Platform.pathSeparator}'
          '$safeId-subtitle-$i.$extension',
        );
        await _dio.download(
          url,
          file.path,
          options: Options(
            followRedirects: true,
            receiveTimeout: const Duration(minutes: 5),
          ),
        );
        if (await file.exists() && await file.length() > 0) {
          result.add(
            TvDownloadedSubtitle(
              localPath: file.path,
              language: source.language,
              label: source.label,
            ),
          );
        }
      } catch (_) {}
    }

    return result;
  }

  Future<void> remove(String id) async {
    await cancel(id);

    final item = _items.remove(id);
    if (item != null) {
      try {
        final file = File(item.localPath);
        if (await file.exists()) await file.delete();
      } catch (_) {}

      for (final subtitle in item.subtitles) {
        try {
          final file = File(subtitle.localPath);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }

      await _save();
      notifyListeners();
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(_items.values.map((e) => e.toJson()).toList()),
    );
  }

  String _safe(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  String _extension(String url) {
    final segments = Uri.tryParse(url)?.pathSegments ?? const <String>[];
    final last = segments.isEmpty ? '' : segments.last;
    if (last.contains('.')) {
      final ext = last.split('.').last.toLowerCase();
      if (ext.isNotEmpty && ext.length <= 5) return ext;
    }
    return 'mp4';
  }

  String _subtitleExtension(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    if (path.endsWith('.vtt')) return 'vtt';
    if (path.endsWith('.ass')) return 'ass';
    return 'srt';
  }
}
