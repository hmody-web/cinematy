import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/download_item.dart';
import '../models/media_item.dart';
import '../models/video_source.dart';

class ActiveDownload {
  const ActiveDownload({required this.media, required this.quality, required this.progress});
  final MediaItem media;
  final String quality;
  final double progress;
}

class DownloadStore extends ChangeNotifier {
  static const _key = 'cinematy_downloads_v2';
  final Dio _dio = Dio();
  final Map<String, DownloadItem> _items = {};
  final Map<String, ActiveDownload> _active = {};
  bool _loaded = false;

  List<DownloadItem> get items {
    final list = _items.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  List<ActiveDownload> get activeItems => _active.values.toList();
  bool isDownloading(String id) => _active.containsKey(id);
  bool isDownloaded(String id) => _items.containsKey(id);
  double progressOf(String id) => _active[id]?.progress ?? 0;
  DownloadItem? itemFor(String id) => _items[id];

  Future<void> load() async {
    if (_loaded) return;
    final p = await SharedPreferences.getInstance();
    try {
      final raw = jsonDecode(p.getString(_key) ?? p.getString('cinematy_downloads_v1') ?? '[]') as List;
      for (final e in raw.whereType<Map>()) {
        final item = DownloadItem.fromJson(Map<String, dynamic>.from(e));
        if (item.id.isNotEmpty && File(item.localPath).existsSync()) _items[item.id] = item;
      }
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  Future<void> download(MediaItem media, VideoSource source) async {
    if (media.id.isEmpty || source.url.isEmpty || _active.containsKey(media.id)) return;
    if (_items.containsKey(media.id)) return;

    final uri = Uri.tryParse(source.url);
    final path = uri?.path.toLowerCase() ?? '';
    if (path.endsWith('.m3u8')) {
      throw StateError('هذه الجودة تعمل كبث HLS وليست ملف تنزيل مباشر حالياً.');
    }

    _active[media.id] = ActiveDownload(media: media, quality: source.quality, progress: 0);
    notifyListeners();

    try {
      final dir = await getApplicationDocumentsDirectory();
      final downloads = Directory('${dir.path}${Platform.pathSeparator}downloads');
      if (!await downloads.exists()) await downloads.create(recursive: true);
      final ext = _extension(source.url, source.container);
      final safeId = media.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final safeQuality = source.quality.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final file = File('${downloads.path}${Platform.pathSeparator}$safeId-$safeQuality.$ext');

      await _dio.download(
        source.url,
        file.path,
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          _active[media.id] = ActiveDownload(media: media, quality: source.quality, progress: (received / total).clamp(0.0, 1.0).toDouble());
          notifyListeners();
        },
        options: Options(followRedirects: true, receiveTimeout: const Duration(minutes: 30)),
      );

      _items[media.id] = DownloadItem(
        id: media.id,
        media: media,
        localPath: file.path,
        quality: source.quality,
        createdAt: DateTime.now(),
      );
      await _save();
    } finally {
      _active.remove(media.id);
      notifyListeners();
    }
  }

  Future<void> remove(String id) async {
    final item = _items.remove(id);
    if (item != null) {
      try {
        await File(item.localPath).delete();
      } catch (_) {}
      await _save();
      notifyListeners();
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(_items.values.map((e) => e.toJson()).toList()));
  }

  String _extension(String url, String container) {
    final c = container.replaceAll('.', '').trim().toLowerCase();
    if (c.isNotEmpty && c.length <= 5) return c;
    final segments = Uri.tryParse(url)?.pathSegments ?? const <String>[];
    final s = segments.isEmpty ? '' : segments.last;
    if (s.contains('.')) {
      final ext = s.split('.').last.toLowerCase();
      if (ext.length <= 5) return ext;
    }
    return 'mp4';
  }
}
