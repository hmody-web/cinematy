class TvCategory {
  const TvCategory({required this.id, required this.name});

  final String id;
  final String name;

  factory TvCategory.fromJson(Map<String, dynamic> json) => TvCategory(
        id: '${json['category_id'] ?? ''}',
        name: '${json['category_name'] ?? 'بدون تصنيف'}'.trim(),
      );
}

class TvChannel {
  const TvChannel({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.icon,
    this.epgChannelId,
    this.nowTitle,
  });

  final int id;
  final String name;
  final String categoryId;
  final String icon;
  final String? epgChannelId;
  final String? nowTitle;

  factory TvChannel.fromJson(Map<String, dynamic> json) {
    final rawId = json['stream_id'];
    return TvChannel(
      id: rawId is int ? rawId : int.tryParse('$rawId') ?? 0,
      name: '${json['name'] ?? 'قناة'}'.trim(),
      categoryId: '${json['category_id'] ?? ''}',
      icon: '${json['stream_icon'] ?? ''}'.trim(),
      epgChannelId: '${json['epg_channel_id'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['epg_channel_id']}'.trim(),
      nowTitle: '${json['title'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['title']}'.trim(),
    );
  }

  /// A stable identity used to group duplicate/quality/language variants of
  /// the same TV channel (e.g. beIN Sports 3 HD / FHD / HEVC / Arabic).
  String get groupKey => normalizeTvChannelName(name);
}

String normalizeTvChannelName(String input) {
  var value = input.toLowerCase().trim();
  const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
  for (var i = 0; i < 10; i++) {
    value = value.replaceAll(arabicDigits[i], '$i');
    value = value.replaceAll(persianDigits[i], '$i');
  }

  // Make the common Arabic and English spellings collapse to one identity.
  value = value
      .replaceAll('بي ان', 'bein')
      .replaceAll('بين', 'bein')
      .replaceAll('بى ان', 'bein')
      .replaceAll('سبورتس', 'sports')
      .replaceAll('سبورت', 'sports')
      .replaceAll('رياضة', 'sports')
      .replaceAll('&', ' and ');

  // Decorations and provider prefixes/suffixes are not part of the channel ID.
  value = value.replaceAll(RegExp(r'[\[\]{}()|•★☆◆◇▶►]+'), ' ');
  value = value.replaceAll(RegExp(r'[_\-–—:/\\]+'), ' ');

  final removable = <String>{
    'hd', 'fhd', 'uhd', 'sd', '4k', '8k', 'hevc', 'h265', 'h264',
    '50fps', '60fps', 'fps', 'raw', 'vip', 'backup', 'server', 'live',
    'ar', 'arabic', 'ara', 'عربي', 'العربية', 'en', 'eng', 'english',
    'uk', 'us', 'usa', 'qa', 'qatar', 'قطر', 'iraq', 'العراق',
  };

  final tokens = value
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty && !removable.contains(token))
      .toList(growable: false);

  return tokens.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}
