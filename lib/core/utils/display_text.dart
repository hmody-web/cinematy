String cinematyDisplayTitle(String value) {
  var title = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (title.isEmpty) return title;

  // Cinemana sometimes returns mixed Arabic/Latin quality labels with the
  // quality token first (for example "4K عالم مارفل"). In an RTL UI that can
  // visually flip again. Keep the Arabic title first and isolate the Latin
  // quality token so it always renders as "عالم مارفل 4K".
  final leadingQuality = RegExp(r'^(4K|8K|UHD|FHD)\s+(.+)$', caseSensitive: false)
      .firstMatch(title);
  if (leadingQuality != null && _containsArabic(leadingQuality.group(2)!)) {
    title = '${leadingQuality.group(2)!.trim()} ${leadingQuality.group(1)!.toUpperCase()}';
  }

  title = title.replaceAllMapped(
    RegExp(r'\b(4K|8K|UHD|FHD)\b', caseSensitive: false),
    (m) => '\u2066${m.group(1)!.toUpperCase()}\u2069',
  );
  return title;
}

bool _containsArabic(String value) =>
    RegExp(r'[\u0600-\u06FF]').hasMatch(value);

String cinematyComparableTitle(String value) {
  var text = cinematyDisplayTitle(value)
      .replaceAll('\u2066', '')
      .replaceAll('\u2069', '')
      .toLowerCase();
  const replacements = <String, String>{
    'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ى': 'ي', 'ة': 'ه', 'ؤ': 'و', 'ئ': 'ي',
  };
  replacements.forEach((from, to) => text = text.replaceAll(from, to));
  return text.replaceAll(RegExp(r'[^\u0600-\u06FFA-Za-z0-9]+'), ' ').trim();
}
