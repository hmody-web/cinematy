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
    this.description = '',
    this.key = '',
    this.enabled = true,
    this.sortOrder = 0,
    this.config = const <String, dynamic>{},
  });

  final String id;
  final String name;
  final String baseUrl;
  final ContentSourceKind kind;
  final String iconUrl;
  final bool builtIn;
  final String searchTemplate;
  final String description;
  final String key;
  final bool enabled;
  final int sortOrder;
  final Map<String, dynamic> config;

  ContentSourceDefinition copyWith({
    String? id,
    String? name,
    String? baseUrl,
    ContentSourceKind? kind,
    String? iconUrl,
    bool? builtIn,
    String? searchTemplate,
    String? description,
    String? key,
    bool? enabled,
    int? sortOrder,
    Map<String, dynamic>? config,
  }) {
    return ContentSourceDefinition(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      kind: kind ?? this.kind,
      iconUrl: iconUrl ?? this.iconUrl,
      builtIn: builtIn ?? this.builtIn,
      searchTemplate: searchTemplate ?? this.searchTemplate,
      description: description ?? this.description,
      key: key ?? this.key,
      enabled: enabled ?? this.enabled,
      sortOrder: sortOrder ?? this.sortOrder,
      config: config ?? this.config,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'kind': kind.name,
        'iconUrl': iconUrl,
        'builtIn': builtIn,
        'searchTemplate': searchTemplate,
        'description': description,
        'key': key,
        'enabled': enabled,
        'sortOrder': sortOrder,
        'config': config,
      };

  static ContentSourceKind _kindFrom(dynamic raw) {
    final value = (raw ?? '').toString().trim().toLowerCase();
    switch (value) {
      case 'cinemana':
      case 'builtin':
      case 'built-in':
        return ContentSourceKind.cinemana;
      case 'website':
      case 'html':
      case 'scraper':
        return ContentSourceKind.website;
      case 'jsonapi':
      case 'json_api':
      case 'json':
      case 'api':
        return ContentSourceKind.jsonApi;
      default:
        return ContentSourceKind.values.firstWhere(
          (e) => e.name.toLowerCase() == value,
          orElse: () => ContentSourceKind.auto,
        );
    }
  }

  factory ContentSourceDefinition.fromJson(Map<String, dynamic> json) {
    final rawConfig = json['config'];
    return ContentSourceDefinition(
      id: (json['id'] ?? json['key'] ?? '').toString().trim(),
      name: (json['name'] ?? 'مصدر').toString().trim(),
      baseUrl: (json['baseUrl'] ?? json['url'] ?? '').toString().trim(),
      kind: _kindFrom(json['kind'] ?? json['type']),
      iconUrl: (json['iconUrl'] ?? json['logo_url'] ?? json['logoUrl'] ?? '').toString().trim(),
      builtIn: json['builtIn'] == true || (json['type'] ?? '').toString().toLowerCase() == 'builtin',
      searchTemplate: (json['searchTemplate'] ?? json['search_template'] ?? '').toString().trim(),
      description: (json['description'] ?? '').toString().trim(),
      key: (json['key'] ?? json['id'] ?? '').toString().trim(),
      enabled: json['enabled'] == null ? true : json['enabled'] == true,
      sortOrder: int.tryParse((json['sortOrder'] ?? json['sort_order'] ?? '0').toString()) ?? 0,
      config: rawConfig is Map ? Map<String, dynamic>.from(rawConfig) : const <String, dynamic>{},
    );
  }

  static String encodeList(List<ContentSourceDefinition> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());

  static List<ContentSourceDefinition> decodeList(String raw) {
    try {
      final parsed = jsonDecode(raw);
      final list = parsed is Map ? parsed['sources'] : parsed;
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((e) => ContentSourceDefinition.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.id.isNotEmpty)
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
    description: 'المصدر الرئيسي لتطبيق سينماتي',
    sortOrder: 10,
  ),
  ContentSourceDefinition(
    id: 'akwam',
    name: 'أكوام',
    baseUrl: 'https://akwam.ss',
    kind: ContentSourceKind.website,
    builtIn: true,
    description: 'مكتبة أكوام للأفلام والمسلسلات',
    sortOrder: 20,
  ),
];
