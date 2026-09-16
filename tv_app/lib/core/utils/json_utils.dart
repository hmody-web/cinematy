class JsonUtils {
  JsonUtils._();

  static String string(Map<String, dynamic> json, List<String> keys, {String fallback = ''}) {
    for (final key in keys) {
      final value = json[key];
      if (value != null && value.toString().trim().isNotEmpty && value.toString() != 'null') {
        return value.toString().trim();
      }
    }
    return fallback;
  }

  static int integer(Map<String, dynamic> json, List<String> keys, {int fallback = 0}) {
    for (final key in keys) {
      final value = json[key];
      if (value is int) return value;
      final parsed = int.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  static double decimal(Map<String, dynamic> json, List<String> keys, {double fallback = 0}) {
    for (final key in keys) {
      final value = json[key];
      if (value is num) return value.toDouble();
      final parsed = double.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  static bool boolean(Map<String, dynamic> json, List<String> keys, {bool fallback = false}) {
    for (final key in keys) {
      final value = json[key];
      if (value is bool) return value;
      final normalized = value?.toString().toLowerCase();
      if (normalized == '1' || normalized == 'true' || normalized == 'yes') return true;
      if (normalized == '0' || normalized == 'false' || normalized == 'no') return false;
    }
    return fallback;
  }

  static List<dynamic> list(dynamic raw, {List<String> candidateKeys = const []}) {
    if (raw is List) return raw;
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      for (final key in [...candidateKeys, 'data', 'result', 'results', 'items', 'videos', 'list']) {
        final value = map[key];
        if (value is List) return value;
      }
      for (final value in map.values) {
        if (value is List) return value;
      }
    }
    return const [];
  }

  static Map<String, dynamic> map(dynamic raw, {List<String> candidateKeys = const []}) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is List && raw.isNotEmpty && raw.first is Map) return Map<String, dynamic>.from(raw.first as Map);
    return const {};
  }
}
