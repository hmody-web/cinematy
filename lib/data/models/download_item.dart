import 'media_item.dart';

class DownloadItem {
  const DownloadItem({
    required this.id,
    required this.media,
    required this.localPath,
    required this.quality,
    required this.createdAt,
    this.progress = 1,
    this.completed = true,
  });

  final String id;
  final MediaItem media;
  final String localPath;
  final String quality;
  final DateTime createdAt;
  final double progress;
  final bool completed;

  Map<String, dynamic> toJson() => {
    'id': id,
    'media': media.raw,
    'localPath': localPath,
    'quality': quality,
    'createdAt': createdAt.toIso8601String(),
    'progress': progress,
    'completed': completed,
  };

  factory DownloadItem.fromJson(Map<String, dynamic> json) => DownloadItem(
    id: json['id']?.toString() ?? '',
    media: MediaItem.fromJson(Map<String, dynamic>.from((json['media'] as Map?) ?? const {})),
    localPath: json['localPath']?.toString() ?? '',
    quality: json['quality']?.toString() ?? 'تلقائي',
    createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
    progress: double.tryParse(json['progress']?.toString() ?? '') ?? 1,
    completed: json['completed'] == true,
  );
}
