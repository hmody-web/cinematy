import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_item.dart';
import '../services/cinematy_account_api.dart';

class WatchProgress {
  const WatchProgress({
    required this.mediaId,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
  });

  final String mediaId;
  final int positionMs;
  final int durationMs;
  final DateTime updatedAt;

  double get ratio => durationMs <= 0
      ? 0
      : (positionMs / durationMs).clamp(0.0, 1.0).toDouble();

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
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}

class _PendingFavoriteOperation {
  const _PendingFavoriteOperation({
    required this.uid,
    required this.action,
    required this.item,
  });

  final String uid;
  final String action;
  final MediaItem item;

  String get key => '$uid:${item.isSeries ? 'series' : 'movie'}:${item.id}';

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'action': action,
        'item': item.toJson(),
      };

  factory _PendingFavoriteOperation.fromJson(Map<String, dynamic> json) {
    return _PendingFavoriteOperation(
      uid: json['uid']?.toString() ?? '',
      action: json['action']?.toString() == 'remove' ? 'remove' : 'add',
      item: MediaItem.fromJson(
        Map<String, dynamic>.from(json['item'] as Map? ?? const {}),
      ),
    );
  }
}

class LibraryStore extends ChangeNotifier {
  static const _favoritesKey = 'cinematy_favorites';
  static const _progressKey = 'cinematy_progress';
  static const _mediaKey = 'cinematy_media_snapshot';
  static const _watchLaterKey = 'cinematy_watch_later';
  static const _favoriteQueueKey = 'cinematy_favorite_cloud_queue_v1';

  final Set<String> _favorites = {};
  final Map<String, WatchProgress> _progress = {};
  final Map<String, MediaItem> _snapshots = {};
  final Set<String> _watchLater = {};
  final Map<String, _PendingFavoriteOperation> _favoriteQueue = {};

  StreamSubscription<User?>? _authSubscription;
  bool _loaded = false;
  bool _cloudSyncing = false;
  String? _loadedFavoriteUid;

