import 'media_item.dart';

class DownloadedSubtitle {
  const DownloadedSubtitle({
    required this.localPath,
    required this.language,
    required this.label,
  });

  final String localPath;
  final String language;
  final String label;

  Map<String, dynamic> toJson() => {
        'localPath': localPath,
        'language': language,
        'label': label,
      };

  factory DownloadedSubtitle.fromJson(Map<String, dynamic> json) =>
      DownloadedSubtitle(
        localPath: json['localPath']?.toString() ?? '',
        language: json['language']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
      );
}

class DownloadItem {
  const DownloadItem({
    required this.id,
    required this.media,
    required this.localPath,
    required this.quality,
    required this.createdAt,
    this.subtitles = const <DownloadedSubtitle>[],
    this.progress = 1,
    this.completed = true,
  });

  final String id;
  final MediaItem media;
  final String localPath;
  final String quality;
  final DateTime createdAt;
  final List<DownloadedSubtitle> subtitles;
  final double progress;
  final bool completed;

  Map<String, dynamic> toJson() => {
        'id': id,
        'media': media.toJson(),
        'localPath': localPath,
        'quality': quality,
        'createdAt': createdAt.toIso8601String(),
        'subtitles': subtitles.map((e) => e.toJson()).toList(),
        'progress': progress,
        'completed': completed,
      };

  factory DownloadItem.fromJson(Map<String, dynamic> json) => DownloadItem(
        id: json['id']?.toString() ?? '',
        media: MediaItem.fromJson(
          Map<String, dynamic>.from((json['media'] as Map?) ?? const {}),
        ),
        localPath: json['localPath']?.toString() ?? '',
        quality: json['quality']?.toString() ?? 'تلقائي',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        subtitles: ((json['subtitles'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map((e) => DownloadedSubtitle.fromJson(
                  Map<String, dynamic>.from(e),
                ))
            .where((e) => e.localPath.isNotEmpty)
            .toList(),
        progress: double.tryParse(json['progress']?.toString() ?? '') ?? 1,
        completed: json['completed'] == true,
      );
}
