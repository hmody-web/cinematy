import 'tv_models.dart';

/// Resolves the actual beIN stream already returned by the app's Xtream source.
///
/// This deliberately does not hard-code stream URLs or stream ids. The app first
/// loads the provider's current `get_live_streams` response, then this resolver
/// matches the broadcaster (for example beIN Sports 6) against those real rows.
class BeinChannelResolver {
  const BeinChannelResolver._();

  static TvChannel? resolve({
    required List<TvChannel> channels,
    required List<TvCategory> categories,
    required String broadcast,
    String preferredVariant = 'N',
  }) {
    if (channels.isEmpty || !isBeinLabel(broadcast)) return null;

    final targetNumber = channelNumber(broadcast, requireBein: true);
    final categoryById = <String, String>{
      for (final category in categories) category.id: category.name,
    };

    TvChannel? best;
    var bestScore = -1 << 20;

    for (final channel in channels) {
      final categoryName = categoryById[channel.categoryId] ?? '';
      final nameIsBein = isBeinLabel(channel.name) ||
          isBeinLabel(channel.epgChannelId ?? '') ||
          isBeinLabel(channel.nowTitle ?? '');
      final categoryIsBein = isBeinLabel(categoryName);
      if (!nameIsBein && !categoryIsBein) continue;

      final number = _firstUsefulNumber(
        <String>[
          channel.name,
          channel.epgChannelId ?? '',
          channel.nowTitle ?? '',
        ],
        allowWithoutBein: categoryIsBein,
      );

      // When the scoreboard explicitly says beIN 6, never open beIN 1/2/etc.
      if (targetNumber != null && number != null && number != targetNumber) {
        continue;
      }

      var score = 0;
      if (nameIsBein) score += 500;
      if (categoryIsBein) score += 260;
      if (targetNumber != null && number == targetNumber) score += 1400;
      if (targetNumber == null && number != null) score += 40;

      // Providers may expose more than one feed for the same beIN number,
      // e.g. beIN 6 (N), beIN 6 (G), beIN 6 (F). Normal devices prefer
      // N and, within N, the 4K row. Low-end optimization prefers F + HD.
      final requestedVariant = preferredVariant.trim().toUpperCase();
      final variant = _streamVariant(<String>[
        channel.name,
        channel.epgChannelId ?? '',
        categoryName,
      ]);
      if (variant == requestedVariant) {
        score += 5000;
      } else if (variant != null) {
        // Strongly keep a different tagged feed behind the requested one,
        // while still allowing it as a fallback if the requested feed is absent.
        score -= 700;
      } else {
        // Untagged channels are valid fallbacks but never outrank N/F explicitly.
        score += 25;
      }

      final searchable = _normalized('${channel.name} ${channel.epgChannelId ?? ''} ${channel.nowTitle ?? ''} $categoryName');

      // Quality preference is tied to the selected beIN feed family:
      //   N (normal/strong devices): prefer the real 4K feed first.
      //   F (low-end optimization): prefer an HD feed first and avoid 4K/FHD load.
      // We still keep other rows as safe fallbacks if the preferred quality is absent.
      final wantsLowEnd = requestedVariant == 'F';
      final is4k = RegExp(r'(^|\s)(4k|uhd|2160p?|2160)(\s|$)').hasMatch(searchable);
      final isFhd = RegExp(r'(^|\s)(fhd|1080p?|1080)(\s|$)').hasMatch(searchable);
      final isHd = !isFhd && RegExp(r'(^|\s)(hd|720p?|720)(\s|$)').hasMatch(searchable);

      if (wantsLowEnd) {
        if (isHd) score += 3600;
        if (isFhd) score += 900;
        if (is4k) score -= 4200;
      } else {
        if (is4k) score += 4200;
        if (isFhd) score += 1200;
        if (isHd) score += 450;
      }

      if (searchable.contains('premium')) score += 12;
      if (searchable.contains('backup') || searchable.contains('بكاب')) score -= 20;

      if (score > bestScore) {
        bestScore = score;
        best = channel;
      }
    }

    // For a numbered beIN broadcast, a candidate without a discoverable number
    // is too risky: returning null is better than opening the wrong beIN feed.
    if (best != null && targetNumber != null) {
      final categoryName = categoryById[best.categoryId] ?? '';
      final bestNumber = _firstUsefulNumber(
        <String>[best.name, best.epgChannelId ?? '', best.nowTitle ?? ''],
        allowWithoutBein: isBeinLabel(categoryName),
      );
      if (bestNumber != targetNumber) return null;
    }
    return best;
  }


