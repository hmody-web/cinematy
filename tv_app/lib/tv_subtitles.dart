
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/models/video_source.dart';
import 'tv_local_text.dart';

class TvSubtitleCue {
  const TvSubtitleCue({required this.start, required this.end, required this.text});
  final Duration start;
  final Duration end;
  final String text;
}

class TvSubtitleStyle {
  const TvSubtitleStyle({
    this.textColor = Colors.white,
    this.edgeColor = Colors.black,
    this.edgeThickness = 0.6,
    this.edgeOpacity = 0.30,
    this.backgroundOpacity = 0.0,
    this.fontSize = 30,
    this.bold = false,
    this.fontFamily = 'system',
    this.positionX = 0.0,
    this.positionY = 0.94,
  });

  final Color textColor;
  final Color edgeColor;
  final double edgeThickness;
  final double edgeOpacity;
  final double backgroundOpacity;
  final double fontSize;
  final bool bold;
  final String fontFamily;
  final double positionX;
  final double positionY;

  TvSubtitleStyle copyWith({
    Color? textColor,
    Color? edgeColor,
    double? edgeThickness,
    double? edgeOpacity,
    double? backgroundOpacity,
    double? fontSize,
    bool? bold,
    String? fontFamily,
    double? positionX,
    double? positionY,
  }) =>
      TvSubtitleStyle(
        textColor: textColor ?? this.textColor,
        edgeColor: edgeColor ?? this.edgeColor,
        edgeThickness: edgeThickness ?? this.edgeThickness,
        edgeOpacity: edgeOpacity ?? this.edgeOpacity,
        backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
        fontSize: fontSize ?? this.fontSize,
        bold: bold ?? this.bold,
        fontFamily: fontFamily ?? this.fontFamily,
        positionX: positionX ?? this.positionX,
        positionY: positionY ?? this.positionY,
      );
}

class TvSubtitleStore {
  static const _p = 'cinematy_tv_subtitle_';

  Future<TvSubtitleStyle> load() async {
    final prefs = await SharedPreferences.getInstance();
    return TvSubtitleStyle(
      textColor: Color(prefs.getInt('${_p}textColor') ?? Colors.white.value),
      edgeColor: Color(prefs.getInt('${_p}edgeColor') ?? Colors.black.value),
      edgeThickness: prefs.getDouble('${_p}edgeThickness') ?? 0.6,
      edgeOpacity: prefs.getDouble('${_p}edgeOpacity') ?? 0.30,
      backgroundOpacity: prefs.getDouble('${_p}backgroundOpacity') ?? 0.0,
      fontSize: prefs.getDouble('${_p}fontSize') ?? 30,
      bold: prefs.getBool('${_p}bold') ?? false,
      fontFamily: prefs.getString('${_p}fontFamily') ?? 'system',
      positionX: prefs.getDouble('${_p}positionX') ?? 0.0,
      positionY: prefs.getDouble('${_p}positionY') ?? 0.94,
    );
  }

  Future<void> save(TvSubtitleStyle v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('${_p}textColor', v.textColor.value);
    await prefs.setInt('${_p}edgeColor', v.edgeColor.value);
    await prefs.setDouble('${_p}edgeThickness', v.edgeThickness);
    await prefs.setDouble('${_p}edgeOpacity', v.edgeOpacity);
    await prefs.setDouble('${_p}backgroundOpacity', v.backgroundOpacity);
    await prefs.setDouble('${_p}fontSize', v.fontSize);
    await prefs.setBool('${_p}bold', v.bold);
    await prefs.setString('${_p}fontFamily', v.fontFamily);
    await prefs.setDouble('${_p}positionX', v.positionX);
    await prefs.setDouble('${_p}positionY', v.positionY);
  }
}

class TvSubtitleLoader {
  final Dio _dio = Dio();

  Future<List<TvSubtitleCue>> load(SubtitleSource source) async {
    final value = source.url.trim();
    if (value.startsWith('file://') ||
        value.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value)) {
      final local = await readTvLocalText(value);
      if (local != null) {
        return parse(local.replaceFirst('\ufeff', ''));
      }
    }

    final r = await _dio.get<String>(
      source.url,
      options: Options(responseType: ResponseType.plain),
    );
    return parse((r.data ?? '').replaceFirst('\ufeff', ''));
  }

  List<TvSubtitleCue> parse(String input) {
    final normalized = input
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'^WEBVTT[^\n]*\n+', multiLine: true), '');
    final cues = <TvSubtitleCue>[];

    for (final block in normalized.split(RegExp(r'\n{2,}'))) {
      final lines = block
          .split('\n')
          .map((e) => e.trimRight())
          .where((e) => e.trim().isNotEmpty)
          .toList();
      final i = lines.indexWhere((e) => e.contains('-->'));
      if (i < 0) continue;

      final parts = lines[i].split('-->');
      if (parts.length != 2) continue;

      final start = _time(parts[0].trim());
      final end = _time(parts[1].trim().split(RegExp(r'\s+')).first);
      if (start == null || end == null || end <= start) continue;

      final text = lines
          .skip(i + 1)
          .join('\n')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&amp;', '&')
          .trim();

      if (text.isNotEmpty) cues.add(TvSubtitleCue(start: start, end: end, text: text));
    }

    cues.sort((a, b) => a.start.compareTo(b.start));
    return cues;
  }

  Duration? _time(String raw) {
    final p = raw.replaceAll(',', '.').split(':');
    if (p.length < 2 || p.length > 3) return null;
    int h = 0;
    int m;
    double s;
    if (p.length == 3) {
      h = int.tryParse(p[0]) ?? 0;
      m = int.tryParse(p[1]) ?? 0;
      s = double.tryParse(p[2]) ?? 0;
    } else {
      m = int.tryParse(p[0]) ?? 0;
      s = double.tryParse(p[1]) ?? 0;
    }
    return Duration(milliseconds: (((h * 3600 + m * 60) * 1000) + s * 1000).round());
  }
}

List<Shadow> tvSubtitleShadows(TvSubtitleStyle s) {
  if (s.edgeThickness <= 0 || s.edgeOpacity <= 0) return const [];
  final c = s.edgeColor.withOpacity(s.edgeOpacity.clamp(0.0, 1.0).toDouble());
  final d = s.edgeThickness;
  return [
    Shadow(color: c, offset: Offset(-d, 0)),
    Shadow(color: c, offset: Offset(d, 0)),
    Shadow(color: c, offset: Offset(0, -d)),
    Shadow(color: c, offset: Offset(0, d)),
    Shadow(color: c, offset: Offset(-d, -d)),
    Shadow(color: c, offset: Offset(d, -d)),
    Shadow(color: c, offset: Offset(-d, d)),
    Shadow(color: c, offset: Offset(d, d)),
  ];
}
