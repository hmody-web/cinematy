import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppFontOption {
  const AppFontOption(this.family, this.label);
  final String family;
  final String label;
}

class AppSettingsStore extends ChangeNotifier {
  static const _fontKey = 'cinematy_app_font';
  static const _videoQualityKey = 'cinematy_default_video_quality';

  static const fonts = <AppFontOption>[
    AppFontOption('Monadi', 'Monadi'),
    AppFontOption('ArabicUI', 'Arabic UI'),
    AppFontOption('Tajawal', 'Tajawal'),
    AppFontOption('NizarCocon', 'Nizar Cocon'),
  ];

  String fontFamily = 'Monadi';
  int preferredVideoQuality = 1080;
  bool loaded = false;

  Future<void> load() async {
    if (loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_fontKey);
    if (saved != null && fonts.any((e) => e.family == saved)) {
      fontFamily = saved;
    }
    preferredVideoQuality = prefs.getInt(_videoQualityKey) ?? 1080;
    loaded = true;
    notifyListeners();
  }

  Future<void> setPreferredVideoQuality(int value) async {
    if (![2160, 1440, 1080, 720, 480, 360].contains(value) || preferredVideoQuality == value) return;
    preferredVideoQuality = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_videoQualityKey, value);
  }

  Future<void> setFontFamily(String value) async {
    if (!fonts.any((e) => e.family == value) || fontFamily == value) return;
    fontFamily = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fontKey, value);
  }
}