  static String? _streamVariant(List<String> values) {
    for (final raw in values) {
      if (raw.trim().isEmpty) continue;
      // Match only a standalone feed marker so the F in FHD is never treated
      // as variant F. Handles forms such as (N), [F], - G, |N| and " 6 N ".
      final value = raw.toUpperCase();
      final bracketed = RegExp(r'[\(\[\{]\s*([NFG])\s*[\)\]\}]').firstMatch(value);
      if (bracketed != null) return bracketed.group(1);
      final separated = RegExp(r'(?:^|[\s|:/_\-])([NFG])(?:$|[\s|:/_\-])').firstMatch(value);
      if (separated != null) return separated.group(1);
    }
    return null;
  }

  static bool isBeinLabel(String value) {
    final normalized = _normalized(value);
    final compact = normalized.replaceAll(' ', '');
    return compact.contains('beinsports') ||
        compact.contains('bein') ||
        compact.contains('beinsport') ||
        normalized.contains('بي ان') ||
        normalized.contains('بين سبورت') ||
        normalized.contains('بي ان سبورت');
  }

  static int? channelNumber(String value, {bool requireBein = false}) {
    if (requireBein && !isBeinLabel(value)) return null;
    return _extractNumber(value, allowWithoutBein: !requireBein);
  }

  static int? _firstUsefulNumber(
    List<String> values, {
    required bool allowWithoutBein,
  }) {
    for (final value in values) {
      if (value.trim().isEmpty) continue;
      final number = _extractNumber(
        value,
        allowWithoutBein: allowWithoutBein || isBeinLabel(value),
      );
      if (number != null) return number;
    }
    return null;
  }

  static int? _extractNumber(String input, {required bool allowWithoutBein}) {
    var value = _normalized(input);
    if (!allowWithoutBein && !isBeinLabel(value)) return null;

    // Remove numbers which describe video quality/framerate/codec rather than
    // the actual channel number.
    value = value
        .replaceAll(RegExp(r'\b(?:2160|1440|1080|720|576|480)p?\b'), ' ')
        .replaceAll(RegExp(r'\b(?:4k|8k|50fps|60fps|25fps|30fps)\b'), ' ')
        .replaceAll(RegExp(r'\b(?:h264|h265|x264|x265|hevc|avc)\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final patterns = <RegExp>[
      RegExp(r'(?:bein\s*(?:sports?|sport)?|بي\s*ان\s*(?:سبورتس?|سبورت)?|بين\s*(?:سبورتس?|سبورت)?)\s*(?:premium\s*)?(\d{1,2})\b'),
      RegExp(r'\bpremium\s*(\d{1,2})\b'),
      RegExp(r'\b(?:ch|channel|قناه|قناة)\s*(\d{1,2})\b'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(value);
      final number = int.tryParse(match?.group(1) ?? '');
      if (number != null && number >= 1 && number <= 20) return number;
    }

    if (allowWithoutBein || isBeinLabel(value)) {
      for (final match in RegExp(r'\b(\d{1,2})\b').allMatches(value)) {
        final number = int.tryParse(match.group(1) ?? '');
        if (number != null && number >= 1 && number <= 20) return number;
      }
    }
    return null;
  }

  static String _normalized(String input) {
    var value = input.toLowerCase().trim();
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
    for (var i = 0; i < 10; i++) {
      value = value.replaceAll(arabicDigits[i], '$i');
      value = value.replaceAll(persianDigits[i], '$i');
    }
    value = value
        .replaceAll('إ', 'ا')
        .replaceAll('أ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll('بى ان', 'bein')
        .replaceAll('بي ان', 'bein')
        .replaceAll('بين', 'bein')
        .replaceAll('سبورتس', 'sports')
        .replaceAll('سبورت', 'sports')
        .replaceAll(RegExp(r'[_\-–—:/\\|\[\]{}()]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return value;
  }
}
