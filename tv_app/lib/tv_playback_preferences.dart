
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TvPlaybackPreferences extends ChangeNotifier {
  static const _qualityKey = 'cinematy_tv_preferred_quality_v2';

  int _preferredQuality = 1080;
  int get preferredQuality => _preferredQuality;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _preferredQuality = prefs.getInt(_qualityKey) ?? 1080;
    notifyListeners();
  }

  Future<void> setPreferredQuality(int value) async {
    if (value <= 0) return;
    _preferredQuality = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_qualityKey, value);
  }
}
