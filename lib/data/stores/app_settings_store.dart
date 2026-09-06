import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppFontOption {
  const AppFontOption(this.family, this.label);
  final String family;
  final String label;
}

class AppSettingsStore extends ChangeNotifier {
  static const _fontKey = 'cinematy_app_font';

  static const fonts = <AppFontOption>[
    AppFontOption('Monadi', 'Monadi'),
    AppFontOption('ArabicUI', 'Arabic UI'),
    AppFontOption('Tajawal', 'Tajawal'),
    AppFontOption('NizarCocon', 'Nizar Cocon'),
  ];

  String fontFamily = 'Monadi';
  bool loaded = false;

  Future<void> load() async {
    if (loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_fontKey);
    if (saved != null && fonts.any((e) => e.family == saved)) {
      fontFamily = saved;
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> setFontFamily(String value) async {
    if (!fonts.any((e) => e.family == value) || fontFamily == value) return;
    fontFamily = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fontKey, value);
  }
}
