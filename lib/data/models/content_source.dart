import 'dart:convert';

enum ContentSourceKind { cinemana, website, jsonApi, auto }

class ContentSourceDefinition {
  const ContentSourceDefinition({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.kind,
    this.iconUrl = '',
    this.builtIn = false,
    this.searchTemplate = '',
  });

  final String id;
  final String name;
  final String baseUrl;
  final ContentSourceKind kind;
  final String iconUrl;
  final bool builtIn;
  final String searchTemplate;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'kind': kind.name,
        'iconUrl': iconUrl,
        'builtIn': builtIn,
        'searchTemplate': searchTemplate,
      };

  factory ContentSourceDefinition.fromJson(Map<String, dynamic> json) {
    final kindName = (json['kind'] ?? 'auto').toString();
    return ContentSourceDefinition(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'مصدر').toString(),
      baseUrl: (json['baseUrl'] ?? '').toString(),
      kind: ContentSourceKind.values.firstWhere(
        (e) => e.name == kindName,
        orElse: () => ContentSourceKind.auto,
      ),
      iconUrl: (json['iconUrl'] ?? '').toString(),
      builtIn: json['builtIn'] == true,
      searchTemplate: (json['searchTemplate'] ?? '').toString(),
    );
  }

  static String encodeList(List<ContentSourceDefinition> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());

  static List<ContentSourceDefinition> decodeList(String raw) {
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! List) return const [];
      return parsed
          .whereType<Map>()
          .map((e) => ContentSourceDefinition.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.id.isNotEmpty && e.baseUrl.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

const builtInContentSources = <ContentSourceDefinition>[
  ContentSourceDefinition(
    id: 'cinemana',
    name: 'سينمانا',
    baseUrl: 'https://cinemana.shabakaty.com',
    kind: ContentSourceKind.cinemana,
    builtIn: true,
  ),
  ContentSourceDefinition(
    id: 'akwam',
    name: 'أكوام',
    baseUrl: 'https://akwam.ss',
    kind: ContentSourceKind.website,
    builtIn: true,
  ),
];
