import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SubtitleFontOption {
  const SubtitleFontOption(this.family, this.label);
  final String family;
  final String label;
}

class SubtitleSettingsStore extends ChangeNotifier {
  static const _prefix = 'cinematy_subtitle_';

  static const fonts = <SubtitleFontOption>[
    SubtitleFontOption('Monadi', 'Monadi'),
    SubtitleFontOption('ArabicUI', 'Arabic UI'),
    SubtitleFontOption('Tajawal', 'Tajawal'),
    SubtitleFontOption('NizarCocon', 'Nizar Cocon'),
  ];

  double fontSize = 50;
  String fontFamily = 'ArabicUI';
  Color textColor = Colors.white;
  Color outlineColor = Colors.black;
  double outlineWidth = 2.0;
  double outlineOpacity = .90;
  bool backgroundEnabled = false;
  Color backgroundColor = Colors.black;
  double backgroundOpacity = .55;
  bool loaded = false;

  Future<void> load() async {
    if (loaded) return;
    final p = await SharedPreferences.getInstance();
    fontSize = (p.getDouble('${_prefix}fontSize') ?? 50).clamp(30.0, 200.0).toDouble();
    final savedFont = p.getString('${_prefix}fontFamily');
    if (savedFont != null && fonts.any((e) => e.family == savedFont)) fontFamily = savedFont;
    textColor = Color(p.getInt('${_prefix}textColor') ?? Colors.white.value);
    outlineColor = Color(p.getInt('${_prefix}outlineColor') ?? Colors.black.value);
    outlineWidth = p.getDouble('${_prefix}outlineWidth') ?? 2.0;
    outlineOpacity = p.getDouble('${_prefix}outlineOpacity') ?? .90;
    backgroundEnabled = p.getBool('${_prefix}backgroundEnabled') ?? false;
    backgroundColor = Color(p.getInt('${_prefix}backgroundColor') ?? Colors.black.value);
    backgroundOpacity = p.getDouble('${_prefix}backgroundOpacity') ?? .55;
    loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble('${_prefix}fontSize', fontSize);
    await p.setString('${_prefix}fontFamily', fontFamily);
    await p.setInt('${_prefix}textColor', textColor.value);
    await p.setInt('${_prefix}outlineColor', outlineColor.value);
    await p.setDouble('${_prefix}outlineWidth', outlineWidth);
    await p.setDouble('${_prefix}outlineOpacity', outlineOpacity);
    await p.setBool('${_prefix}backgroundEnabled', backgroundEnabled);
    await p.setInt('${_prefix}backgroundColor', backgroundColor.value);
    await p.setDouble('${_prefix}backgroundOpacity', backgroundOpacity);
  }

  void setFontSize(double v) { fontSize = v; notifyListeners(); _save(); }
  void setFontFamily(String v) { if (fonts.any((e) => e.family == v)) { fontFamily = v; notifyListeners(); _save(); } }
  void setTextColor(Color v) { textColor = v; notifyListeners(); _save(); }
  void setOutlineColor(Color v) { outlineColor = v; notifyListeners(); _save(); }
  void setOutlineWidth(double v) { outlineWidth = v; notifyListeners(); _save(); }
  void setOutlineOpacity(double v) { outlineOpacity = v; notifyListeners(); _save(); }
  void setBackgroundEnabled(bool v) { backgroundEnabled = v; notifyListeners(); _save(); }
  void setBackgroundColor(Color v) { backgroundColor = v; notifyListeners(); _save(); }
  void setBackgroundOpacity(double v) { backgroundOpacity = v; notifyListeners(); _save(); }

  Future<void> reset() async {
    fontSize = 50;
    fontFamily = 'ArabicUI';
    textColor = Colors.white;
    outlineColor = Colors.black;
    outlineWidth = 2;
    outlineOpacity = .9;
    backgroundEnabled = false;
    backgroundColor = Colors.black;
    backgroundOpacity = .55;
    notifyListeners();
    await _save();
  }
}
