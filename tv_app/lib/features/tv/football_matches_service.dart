import 'package:dio/dio.dart';

import 'football_match_models.dart';

/// Lightweight feed for the TV hero. The existing channel source stays the
/// playback source; this service only tells the TV UI which football match is
/// live/next during the coming 24 hours.
class FootballMatchesService {
  FootballMatchesService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://matchora.to/api/v1/',
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 12),
                responseType: ResponseType.json,
                headers: const {
                  'Accept': 'application/json',
                  'User-Agent': 'Cinematy/1.0',
                },
              ),
            );

  final Dio _dio;

  DateTime? _featuredFutureCacheAt;
  List<FootballMatch> _featuredFutureCache = const [];

  // Backward-compatible alias used by older UI paths. The mobile TV hero now
  // intentionally works on the next rolling 24 hours, not only the calendar day.
  Future<List<FootballMatch>> getTodayMatches() => getNext24HourMatches();

  Future<List<FootballMatch>> getNextFeaturedClubMatches({
    bool needRealMadrid = true,
    bool needBarcelona = true,
  }) async {
    if (!needRealMadrid && !needBarcelona) return const [];

    final now = DateTime.now();
    final cachedAt = _featuredFutureCacheAt;
    if (cachedAt != null &&
        now.difference(cachedAt) < const Duration(hours: 6) &&
        _featuredFutureCache.isNotEmpty) {
      return _filterFeaturedFutureCache(
        _featuredFutureCache,
        needRealMadrid: needRealMadrid,
        needBarcelona: needBarcelona,
      );
    }

    FootballMatch? nextReal;
    FootballMatch? nextBarca;
    final startDay = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));

    // Scan only until both marquee clubs are found. In normal league schedules
    // this finishes after a handful of requests, while still covering long gaps.
    for (var dayOffset = 0; dayOffset < 45; dayOffset++) {
      final date = startDay.add(Duration(days: dayOffset));
      try {
        final response = await _dio.get<dynamic>(
          'schedule',
          queryParameters: {'date': _yyyyMmDd(date)},
        );
        for (final raw in _extractRows(response.data)) {
          if (raw is! Map) continue;
          final match = _parse(Map<String, dynamic>.from(raw));
          if (match == null || !_isAllowedMatch(match)) continue;
          final start = match.startsAt;
          if (start == null || !start.isAfter(now)) continue;

          final clubs = _featuredClubs(match);
          if (clubs.$1 && (nextReal == null || start.isBefore(nextReal.startsAt!))) {
            nextReal = match;
          }
          if (clubs.$2 && (nextBarca == null || start.isBefore(nextBarca.startsAt!))) {
            nextBarca = match;
          }
        }
      } catch (_) {
        // Skip a failed day and continue searching forward.
      }

      if (nextReal != null && nextBarca != null) break;
    }

    final found = <FootballMatch>[
      if (nextReal != null) nextReal,
      if (nextBarca != null && nextBarca.id != nextReal?.id) nextBarca,
    ]..sort((a, b) => (a.startsAt ?? DateTime(9999)).compareTo(b.startsAt ?? DateTime(9999)));

    _featuredFutureCacheAt = now;
    _featuredFutureCache = List.unmodifiable(found);
    return _filterFeaturedFutureCache(
      found,
      needRealMadrid: needRealMadrid,
      needBarcelona: needBarcelona,
    );
  }

  static List<FootballMatch> _filterFeaturedFutureCache(
    List<FootballMatch> matches, {
    required bool needRealMadrid,
    required bool needBarcelona,
  }) {
    return matches.where((match) {
      final clubs = _featuredClubs(match);
      return (needRealMadrid && clubs.$1) || (needBarcelona && clubs.$2);
    }).toList(growable: false);
  }

  static (bool, bool) _featuredClubs(FootballMatch match) {
    final home = _normalize(match.homeName);
    final away = _normalize(match.awayName);
    bool real(String value) =>
        value.contains('real madrid') || value.contains('ريال مدريد');
    bool barca(String value) =>
        value.contains('barcelona') ||
        value.contains('fc barcelona') ||
        value.contains('برشلونة');
    return (real(home) || real(away), barca(home) || barca(away));
  }

  Future<List<FootballMatch>> getNext24HourMatches() async {
    final now = DateTime.now();
    final until = now.add(const Duration(hours: 24));
    final dates = <String>{_yyyyMmDd(now), _yyyyMmDd(until)};
    final byId = <String, FootballMatch>{};

    for (final date in dates) {
      try {
        final response = await _dio.get<dynamic>(
          'schedule',
          queryParameters: {'date': date},
        );
        for (final raw in _extractRows(response.data)) {
          if (raw is! Map) continue;
          final match = _parse(Map<String, dynamic>.from(raw));
          if (match == null || !_isAllowedMatch(match)) continue;

          final start = match.startsAt;
          final withinWindow = start != null &&
              !start.isBefore(now.subtract(const Duration(minutes: 10))) &&
              !start.isAfter(until);
          if (!match.isLive && !withinWindow) continue;
          byId[match.id] = match;
        }
      } catch (_) {
        // One date failing must not prevent the other date from being shown.
      }
    }

    final matches = byId.values.toList(growable: false)
      ..sort((a, b) {
        if (a.isLive != b.isLive) return a.isLive ? -1 : 1;
        final at = a.startsAt;
        final bt = b.startsAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return at.compareTo(bt);
      });
    return matches;
  }

  static String _yyyyMmDd(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  static List<dynamic> _extractRows(dynamic data) {
    if (data is List) return data;
    if (data is! Map) return const [];
    for (final key in const ['events', 'data', 'matches', 'results', 'items']) {
      final value = data[key];
      if (value is List) return value;
      if (value is Map) {
        for (final nested in const ['events', 'data', 'matches', 'results', 'items']) {
          final list = value[nested];
          if (list is List) return list;
        }
      }
    }
    return const [];
  }

  static FootballMatch? _parse(Map<String, dynamic> json) {
    final homeName = _scalarString(json['home']) ??
        _scalarString(json['home_name']) ??
        _teamName(json['homeTeam']) ??
        _teamName(json['home_team']) ??
        _teamName(json['home']);
    final awayName = _scalarString(json['away']) ??
        _scalarString(json['away_name']) ??
        _teamName(json['awayTeam']) ??
        _teamName(json['away_team']) ??
        _teamName(json['away']);
    if (homeName == null || awayName == null) return null;

    final parsedScore = _parseScore(_string(json['score']));
    final homeScore = _int(json['home_score']) ??
        _int(json['homeScore']) ??
        parsedScore?.$1;
    final awayScore = _int(json['away_score']) ??
        _int(json['awayScore']) ??
        parsedScore?.$2;
    final minute = _int(json['minute']) ?? _int(json['elapsed']);
    final rawStatus = _string(json['status']) ?? '';
    final live = json['live'] == true;
    final startsAt = _parseKickoff(
      json['kickoff'] ??
          json['kickoff_ts'] ??
          json['kickoffUtc'] ??
          json['start_time'] ??
          json['startsAt'] ??
          json['date'],
    );

    return FootballMatch(
      id: _string(json['id']) ??
          _string(json['event_id']) ??
          '${homeName}_${awayName}_${startsAt?.millisecondsSinceEpoch ?? ''}',
      homeName: homeName,
      awayName: awayName,
      homeLogo: _scalarString(json['home_logo']) ??
          _scalarString(json['homeLogo']) ??
          _scalarString(json['home_badge']) ??
          _scalarString(json['homeBadge']) ??
          _teamLogo(json['homeTeam']) ??
          _teamLogo(json['home_team']) ??
          _teamLogo(json['home']) ??
          '',
      awayLogo: _scalarString(json['away_logo']) ??
          _scalarString(json['awayLogo']) ??
          _scalarString(json['away_badge']) ??
          _scalarString(json['awayBadge']) ??
          _teamLogo(json['awayTeam']) ??
          _teamLogo(json['away_team']) ??
          _teamLogo(json['away']) ??
          '',
      league: _scalarString(json['league']) ??
          _scalarString(json['competition']) ??
          _leagueName(json['league']) ??
          _leagueName(json['competition']) ??
          _leagueName(json['tournament']) ??
          '',
      leagueLogo: _scalarString(json['league_logo']) ??
          _scalarString(json['leagueLogo']) ??
          '',
      homeScore: homeScore,
      awayScore: awayScore,
      minute: minute,
      status: _status(rawStatus, live, minute, homeScore, awayScore),
      startsAt: startsAt,
    );
  }

  static (int, int)? _parseScore(String? value) {
    if (value == null) return null;
    final match = RegExp(r'(\d+)\s*[-:]\s*(\d+)').firstMatch(value);
    if (match == null) return null;
    final home = int.tryParse(match.group(1) ?? '');
    final away = int.tryParse(match.group(2) ?? '');
    return home == null || away == null ? null : (home, away);
  }

  static DateTime? _parseKickoff(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) {
      final value = raw.toInt();
      final milliseconds = value > 9999999999 ? value : value * 1000;
      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true).toLocal();
    }
    final text = '$raw'.trim();
    if (text.isEmpty) return null;
    final numeric = int.tryParse(text);
    if (numeric != null) {
      final milliseconds = numeric > 9999999999 ? numeric : numeric * 1000;
      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true).toLocal();
    }
    final parsed = DateTime.tryParse(text);
    return parsed?.toLocal();
  }

  static FootballMatchStatus _status(
    String raw,
    bool live,
    int? minute,
    int? home,
    int? away,
  ) {
    final status = raw.toLowerCase().trim();
    if (live ||
        status.contains('live') ||
        status.contains('playing') ||
        status.contains('in progress') ||
        status.contains('مباشر')) {
      return FootballMatchStatus.live;
    }
    if (status == 'ft' ||
        status.contains('finish') ||
        status.contains('ended') ||
        status.contains('انته')) {
      return FootballMatchStatus.finished;
    }
    if (status.contains('postpon') ||
        status.contains('cancel') ||
        status.contains('تأجل')) {
      return FootballMatchStatus.postponed;
    }
    if (minute != null && minute > 0) return FootballMatchStatus.live;
    if (home != null && away != null && status.isNotEmpty) {
      if (!status.contains('schedule') && !status.contains('not started')) {
        return FootballMatchStatus.live;
      }
    }
    return FootballMatchStatus.scheduled;
  }

  static bool _isAllowedMatch(FootballMatch match) {
    final value = _normalize(match.league);
    if (value.isEmpty) return false;

    // Only the competitions requested for the TV hero:
    // UEFA Champions League + the five major European domestic leagues.
    // Keep youth/women/reserve/qualifying/second-division variants out.
    final excludedVariant = value.contains('women') ||
        value.contains('womens') ||
        value.contains('female') ||
        value.contains('youth') ||
        value.contains('u19') ||
        value.contains('u20') ||
        value.contains('u21') ||
        value.contains('u23') ||
        value.contains('reserve') ||
        value.contains('qualification') ||
        value.contains('qualifying') ||
        value.contains('qualifier') ||
        value.contains('playoff') ||
        value.contains('play-off') ||
        value.contains('2. bundesliga') ||
        value.contains('bundesliga 2') ||
        value.contains('la liga 2') ||
        value.contains('laliga 2') ||
        value.contains('ligue 2') ||
        value.contains('serie b') ||
        value.contains('championship') ||
        value.contains('السيدات') ||
        value.contains('نسائي') ||
        value.contains('الشباب') ||
        value.contains('تحت ') ||
        value.contains('تصفيات') ||
        value.contains('تأهيلي');
    if (excludedVariant) return false;

    final isChampionsLeague =
        value == 'uefa champions league' ||
        value == 'champions league' ||
        value == 'european champions league' ||
        value == 'europe champions league' ||
        value == 'دوري ابطال اوروبا' ||
        value == 'دوري أبطال أوروبا';
    if (isChampionsLeague) return true;

    // Explicitly reject similarly-named continental competitions.
    if (value.contains('afc champions league') ||
        value.contains('caf champions league') ||
        value.contains('concacaf champions') ||
        value.contains('ofc champions')) {
      return false;
    }

    final isPremierLeague = value == 'premier league' ||
        value == 'english premier league' ||
        value == 'england premier league' ||
        value == 'premier league england' ||
        value == 'الدوري الانجليزي الممتاز' ||
        value == 'الدوري الإنجليزي الممتاز';

    final isLaLiga = value == 'la liga' ||
        value == 'laliga' ||
        value == 'spanish la liga' ||
        value == 'spain la liga' ||
        value == 'la liga spain' ||
        value == 'الدوري الاسباني' ||
        value == 'الدوري الإسباني';

    final isSerieA = value == 'serie a' ||
        value == 'italian serie a' ||
        value == 'italy serie a' ||
        value == 'serie a italy' ||
        value == 'الدوري الايطالي' ||
        value == 'الدوري الإيطالي';

    final isBundesliga = value == 'bundesliga' ||
        value == 'german bundesliga' ||
        value == 'germany bundesliga' ||
        value == 'bundesliga germany' ||
        value == 'الدوري الالماني' ||
        value == 'الدوري الألماني';

    final isLigue1 = value == 'ligue 1' ||
        value == 'french ligue 1' ||
        value == 'france ligue 1' ||
        value == 'ligue 1 france' ||
        value == 'الدوري الفرنسي';

    return isPremierLeague || isLaLiga || isSerieA || isBundesliga || isLigue1;
  }


  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String? _teamName(dynamic value) {
    if (value is String) return value.trim();
    if (value is Map) {
      return _string(value['name'] ?? value['title'] ?? value['shortName']);
    }
    return null;
  }

  static String? _teamLogo(dynamic value) {
    if (value is Map) {
      return _scalarString(
        value['logo'] ??
            value['logoUrl'] ??
            value['logo_url'] ??
            value['image'] ??
            value['imageUrl'] ??
            value['icon'] ??
            value['badge'] ??
            value['crest'],
      );
    }
    return null;
  }

  static String? _leagueName(dynamic value) {
    if (value is String) return value.trim();
    if (value is Map) {
      final unique = value['uniqueTournament'];
      if (unique is Map) {
        final name = _scalarString(unique['name'] ?? unique['title']);
        if (name != null) return name;
      }
      return _scalarString(value['name'] ?? value['title']);
    }
    return null;
  }

  static String? _scalarString(dynamic value) {
    if (value == null || value is Map || value is List) return null;
    return _string(value);
  }

  static String? _string(dynamic value) {
    if (value == null) return null;
    final text = '$value'.trim();
    return text.isEmpty || text == 'null' ? null : text;
  }

  static int? _int(dynamic value) {
    if (value is num) return value.toInt();
    final text = _string(value);
    if (text == null) return null;
    return int.tryParse(RegExp(r'-?\d+').firstMatch(text)?.group(0) ?? '');
  }
}