  LibraryStore() {
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!_loaded) return;
      unawaited(_switchFavoriteScope(user));
    });
  }

  bool get loaded => _loaded;
  bool get cloudSyncing => _cloudSyncing;
  Set<String> get favorites => Set.unmodifiable(_favorites);
  Map<String, WatchProgress> get progress => Map.unmodifiable(_progress);

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();

    _watchLater.addAll(prefs.getStringList(_watchLaterKey) ?? const []);

    try {
      final raw = jsonDecode(prefs.getString(_progressKey) ?? '{}')
          as Map<String, dynamic>;
      for (final entry in raw.entries) {
        if (entry.value is Map) {
          _progress[entry.key] = WatchProgress.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }

      final media = jsonDecode(prefs.getString(_mediaKey) ?? '{}')
          as Map<String, dynamic>;
      for (final entry in media.entries) {
        if (entry.value is Map) {
          _snapshots[entry.key] = MediaItem.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }

      final pending = jsonDecode(prefs.getString(_favoriteQueueKey) ?? '{}');
      if (pending is Map) {
        for (final entry in pending.entries) {
          if (entry.value is! Map) continue;
          final op = _PendingFavoriteOperation.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
          if (op.uid.isNotEmpty && op.item.id.isNotEmpty) {
            _favoriteQueue[op.key] = op;
          }
        }
      }
    } catch (_) {}

    _loaded = true;
    await _loadFavoriteScope(FirebaseAuth.instance.currentUser);
    notifyListeners();

    if (FirebaseAuth.instance.currentUser != null) {
      unawaited(syncCloudFavorites());
    }
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

  List<MediaItem> favoriteItems() => _favorites
      .map((id) => _snapshots[id])
      .whereType<MediaItem>()
      .toList();

  List<MediaItem> watchLaterItems() => _watchLater
      .map((id) => _snapshots[id])
      .whereType<MediaItem>()
      .toList();

  List<MediaItem> continueWatching() {
    final entries = _progress.values
        .where((e) => e.positionMs >= 60000 && e.ratio < .97)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return entries
        .map((e) => _snapshots[e.mediaId])
        .whereType<MediaItem>()
        .toList();
  }

  Future<void> toggleFavorite(MediaItem item) async {
    if (item.id.isEmpty) return;
    _snapshots[item.id] = item;

    final wasFavorite = _favorites.contains(item.id);
    final added = !wasFavorite;
    if (added) {
      final previous = _favorites.toList(growable: false);
      _favorites
        ..clear()
        ..add(item.id)
        ..addAll(previous);
    } else {
      _favorites.remove(item.id);
    }
    notifyListeners();
    await _save();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final op = _PendingFavoriteOperation(
      uid: user.uid,
      action: added ? 'add' : 'remove',
      item: item,
    );
    _favoriteQueue[op.key] = op;
    await _saveFavoriteQueue();
    unawaited(_flushFavoriteQueue(user.uid));
  }

  Future<void> syncCloudFavorites({bool force = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _cloudSyncing) return;

    _cloudSyncing = true;
    notifyListeners();
    try {
      await CinematyAccountApi.instance.syncProfile();
      await _flushFavoriteQueue(user.uid);
      final hasPending = _favoriteQueue.values.any((op) => op.uid == user.uid);
      if (hasPending) return;
      final cloud = await CinematyAccountApi.instance.myFavorites();

      if (FirebaseAuth.instance.currentUser?.uid != user.uid) return;

      _favorites
        ..clear()
        ..addAll(cloud.map((e) => e.id));
      for (final item in cloud) {
        _snapshots[item.id] = item;
      }
      await _save();
    } catch (_) {
      // Keep the account-scoped local cache when the server is unreachable.
    } finally {
      _cloudSyncing = false;
      notifyListeners();
    }
  }

  Future<void> toggleWatchLater(MediaItem item) async {
    _snapshots[item.id] = item;
    if (!_watchLater.add(item.id)) _watchLater.remove(item.id);
    notifyListeners();
    await _save();
  }

  Future<void> saveProgress(
    MediaItem item,
    Duration position,
    Duration duration,
  ) async {
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

  Future<void> _switchFavoriteScope(User? user) async {
    await _loadFavoriteScope(user);
    notifyListeners();
    if (user != null) unawaited(syncCloudFavorites(force: true));
  }

  String _favoriteStorageKey(String? uid) {
    if (uid == null || uid.isEmpty) return _favoritesKey;
    return '${_favoritesKey}_account_$uid';
  }

  Future<void> _loadFavoriteScope(User? user) async {
    final uid = user?.uid;
    if (_loadedFavoriteUid == uid) return;
    final prefs = await SharedPreferences.getInstance();
    _favorites
      ..clear()
      ..addAll(prefs.getStringList(_favoriteStorageKey(uid)) ?? const []);
    _loadedFavoriteUid = uid;
  }

  Future<void> _flushFavoriteQueue(String uid) async {
    final operations = _favoriteQueue.values
        .where((op) => op.uid == uid)
        .toList(growable: false);
    if (operations.isEmpty) return;

    var changed = false;
    for (final op in operations) {
      if (FirebaseAuth.instance.currentUser?.uid != uid) break;
      try {
        if (op.action == 'remove') {
          await CinematyAccountApi.instance.removeFavorite(op.item);
        } else {
          await CinematyAccountApi.instance.addFavorite(op.item);
        }
        _favoriteQueue.remove(op.key);
        changed = true;
      } catch (_) {
        // Stop on first network/server failure and retry later.
        break;
      }
    }
    if (changed) await _saveFavoriteQueue();
  }

  Future<void> _saveFavoriteQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _favoriteQueueKey,
      jsonEncode(
        _favoriteQueue.map((key, value) => MapEntry(key, value.toJson())),
      ),
    );
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _favoriteStorageKey(FirebaseAuth.instance.currentUser?.uid),
      _favorites.toList(),
    );
    await prefs.setStringList(_watchLaterKey, _watchLater.toList());
    await prefs.setString(
      _progressKey,
      jsonEncode(
        _progress.map((k, v) => MapEntry(k, v.toJson())),
      ),
    );
    await prefs.setString(
      _mediaKey,
      jsonEncode(
        _snapshots.map((k, v) => MapEntry(k, v.toJson())),
      ),
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
