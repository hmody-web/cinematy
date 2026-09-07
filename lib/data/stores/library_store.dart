import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_item.dart';

class WatchProgress {
  const WatchProgress({required this.mediaId, required this.positionMs, required this.durationMs, required this.updatedAt});
  final String mediaId;
  final int positionMs;
  final int durationMs;
  final DateTime updatedAt;

  double get ratio => durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0).toDouble();

  Map<String, dynamic> toJson() => {
    'mediaId': mediaId,
    'positionMs': positionMs,
    'durationMs': durationMs,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory WatchProgress.fromJson(Map<String, dynamic> json) => WatchProgress(
    mediaId: json['mediaId']?.toString() ?? '',
    positionMs: int.tryParse(json['positionMs']?.toString() ?? '') ?? 0,
    durationMs: int.tryParse(json['durationMs']?.toString() ?? '') ?? 0,
    updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
  );
}

class LibraryStore extends ChangeNotifier {
  static const _favoritesKey = 'cinematy_favorites';
  static const _progressKey = 'cinematy_progress';
  static const _mediaKey = 'cinematy_media_snapshot';
  static const _watchLaterKey = 'cinematy_watch_later';

  final Set<String> _favorites = {};
  final Map<String, WatchProgress> _progress = {};
  final Map<String, MediaItem> _snapshots = {};
  final Set<String> _watchLater = {};
  bool _loaded = false;

  bool get loaded => _loaded;
  Set<String> get favorites => Set.unmodifiable(_favorites);
  Map<String, WatchProgress> get progress => Map.unmodifiable(_progress);

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _favorites.addAll(prefs.getStringList(_favoritesKey) ?? const []);
    _watchLater.addAll(prefs.getStringList(_watchLaterKey) ?? const []);
    try {
      final raw = jsonDecode(prefs.getString(_progressKey) ?? '{}') as Map<String, dynamic>;
      for (final entry in raw.entries) {
        if (entry.value is Map) _progress[entry.key] = WatchProgress.fromJson(Map<String, dynamic>.from(entry.value as Map));
      }
      final media = jsonDecode(prefs.getString(_mediaKey) ?? '{}') as Map<String, dynamic>;
      for (final entry in media.entries) {
        if (entry.value is Map) _snapshots[entry.key] = MediaItem.fromJson(Map<String, dynamic>.from(entry.value as Map));
      }
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  bool isFavorite(String id) => _favorites.contains(id);
  bool isWatchLater(String id) => _watchLater.contains(id);
  WatchProgress? watchProgress(String id) => _progress[id];
  WatchProgress? cardProgress(String id) {
    final p = _progress[id];
    if (p == null || p.positionMs < 60000 || p.ratio >= .97) return null;
    return p;
  }
  MediaItem? snapshot(String id) => _snapshots[id];

  List<MediaItem> favoriteItems() => _favorites.map((id) => _snapshots[id]).whereType<MediaItem>().toList();
  List<MediaItem> watchLaterItems() => _watchLater.map((id) => _snapshots[id]).whereType<MediaItem>().toList();

  List<MediaItem> continueWatching() {
    final entries = _progress.values.where((e) => e.positionMs >= 60000 && e.ratio < .97).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return entries.map((e) => _snapshots[e.mediaId]).whereType<MediaItem>().toList();
  }

  Future<void> toggleFavorite(MediaItem item) async {
    _snapshots[item.id] = item;
    if (!_favorites.add(item.id)) _favorites.remove(item.id);
    notifyListeners();
    await _save();
  }


  Future<void> toggleWatchLater(MediaItem item) async {
    _snapshots[item.id] = item;
    if (!_watchLater.add(item.id)) _watchLater.remove(item.id);
    notifyListeners();
    await _save();
  }

  Future<void> saveProgress(MediaItem item, Duration position, Duration duration) async {
    if (item.id.isEmpty || duration.inMilliseconds <= 0) return;
    _snapshots[item.id] = item;
    _progress[item.id] = WatchProgress(
      mediaId: item.id,
      positionMs: position.inMilliseconds,
      durationMs: duration.inMilliseconds,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
    await _save();
  }

  Future<void> clearProgress(String id) async {
    _progress.remove(id);
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesKey, _favorites.toList());
    await prefs.setStringList(_watchLaterKey, _watchLater.toList());
    await prefs.setString(_progressKey, jsonEncode(_progress.map((k, v) => MapEntry(k, v.toJson()))));
    await prefs.setString(_mediaKey, jsonEncode(_snapshots.map((k, v) => MapEntry(k, v.toJson()))));
  }
}
