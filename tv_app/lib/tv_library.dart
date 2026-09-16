import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/models/media_item.dart';

class TvLibraryStore extends ChangeNotifier {
  static const _favoritesKey = 'tv_favorites_v1';
  static const _watchLaterKey = 'tv_watch_later_v1';
  static const _snapshotsKey = 'tv_snapshots_v1';
  static const _progressKey = 'tv_progress_v1';

  final Set<String> _favorites = <String>{};
  final Set<String> _watchLater = <String>{};
  final Map<String, MediaItem> _snapshots = <String, MediaItem>{};
  final Map<String, TvProgress> _progress = <String, TvProgress>{};

  bool isFavorite(String id) => _favorites.contains(id);
  bool isWatchLater(String id) => _watchLater.contains(id);
  TvProgress? progress(String id) => _progress[id];

  List<MediaItem> get favorites => _favorites
      .map((id) => _snapshots[id])
      .whereType<MediaItem>()
      .toList(growable: false);

  List<MediaItem> get watchLater => _watchLater
      .map((id) => _snapshots[id])
      .whereType<MediaItem>()
      .toList(growable: false);

  List<MediaItem> get continueWatching {
    final ids = _progress.entries
        .where((e) => e.value.positionMs >= 60000 && e.value.ratio < .96)
        .toList()
      ..sort((a, b) => b.value.updatedAt.compareTo(a.value.updatedAt));
    return ids
        .map((e) => _snapshots[e.key])
        .whereType<MediaItem>()
        .toList(growable: false);
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _favorites
      ..clear()
      ..addAll(prefs.getStringList(_favoritesKey) ?? const <String>[]);
    _watchLater
      ..clear()
      ..addAll(prefs.getStringList(_watchLaterKey) ?? const <String>[]);
    try {
      final snapshots = jsonDecode(prefs.getString(_snapshotsKey) ?? '{}');
      if (snapshots is Map) {
        for (final entry in snapshots.entries) {
          if (entry.value is Map) {
            _snapshots['${entry.key}'] = MediaItem.fromJson(
              Map<String, dynamic>.from(entry.value as Map),
            );
          }
        }
      }
      final progress = jsonDecode(prefs.getString(_progressKey) ?? '{}');
      if (progress is Map) {
        for (final entry in progress.entries) {
          if (entry.value is Map) {
            _progress['${entry.key}'] = TvProgress.fromJson(
              Map<String, dynamic>.from(entry.value as Map),
            );
          }
        }
      }
    } catch (_) {}
    notifyListeners();
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
    _progress[item.id] = TvProgress(
      positionMs: position.inMilliseconds,
      durationMs: duration.inMilliseconds,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setStringList(_favoritesKey, _favorites.toList()),
      prefs.setStringList(_watchLaterKey, _watchLater.toList()),
      prefs.setString(
        _snapshotsKey,
        jsonEncode(_snapshots.map((k, v) => MapEntry(k, v.toJson()))),
      ),
      prefs.setString(
        _progressKey,
        jsonEncode(_progress.map((k, v) => MapEntry(k, v.toJson()))),
      ),
    ]);
  }
}

class TvProgress {
  const TvProgress({required this.positionMs, required this.durationMs, required this.updatedAt});
  final int positionMs;
  final int durationMs;
  final DateTime updatedAt;
  double get ratio => durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0).toDouble();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'positionMs': positionMs,
        'durationMs': durationMs,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory TvProgress.fromJson(Map<String, dynamic> json) => TvProgress(
        positionMs: int.tryParse('${json['positionMs'] ?? 0}') ?? 0,
        durationMs: int.tryParse('${json['durationMs'] ?? 0}') ?? 0,
        updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}') ?? DateTime.now(),
      );
}
