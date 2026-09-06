import '../../core/config/app_config.dart';
import '../../core/utils/json_utils.dart';
import 'media_item.dart';

class VideoSource {
  const VideoSource({required this.url, this.quality = 'تلقائي', this.container = '', this.resolution = ''});
  final String url;
  final String quality;
  final String container;
  final String resolution;

  factory VideoSource.fromJson(Map<String, dynamic> json) {
    final resolution = JsonUtils.string(json, ['resolution', 'quality']);
    final direct = JsonUtils.string(json, ['videoUrl', 'url', 'file', 'path']);
    final filename = JsonUtils.string(json, ['transcoddedFileName']);
    String url;
    if (direct.isNotEmpty) {
      url = normalizeMediaUrl(direct);
    } else if (filename.isNotEmpty) {
      if (filename.startsWith('http://') || filename.startsWith('https://')) {
        url = filename;
      } else if (filename.startsWith('/')) {
        url = '${AppConfig.baseUrl}$filename';
      } else {
        // النسخة الأصلية من Cinemana تحتوي هذا Video base path صراحةً.
        url = '${AppConfig.baseUrl}/video/en/$filename';
      }
    } else {
      url = '';
    }

    return VideoSource(
      url: url,
      quality: _qualityLabel(resolution.isEmpty ? JsonUtils.string(json, ['display_name'], fallback: 'تلقائي') : resolution),
      container: JsonUtils.string(json, ['container', 'extention', 'extension']),
      resolution: resolution,
    );
  }

  static String _qualityLabel(String value) {
    final v = value.toLowerCase().replaceAll('p', '');
    for (final q in ['2160', '1440', '1080', '720', '480', '360', '320', '240']) {
      if (v.contains(q)) return '${q}p';
    }
    return value.isEmpty ? 'تلقائي' : value;
  }
}

class SubtitleSource {
  const SubtitleSource({required this.url, this.language = 'العربية', this.label = ''});
  final String url;
  final String language;
  final String label;

  factory SubtitleSource.fromJson(Map<String, dynamic> json) {
    final lang = JsonUtils.string(json, ['lang', 'language', 'display_name']);
    return SubtitleSource(
      url: normalizeMediaUrl(JsonUtils.string(json, ['file', 'url', 'path', 'arTranslationFilePath', 'enTranslationFilePath'])),
      language: lang.isEmpty ? 'العربية' : lang,
      label: JsonUtils.string(json, ['display_name', 'title'], fallback: lang),
    );
  }
}
