
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/tv/tv_models.dart';

class TvChannelFavorites extends ChangeNotifier {
  static const _key = 'cinematy_tv_channel_favorites_v1';
  final Map<int, TvChannel> _items = <int, TvChannel>{};

  List<TvChannel> get items => _items.values.toList(growable: false);
  bool contains(TvChannel channel) => _items.containsKey(channel.id);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = jsonDecode(prefs.getString(_key) ?? '[]');
      if (raw is List) {
        for (final value in raw.whereType<Map>()) {
          final map = Map<String, dynamic>.from(value);
          final channel = TvChannel(
            id: int.tryParse('${map['id'] ?? 0}') ?? 0,
            name: '${map['name'] ?? ''}',
            categoryId: '${map['categoryId'] ?? ''}',
            icon: '${map['icon'] ?? ''}',
            epgChannelId: '${map['epgChannelId'] ?? ''}'.trim().isEmpty
                ? null
                : '${map['epgChannelId']}',
            nowTitle: '${map['nowTitle'] ?? ''}'.trim().isEmpty
                ? null
                : '${map['nowTitle']}',
          );
          if (channel.id > 0) _items[channel.id] = channel;
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> toggle(TvChannel channel) async {
    if (_items.containsKey(channel.id)) {
      _items.remove(channel.id);
    } else {
      _items[channel.id] = channel;
    }
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(
        _items.values.map((channel) => <String, dynamic>{
          'id': channel.id,
          'name': channel.name,
          'categoryId': channel.categoryId,
          'icon': channel.icon,
          'epgChannelId': channel.epgChannelId,
          'nowTitle': channel.nowTitle,
        }).toList(growable: false),
      ),
    );
  }
}
