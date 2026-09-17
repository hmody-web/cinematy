import 'package:dio/dio.dart';

import 'football_match_models.dart';

class SportsMatchHeroData {
  const SportsMatchHeroData({
    required this.match,
    this.eventId = '',
    this.homePlayer = '',
    this.awayPlayer = '',
    this.homeBadge = '',
    this.awayBadge = '',
    this.leagueBadge = '',
    this.stadiumName = '',
    this.homeColour = '',
    this.awayColour = '',
    this.broadcastName = '',
    this.broadcastLogo = '',
  });

  final FootballMatch match;
  final String eventId;
  final String homePlayer;
  final String awayPlayer;
  final String homeBadge;
  final String awayBadge;
  final String leagueBadge;
  final String stadiumName;
  final String homeColour;
  final String awayColour;
  final String broadcastName;
  final String broadcastLogo;

  SportsMatchHeroData withMatch(FootballMatch value) => SportsMatchHeroData(
        match: value,
        eventId: eventId,
        homePlayer: homePlayer,
        awayPlayer: awayPlayer,
        homeBadge: homeBadge,
        awayBadge: awayBadge,
        leagueBadge: leagueBadge,
        stadiumName: stadiumName,
        homeColour: homeColour,
        awayColour: awayColour,
        broadcastName: broadcastName,
        broadcastLogo: broadcastLogo,
      );

  SportsMatchHeroData withBroadcast({String? name, String? logo}) => SportsMatchHeroData(
        match: match,
        eventId: eventId,
        homePlayer: homePlayer,
        awayPlayer: awayPlayer,
        homeBadge: homeBadge,
        awayBadge: awayBadge,
        leagueBadge: leagueBadge,
        stadiumName: stadiumName,
        homeColour: homeColour,
        awayColour: awayColour,
        broadcastName: name ?? broadcastName,
        broadcastLogo: logo ?? broadcastLogo,
      );
}

/// Artwork-only enrichment from TheSportsDB V1 free API.
///
/// It deliberately enriches only the single hero match and uses an in-memory
/// cache so reopening the TV section does not repeatedly hit the free limit.
class SportsMatchHeroService {
  SportsMatchHeroService({Dio? dio, Dio? matchoraDio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://www.thesportsdb.com/api/v1/json/123/',
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 10),
                responseType: ResponseType.json,
                headers: const {
                  'Accept': 'application/json',
                  'User-Agent': 'Cinematy/1.0',
                },
              ),
            ),
        _matchoraDio = matchoraDio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://matchora.to/api/v1/',
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 10),
                responseType: ResponseType.json,
                headers: const {
                  'Accept': 'application/json',
                  'User-Agent': 'Cinematy/1.0',
                },
              ),
            );

  final Dio _dio;
  final Dio _matchoraDio;

  static final Map<String, _CachedHero> _cache = <String, _CachedHero>{};
  static final Map<String, _CachedBroadcast> _matchoraBroadcastCache =
      <String, _CachedBroadcast>{};
  static const Duration _cacheAge = Duration(minutes: 45);

  Future<SportsMatchHeroData> enrich(FootballMatch match) async {
    final cacheKey = '${match.homeName}|${match.awayName}|${match.startsAt?.year}-${match.startsAt?.month}-${match.startsAt?.day}';
    final cached = _cache[cacheKey];
    if (cached != null && DateTime.now().difference(cached.savedAt) < _cacheAge) {
      final base = cached.data.withMatch(match);
      final broadcast = await _matchoraBroadcastInfo(match);
      return base.withBroadcast(
        name: broadcast?.name,
        logo: broadcast?.logo,
      );
    }

    final event = await _findEvent(match);
    if (event == null) {
      final broadcast = await _matchoraBroadcastInfo(match);
      final fallback = SportsMatchHeroData(
        match: match,
        homeBadge: match.homeLogo,
        awayBadge: match.awayLogo,
        leagueBadge: match.leagueLogo,
        broadcastName: broadcast?.name ?? '',
        broadcastLogo: broadcast?.logo ?? '',
      );
      _cache[cacheKey] = _CachedHero(fallback, DateTime.now());
      return fallback;
    }

    final eventId = _text(event['idEvent']);
    final homeTeamId = _text(event['idHomeTeam']);
    final awayTeamId = _text(event['idAwayTeam']);
    final leagueId = _text(event['idLeague']);
    final stadiumName = await _eventVenue(eventId, event);

    final teamResults = await Future.wait([
      _teamInfo(homeTeamId),
      _teamInfo(awayTeamId),
      _leagueInfo(leagueId),
      _broadcastInfo(eventId, event, match),
      _lineup(eventId),
    ]);

    final homeTeam = teamResults[0] as Map<String, dynamic>?;
    final awayTeam = teamResults[1] as Map<String, dynamic>?;
    final league = teamResults[2] as Map<String, dynamic>?;
    final broadcast = teamResults[3] as _Broadcast?;
    final lineup = teamResults[4] as List<Map<String, dynamic>>;

    final homeCaptainId = _captainId(lineup, homeTeamId, match.homeName);
    final awayCaptainId = _captainId(lineup, awayTeamId, match.awayName);

    final playerResults = await Future.wait([
      _playerArtwork(
        teamId: homeTeamId,
        currentCaptainId: homeCaptainId,
        teamName: match.homeName,
      ),
      _playerArtwork(
        teamId: awayTeamId,
        currentCaptainId: awayCaptainId,
        teamName: match.awayName,
      ),
    ]);

    final data = SportsMatchHeroData(
      match: match,
      eventId: eventId,
      homePlayer: playerResults[0],
      awayPlayer: playerResults[1],
      homeBadge: _firstText([
        event['strHomeTeamBadge'],
        homeTeam?['strBadge'],
        homeTeam?['strLogo'],
        match.homeLogo,
      ]),
      awayBadge: _firstText([
        event['strAwayTeamBadge'],
        awayTeam?['strBadge'],
        awayTeam?['strLogo'],
        match.awayLogo,
      ]),
      leagueBadge: _firstText([
        event['strLeagueBadge'],
        league?['strBadge'],
        league?['strLogo'],
        match.leagueLogo,
      ]),
      stadiumName: stadiumName,
      homeColour: _firstText([
        homeTeam?['strColour1'],
        homeTeam?['strColour2'],
      ]),
      awayColour: _firstText([
        awayTeam?['strColour1'],
        awayTeam?['strColour2'],
      ]),
      broadcastName: broadcast?.name ?? '',
      broadcastLogo: broadcast?.logo ?? '',
    );

    _cache[cacheKey] = _CachedHero(data, DateTime.now());
    return data;
  }

  Future<Map<String, dynamic>?> _findEvent(FootballMatch match) async {
    final date = match.startsAt ?? DateTime.now();
    final day = _date(date);
    final queries = <String>[
      '${match.homeName}_vs_${match.awayName}',
      '${match.awayName}_vs_${match.homeName}',
    ];

    for (final query in queries) {
      try {
        final response = await _dio.get<dynamic>(
          'searchevents.php',
          queryParameters: {'e': query, 'd': day},
        );
        final events = _mapsFrom(response.data, const ['event', 'events']);
        if (events.isEmpty) continue;
        // Never accept an event by a loose one-team match. A previous fuzzy
        // threshold could pair the correct home side with an unrelated away
        // side (or vice versa), which then leaked that unrelated team's
        // player artwork into the hero card. Both clubs must match the fixture.
        final exact = events.where((event) => _eventMatchesFixture(event, match)).toList();
        if (exact.isEmpty) continue;
        exact.sort((a, b) => _eventScore(b, match).compareTo(_eventScore(a, match)));
        return exact.first;
      } catch (_) {
        // Try the opposite title ordering.
      }
    }
    return null;
  }

  int _eventScore(Map<String, dynamic> event, FootballMatch match) {
    final home = _normal(_text(event['strHomeTeam']));
    final away = _normal(_text(event['strAwayTeam']));
    final wantedHome = _normal(match.homeName);
    final wantedAway = _normal(match.awayName);
    var score = 0;
    if (_similar(home, wantedHome)) score += 3;
    if (_similar(away, wantedAway)) score += 3;
    if (_similar(home, wantedAway)) score += 1;
    if (_similar(away, wantedHome)) score += 1;
    final league = _normal(_text(event['strLeague']));
    if (league.isNotEmpty && _similar(league, _normal(match.league))) score += 1;
    return score;
  }

  bool _eventMatchesFixture(Map<String, dynamic> event, FootballMatch match) {
    final home = _canonicalTeamName(_text(event['strHomeTeam']));
    final away = _canonicalTeamName(_text(event['strAwayTeam']));
    final wantedHome = _canonicalTeamName(match.homeName);
    final wantedAway = _canonicalTeamName(match.awayName);
    if (home.isEmpty || away.isEmpty || wantedHome.isEmpty || wantedAway.isEmpty) {
      return false;
    }
    final direct = _sameTeam(home, wantedHome) && _sameTeam(away, wantedAway);
    final reversed = _sameTeam(home, wantedAway) && _sameTeam(away, wantedHome);
    return direct || reversed;
  }

  Future<String> _eventVenue(String eventId, Map<String, dynamic> event) async {
    final direct = _firstText([
      event['strVenue'],
      event['strStadium'],
      event['strArena'],
    ]);
    if (direct.isNotEmpty || eventId.isEmpty) return direct;

    try {
      final response = await _dio.get<dynamic>(
        'lookupevent.php',
        queryParameters: {'id': eventId},
      );
      final rows = _mapsFrom(response.data, const ['events', 'event']);
      if (rows.isEmpty) return '';
      return _firstText([
        rows.first['strVenue'],
        rows.first['strStadium'],
        rows.first['strArena'],
      ]);
    } catch (_) {
      return '';
    }
  }

  Future<Map<String, dynamic>?> _teamInfo(String id) async {
    if (id.isEmpty) return null;
    try {
      final response = await _dio.get<dynamic>('lookupteam.php', queryParameters: {'id': id});
      final rows = _mapsFrom(response.data, const ['teams', 'team']);
      return rows.isEmpty ? null : rows.first;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _leagueInfo(String id) async {
    if (id.isEmpty) return null;
    try {
      final response = await _dio.get<dynamic>('lookupleague.php', queryParameters: {'id': id});
      final rows = _mapsFrom(response.data, const ['leagues', 'league']);
      return rows.isEmpty ? null : rows.first;
    } catch (_) {
      return null;
    }
  }

  Future<_Broadcast?> _matchoraBroadcastInfo(FootballMatch match) async {
    final eventId = match.id.trim();
    if (eventId.isEmpty || eventId.contains('_')) return null;

    final cached = _matchoraBroadcastCache[eventId];
    final maxAge = _broadcastCacheAge(match);
    if (cached != null && DateTime.now().difference(cached.savedAt) < maxAge) {
      return cached.broadcast;
    }

    try {
      final response = await _matchoraDio.get<dynamic>('events/$eventId');
      final candidates = _extractMatchoraBroadcasts(response.data);
      if (candidates.isEmpty) {
        _matchoraBroadcastCache[eventId] =
            _CachedBroadcast(null, DateTime.now());
        return null;
      }

      candidates.sort(
        (a, b) => _matchoraBroadcastPriority(b.name)
            .compareTo(_matchoraBroadcastPriority(a.name)),
      );
      final best = candidates.first;
      final cleaned = _Broadcast(
        _cleanBroadcastName(best.name),
        best.logo,
      );
      _matchoraBroadcastCache[eventId] =
          _CachedBroadcast(cleaned, DateTime.now());
      return cleaned;
    } catch (_) {
      // Matchora is the authoritative broadcaster source for this hero. If a
      // request fails, let TheSportsDB provide a visual/fallback broadcaster
      // rather than hiding the match card.
      return cached?.broadcast;
    }
  }

  Duration _broadcastCacheAge(FootballMatch match) {
    if (match.isLive) return const Duration(minutes: 2);
    final start = match.startsAt;
    if (start == null) return const Duration(minutes: 10);
    final untilKickoff = start.difference(DateTime.now());
    if (untilKickoff <= const Duration(hours: 6)) {
      return const Duration(minutes: 5);
    }
    return const Duration(minutes: 15);
  }

  List<_Broadcast> _extractMatchoraBroadcasts(dynamic root) {
    final output = <_Broadcast>[];
    final seen = <String>{};

    void add(String name, String logo) {
      final cleaned = name.trim();
      if (cleaned.isEmpty) return;
      final key = _normal(cleaned);
      if (key.isEmpty || !seen.add(key)) return;
      output.add(_Broadcast(cleaned, logo.trim()));
    }

    void walk(dynamic value, {bool inChannelTree = false}) {
      if (value is List) {
        for (final item in value) {
          if (item is String && inChannelTree) {
            add(item, '');
          } else {
            walk(item, inChannelTree: inChannelTree);
          }
        }
        return;
      }

      if (value is! Map) return;
      final map = Map<String, dynamic>.from(value);

      if (inChannelTree) {
        final name = _firstText([
          map['name'],
          map['channel_name'],
          map['channelName'],
          map['channel'],
          map['title'],
          map['label'],
          map['display_name'],
          map['displayName'],
          map['broadcaster'],
          map['network'],
        ]);
        if (name.isNotEmpty) {
          add(
            name,
            _firstText([
              map['logo'],
              map['icon'],
              map['image'],
              map['channel_logo'],
              map['channelLogo'],
              map['thumb'],
            ]),
          );
        }
      }

      for (final entry in map.entries) {
        final key = _normal('${entry.key}').replaceAll(' ', '');
        final isChannelKey = key.contains('channel') ||
            key.contains('broadcaster') ||
            key == 'tv' ||
            key.contains('network');
        final child = entry.value;

        if (child is String) {
          if (isChannelKey && child.trim().isNotEmpty) {
            add(child, '');
          }
          continue;
        }

        if (child is Map || child is List) {
          walk(
            child,
            inChannelTree: inChannelTree || isChannelKey,
          );
        }
      }
    }

    walk(root);
    return output;
  }

  int _matchoraBroadcastPriority(String value) {
    final name = _normal(value);
    final compact = name.replaceAll(' ', '');
    final hasNumber = RegExp(r'\b\d{1,2}\b').hasMatch(name);
    final isBein = compact.contains('beinsports') ||
        compact.contains('bein') ||
        value.contains('بين سبورت') ||
        value.contains('بي إن');

    if (isBein) {
      var score = 1000;
      if (name.contains('mena') ||
          name.contains('qatar') ||
          name.contains('middle east') ||
          name.contains('arab')) {
        score += 180;
      }
      if (hasNumber) score += 60;
      if (name.contains('premium')) score += 15;
      return score;
    }

    if (name.contains('ssc')) return hasNumber ? 700 : 680;
    if (name.contains('alkass') || name.contains('al kass')) return 650;
    if (name.contains('abu dhabi')) return 620;
    if (name.contains('dubai sports')) return 600;
    if (name.contains('tnt sports')) return 520;
    if (name.contains('sky sports')) return 500;
    if (name.contains('dazn')) return 480;
    if (name.contains('espn')) return 460;
    return 100;
  }

  String _cleanBroadcastName(String value) {
    var name = value.trim();
    if (!_isBein(name)) return name;

    // Keep the actual beIN channel number/name while removing location/language
    // decorations that make matching the user's local TV list less reliable.
    name = name
        .replaceAll(RegExp(r'\b(qatar|mena|arabic|english|middle east)\b',
            caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return name;
  }

  Future<_Broadcast?> _broadcastInfo(
    String eventId,
    Map<String, dynamic> event,
    FootballMatch match,
  ) async {
    // Matchora is already the source of the fixture id and exposes the full
    // channel list for that exact fixture. Prefer it before TheSportsDB.
    final matchora = await _matchoraBroadcastInfo(match);
    if (matchora != null) return matchora;

    // 1) If the event itself already exposes a beIN station, use it immediately.
    final eventBroadcastName = _firstText([
      event['strTVStation'],
      event['strChannel'],
      event['strTVBroadcast'],
    ]);
    if (_isBein(eventBroadcastName)) {
      return _Broadcast(eventBroadcastName, '');
    }

    // 2) The free lookuptv endpoint only exposes a small number of channels,
    // so check those first and prefer beIN if it is present there.
    _Broadcast? ordinaryFallback;
    if (eventId.isNotEmpty) {
      try {
        final response = await _dio.get<dynamic>(
          'lookuptv.php',
          queryParameters: {'id': eventId},
        );
        final rows = _mapsFrom(
          response.data,
          const ['tvevent', 'tvevents', 'tv', 'channels', 'broadcasts'],
        );
        if (rows.isNotEmpty) {
          rows.sort((a, b) => _broadcastPriority(b).compareTo(_broadcastPriority(a)));
          for (final row in rows) {
            final candidate = _broadcastFromRow(row);
            if (candidate == null) continue;
            if (_isBein(candidate.name)) return candidate;
            ordinaryFallback ??= candidate;
          }
        }
      } catch (_) {
        // Continue to the Qatar/MENA beIN schedule fallback below.
      }
    }

    // 3) Free lookuptv may omit beIN even when TheSportsDB has it in the
    // channel schedule. Probe the MENA/Qatar beIN channels directly, starting
    // with 1 then 2, 3... and stop as soon as this exact match is found.
    final qatarBein = await _findBeinQatarBroadcast(match);
    if (qatarBein != null) return qatarBein;

    // 4) Only when no beIN channel is found do we expose another broadcaster.
    if (ordinaryFallback != null) return ordinaryFallback;
    if (eventBroadcastName.isNotEmpty) {
      return _Broadcast(eventBroadcastName, '');
    }
    return null;
  }

  static const List<String> _beinQatarChannels = <String>[
    'BeIN Sports 1 Qatar',
    'BeIN Sports 2 Qatar',
    'BeIN Sports 3 Qatar',
    'BeIN Sports 4 Qatar',
    'BeIN Sports 5 Qatar',
    'BeIN Sports 6 Qatar',
    'BeIN Sports 7 Qatar',
  ];

  static final Map<String, _Broadcast?> _beinScheduleCache = <String, _Broadcast?>{};

  Future<_Broadcast?> _findBeinQatarBroadcast(FootballMatch match) async {
    final start = match.startsAt ?? DateTime.now();
    final day = _date(start);
    final cacheKey = '${match.homeName}|${match.awayName}|$day';
    if (_beinScheduleCache.containsKey(cacheKey)) {
      return _beinScheduleCache[cacheKey];
    }

    for (final channelName in _beinQatarChannels) {
      try {
        final response = await _dio.get<dynamic>(
          'eventstv.php',
          queryParameters: {
            'd': day,
            's': 'Soccer',
            'c': channelName.replaceAll(' ', '_'),
          },
        );
        final rows = _mapsFrom(
          response.data,
          const ['tvevents', 'tvevent', 'events', 'event', 'tv'],
        );
        for (final row in rows) {
          if (!_tvRowMatchesMatch(row, match)) continue;
          final foundName = _firstText([
            row['strChannel'],
            row['strTVStation'],
            row['strName'],
            channelName,
          ]);
          final result = _Broadcast(
            foundName.isEmpty ? channelName : foundName,
            _firstText([
              row['strLogo'],
              row['strChannelLogo'],
              row['strBadge'],
            ]),
          );
          _beinScheduleCache[cacheKey] = result;
          return result;
        }
      } catch (_) {
        // Try the next numbered beIN Qatar channel.
      }
    }

    _beinScheduleCache[cacheKey] = null;
    return null;
  }

  bool _tvRowMatchesMatch(Map<String, dynamic> row, FootballMatch match) {
    final rowHome = _normal(_firstText([
      row['strHomeTeam'],
      row['homeTeam'],
    ]));
    final rowAway = _normal(_firstText([
      row['strAwayTeam'],
      row['awayTeam'],
    ]));
    final wantedHome = _normal(match.homeName);
    final wantedAway = _normal(match.awayName);

    if (rowHome.isNotEmpty && rowAway.isNotEmpty) {
      final direct = _similar(rowHome, wantedHome) && _similar(rowAway, wantedAway);
      final reversed = _similar(rowHome, wantedAway) && _similar(rowAway, wantedHome);
      if (direct || reversed) return true;
    }

    final title = _normal(_firstText([
      row['strEvent'],
      row['strEventAlternate'],
      row['event'],
      row['name'],
    ]));
    if (title.isEmpty) return false;
    return _similar(title, '$wantedHome vs $wantedAway') ||
        _similar(title, '$wantedAway vs $wantedHome') ||
        (title.contains(wantedHome) && title.contains(wantedAway));
  }

  _Broadcast? _broadcastFromRow(Map<String, dynamic> row) {
    final name = _firstText([
      row['strChannel'],
      row['strTVStation'],
      row['strName'],
      row['channel'],
    ]);
    if (name.isEmpty) return null;
    return _Broadcast(
      name,
      _firstText([
        row['strLogo'],
        row['strChannelLogo'],
        row['strBadge'],
      ]),
    );
  }

  bool _isBein(String value) {
    final normalized = _normal(value).replaceAll(' ', '');
    return normalized.contains('beinsports') ||
        normalized.contains('bein') ||
        value.contains('بين سبورت') ||
        value.contains('بي إن');
  }

  int _broadcastPriority(Map<String, dynamic> row) {
    final name = _normal(_firstText([
      row['strChannel'],
      row['strTVStation'],
      row['strName'],
      row['channel'],
    ]));
    final hasNumber = RegExp(r'\b\d+\b').hasMatch(name);
    if (name.contains('bein sports') || name.contains('bein') || name.contains('بي ان')) {
      return hasNumber ? 220 : 210;
    }
    if (name.contains('ssc')) return hasNumber ? 160 : 150;
    if (name.contains('alkass') || name.contains('al kass') || name.contains('الكاس')) {
      return hasNumber ? 145 : 140;
    }
    if (name.contains('abu dhabi') || name.contains('ابوظبي')) return 130;
    if (name.contains('dubai sports') || name.contains('دبي الرياضية')) return 120;
    if (name.contains('tnt sports')) return 110;
    if (name.contains('sky sports')) return 100;
    if (name.contains('dazn')) return 95;
    if (name.contains('espn')) return 90;
    return 10;
  }

  Future<List<Map<String, dynamic>>> _lineup(String eventId) async {
    if (eventId.isEmpty) return const [];
    try {
      final response = await _dio.get<dynamic>('lookuplineup.php', queryParameters: {'id': eventId});
      return _collectPlayerRows(response.data);
    } catch (_) {
      return const [];
    }
  }

  Future<String> _playerArtwork({
    required String teamId,
    required String currentCaptainId,
    required String teamName,
  }) async {
    if (teamId.isEmpty) return '';

    // 1) Current-match captain is the strongest signal because it is attached
    // to this exact fixture. Still validate his CURRENT team before using art.
    if (currentCaptainId.isNotEmpty) {
      final art = await _lookupPlayerArtForTeam(
        currentCaptainId,
        teamId: teamId,
        teamName: teamName,
      );
      if (art.isNotEmpty) return art;
    }

    // 2) For well-known clubs prefer a recognisable current star by name.
    // This also avoids stale renders such as a newly transferred player still
    // photographed in his former club shirt. Every result is team-validated.
    for (final starName in _preferredHeroPlayers(teamName)) {
      final art = await _searchPlayerArtForTeam(
        starName,
        teamId: teamId,
        teamName: teamName,
      );
      if (art.isNotEmpty) return art;
    }

    // 3) Use players from the club's latest REAL lineup. This works far better
    // across Premier League / Serie A / Bundesliga / Ligue 1 than relying only
    // on lookup_all_players, whose free response is limited and can be stale.
    final recentCandidates = await _recentLineupCandidates(teamId, teamName);
    for (final candidate in recentCandidates) {
      final art = await _lookupPlayerArtForTeam(
        candidate,
        teamId: teamId,
        teamName: teamName,
      );
      if (art.isNotEmpty) return art;
    }

    // 4) Previous-match captain, still guarded by current-team validation.
    final previousCaptain = await _captainFromPreviousEvent(teamId, teamName);
    if (previousCaptain.isNotEmpty) {
      final art = await _lookupPlayerArtForTeam(
        previousCaptain,
        teamId: teamId,
        teamName: teamName,
      );
      if (art.isNotEmpty) return art;
    }

    // 5) Last fallback: current squad rows with a transparent render. Never
    // take the first row blindly; validate team and rank recognisable players.
    try {
      final response = await _dio.get<dynamic>(
        'lookup_all_players.php',
        queryParameters: {'id': teamId},
      );
      final rows = _mapsFrom(response.data, const ['player', 'players'])
          .where((row) =>
              _playerBelongsToTeam(row, teamId: teamId, teamName: teamName) &&
              _playerRender(row).isNotEmpty &&
              _playerLooksActive(row) &&
              !_isKnownStaleRender(row, teamName))
          .toList();

      if (rows.isEmpty) return '';
      rows.sort((a, b) => _playerHeroScore(b).compareTo(_playerHeroScore(a)));
      return _playerRender(rows.first);
    } catch (_) {
      return '';
    }
  }

  Future<String> _searchPlayerArtForTeam(
    String playerName, {
    required String teamId,
    required String teamName,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        'searchplayers.php',
        queryParameters: {'p': playerName},
      );
      final rows = _mapsFrom(response.data, const ['player', 'players']);
      for (final row in rows) {
        if (!_playerBelongsToTeam(row, teamId: teamId, teamName: teamName)) continue;
        if (!_playerLooksActive(row)) continue;
        if (_isKnownStaleRender(row, teamName)) continue;
        final art = _playerRender(row);
        if (art.isNotEmpty) return art;
      }
    } catch (_) {}
    return '';
  }

  Future<List<String>> _recentLineupCandidates(String teamId, String teamName) async {
    if (teamId.isEmpty) return const [];
    try {
      final response = await _dio.get<dynamic>(
        'eventslast.php',
        queryParameters: {'id': teamId},
      );
      final events = _mapsFrom(response.data, const ['results', 'events', 'event']);
      final ids = <String>[];
      final seen = <String>{};

      // Inspect a few latest matches; stop as soon as enough current starters
      // are found so we stay comfortably under the free API rate limit.
      for (final event in events.take(3)) {
        final eventId = _text(event['idEvent']);
        if (eventId.isEmpty) continue;
        final rows = await _lineup(eventId);
        final teamRows = rows.where((row) {
          final rowTeamId = _firstText([row['idTeam'], row['teamId'], row['id_team']]);
          final rowTeamName = _firstText([row['strTeam'], row['team'], row['teamName']]);
          if (rowTeamId.isNotEmpty) return rowTeamId == teamId;
          return _sameTeam(_canonicalTeamName(rowTeamName), _canonicalTeamName(teamName));
        }).toList();

        teamRows.sort((a, b) => _lineupPlayerScore(b).compareTo(_lineupPlayerScore(a)));
        for (final row in teamRows) {
          final id = _firstText([row['idPlayer'], row['playerId'], row['id_player']]);
          if (id.isNotEmpty && seen.add(id)) ids.add(id);
          if (ids.length >= 6) return ids;
        }
      }
      return ids;
    } catch (_) {
      return const [];
    }
  }

  int _lineupPlayerScore(Map<String, dynamic> row) {
    var score = 0;
    if (_isCaptain(row)) score += 1000;
    final position = _normal(_firstText([
      row['strPosition'], row['position'], row['strRole'], row['positionName'],
    ]));
    if (position.contains('forward') || position.contains('striker') ||
        position.contains('wing') || position.contains('attack')) {
      score += 250;
    } else if (position.contains('mid')) {
      score += 180;
    } else if (position.contains('def')) {
      score += 110;
    } else if (position.contains('goal')) {
      score += 70;
    }
    final starter = _normal(_firstText([
      row['strSubstitute'], row['isSubstitute'], row['substitute'], row['strStarter'],
    ]));
    if (starter == '0' || starter == 'false' || starter == 'starter' || starter == '1') {
      score += 40;
    }
    return score;
  }

  List<String> _preferredHeroPlayers(String teamName) {
    final team = _canonicalTeamName(teamName);
    const stars = <String, List<String>>{
      'real madrid': ['Kylian Mbappe', 'Jude Bellingham', 'Vinicius Junior', 'Federico Valverde'],
      'atletico madrid': ['Julian Alvarez', 'Alex Baena', 'Pablo Barrios', 'Koke', 'Jan Oblak', 'Alexander Sorloth'],
      'barcelona': ['Lamine Yamal', 'Pedri', 'Raphinha', 'Frenkie de Jong'],
      'manchester city': ['Erling Haaland', 'Phil Foden', 'Rodri'],
      'manchester united': ['Bruno Fernandes'],
      'liverpool': ['Mohamed Salah', 'Florian Wirtz'],
      'arsenal': ['Bukayo Saka', 'Martin Odegaard'],
      'chelsea': ['Cole Palmer'],
      'tottenham': ['James Maddison'],
      'bayern munich': ['Harry Kane', 'Jamal Musiala', 'Joshua Kimmich'],
      'borussia dortmund': ['Julian Brandt'],
      'paris saint germain': ['Ousmane Dembele', 'Vitinha', 'Achraf Hakimi'],
      'marseille': ['Mason Greenwood'],
      'inter milan': ['Lautaro Martinez', 'Nicolo Barella'],
      'ac milan': ['Rafael Leao', 'Christian Pulisic'],
      'juventus': ['Kenan Yildiz'],
      'napoli': ['Scott McTominay'],
    };
    return stars[team] ?? const [];
  }

  bool _isKnownStaleRender(Map<String, dynamic> row, String teamName) {
    final team = _canonicalTeamName(teamName);
    final player = _normal(_firstText([row['strPlayer'], row['strPlayerAlternate'], row['name']]));
    // TheSportsDB currently lists Lookman at Atlético but his transparent
    // render can still show his former Atalanta kit. Skip that stale artwork.
    if (team == 'atletico madrid' && player.contains('lookman')) return true;
    return false;
  }

  Future<String> _captainFromPreviousEvent(String teamId, String teamName) async {
    if (teamId.isEmpty) return '';
    try {
      final response = await _dio.get<dynamic>('eventslast.php', queryParameters: {'id': teamId});
      final events = _mapsFrom(response.data, const ['results', 'events', 'event']);
      if (events.isEmpty) return '';
      final eventId = _text(events.first['idEvent']);
      if (eventId.isEmpty) return '';
      final lineup = await _lineup(eventId);
      return _captainId(lineup, teamId, teamName);
    } catch (_) {
      return '';
    }
  }

  String _captainId(
    List<Map<String, dynamic>> rows,
    String teamId,
    String teamName,
  ) {
    for (final row in rows) {
      if (!_isCaptain(row)) continue;
      final rowTeamId = _firstText([row['idTeam'], row['teamId'], row['id_team']]);
      final rowTeam = _normal(_firstText([row['strTeam'], row['team'], row['teamName']]));
      final matchesTeam = teamId.isNotEmpty && rowTeamId == teamId ||
          rowTeam.isNotEmpty && _similar(rowTeam, _normal(teamName));
      if (!matchesTeam && (rowTeamId.isNotEmpty || rowTeam.isNotEmpty)) continue;
      final playerId = _firstText([row['idPlayer'], row['playerId'], row['id_player']]);
      if (playerId.isNotEmpty) return playerId;
    }
    return '';
  }

  bool _isCaptain(Map<String, dynamic> row) {
    for (final key in const [
      'strCaptain',
      'isCaptain',
      'captain',
      'intCaptain',
      'is_captain',
      'strRole',
    ]) {
      final value = _normal(_text(row[key]));
      if (value == '1' ||
          value == 'true' ||
          value == 'yes' ||
          value == 'captain' ||
          value.contains('captain')) {
        return true;
      }
    }
    return false;
  }

  Future<String> _lookupPlayerArtForTeam(
    String playerId, {
    required String teamId,
    required String teamName,
  }) async {
    if (playerId.isEmpty) return '';
    try {
      final response = await _dio.get<dynamic>(
        'lookupplayer.php',
        queryParameters: {'id': playerId},
      );
      final rows = _mapsFrom(response.data, const ['players', 'player']);
      if (rows.isEmpty) return '';
      final row = rows.first;
      if (!_playerBelongsToTeam(row, teamId: teamId, teamName: teamName)) {
        return '';
      }
      if (!_playerLooksActive(row)) return '';
      if (_isKnownStaleRender(row, teamName)) return '';
      return _playerRender(row);
    } catch (_) {
      return '';
    }
  }

  bool _playerBelongsToTeam(
    Map<String, dynamic> row, {
    required String teamId,
    required String teamName,
  }) {
    final rowTeamId = _firstText([
      row['idTeam'],
      row['teamId'],
      row['id_team'],
      row['idTeam1'],
    ]);
    final rowTeamName = _normal(_firstText([
      row['strTeam'],
      row['strTeam1'],
      row['team'],
      row['teamName'],
    ]));

    // A conflicting explicit current-team id is a hard reject. This is the
    // important guard that prevents a render from a former club being used.
    if (rowTeamId.isNotEmpty && teamId.isNotEmpty && rowTeamId != teamId) {
      return false;
    }
    if (rowTeamName.isNotEmpty && teamName.trim().isNotEmpty) {
      return _similar(rowTeamName, _normal(teamName));
    }
    return rowTeamId.isNotEmpty && rowTeamId == teamId;
  }

  bool _playerLooksActive(Map<String, dynamic> row) {
    final status = _normal(_firstText([
      row['strStatus'],
      row['status'],
      row['strPlayerStatus'],
    ]));
    if (status.isEmpty) return true;
    const blocked = <String>[
      'retired',
      'inactive',
      'former',
      'released',
      'deceased',
    ];
    return !blocked.any(status.contains);
  }

  int _playerHeroScore(Map<String, dynamic> row) {
    var score = 0;

    // Prefer data explicitly indicating captain/leadership.
    if (_isCaptain(row)) score += 1000;

    // TheSportsDB sometimes exposes a popularity/love count. When available,
    // use it as a soft signal that the player is recognisable.
    final loved = int.tryParse(_text(row['intLoved'])) ??
        int.tryParse(_text(row['intPopular'])) ??
        int.tryParse(_text(row['intPopularity'])) ??
        0;
    score += loved.clamp(0, 500);

    final position = _normal(_firstText([
      row['strPosition'],
      row['position'],
      row['strRole'],
    ]));
    if (position.contains('forward') ||
        position.contains('wing') ||
        position.contains('striker') ||
        position.contains('attack')) {
      score += 180;
    } else if (position.contains('midfield')) {
      score += 140;
    } else if (position.contains('defen')) {
      score += 90;
    } else if (position.contains('goal')) {
      score += 60;
    }

    // Complete current-player records are more trustworthy than sparse legacy
    // records and usually contain fresher artwork.
    if (_text(row['strNumber']).isNotEmpty ||
        _text(row['intSquadNumber']).isNotEmpty) score += 40;
    if (_text(row['dateBorn']).isNotEmpty) score += 15;
    if (_text(row['strNationality']).isNotEmpty) score += 10;

    return score;
  }

  String _playerRender(Map<String, dynamic> row) {
    // Use only transparent player artwork. Prefer the cinematic Render, then
    // the transparent Cutout when a Render is unavailable. Never fall back to
    // strThumb/fanart because those are portrait/background images and caused
    // the identity-photo look the user explicitly rejected.
    return _firstText([
      row['strRender'],
      row['strCutout'],
    ]);
  }


  static List<Map<String, dynamic>> _mapsFrom(dynamic root, List<String> keys) {
    if (root is List) {
      return root.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (root is! Map) return const [];
    for (final key in keys) {
      final value = root[key];
      if (value is List) {
        return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      if (value is Map) return [Map<String, dynamic>.from(value)];
    }
    return const [];
  }

  static List<Map<String, dynamic>> _collectPlayerRows(dynamic root) {
    final out = <Map<String, dynamic>>[];
    void walk(dynamic value) {
      if (value is List) {
        for (final item in value) walk(item);
        return;
      }
      if (value is! Map) return;
      final map = Map<String, dynamic>.from(value);
      if (map.keys.any((key) =>
          key == 'idPlayer' || key == 'playerId' || key == 'strPlayer')) {
        out.add(map);
      }
      for (final child in map.values) {
        if (child is List || child is Map) walk(child);
      }
    }

    walk(root);
    return out;
  }

  static String _date(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  static String _firstText(List<dynamic> values) {
    for (final value in values) {
      final text = _text(value);
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static String _text(dynamic value) {
    if (value == null || value is Map || value is List) return '';
    final text = '$value'.trim();
    return text == 'null' ? '' : text;
  }

  static String _normal(String value) => value
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _canonicalTeamName(String value) {
    var v = _normal(value);
    const aliases = <String, String>{
      'real madrid cf': 'real madrid',
      'real madrid': 'real madrid',
      'club atletico de madrid': 'atletico madrid',
      'atletico de madrid': 'atletico madrid',
      'atletico madrid': 'atletico madrid',
      'fc barcelona': 'barcelona',
      'barcelona': 'barcelona',
      'man city': 'manchester city',
      'manchester city fc': 'manchester city',
      'manchester city': 'manchester city',
      'man utd': 'manchester united',
      'manchester united fc': 'manchester united',
      'manchester united': 'manchester united',
      'paris saint germain fc': 'paris saint germain',
      'paris saint germain': 'paris saint germain',
      'psg': 'paris saint germain',
      'fc bayern munich': 'bayern munich',
      'bayern munchen': 'bayern munich',
      'bayern munich': 'bayern munich',
      'internazionale': 'inter milan',
      'inter': 'inter milan',
      'inter milan': 'inter milan',
      'ac milan': 'ac milan',
      'milan': 'ac milan',
      'olympique de marseille': 'marseille',
      'marseille': 'marseille',
      'borussia dortmund': 'borussia dortmund',
      'bvb': 'borussia dortmund',
      'malaga cf': 'malaga',
      'malaga': 'malaga',
    };
    if (aliases.containsKey(v)) return aliases[v]!;
    v = v
        .replaceAll(RegExp(r'\b(fc|cf|afc|sc|ssc)\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return aliases[v] ?? v;
  }

  static bool _sameTeam(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    return _similar(a, b) && a.split(' ').toSet().intersection(b.split(' ').toSet()).length >= 1;
  }

  static bool _similar(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b || a.contains(b) || b.contains(a)) return true;
    final aa = a.split(' ').where((e) => e.length > 2).toSet();
    final bb = b.split(' ').where((e) => e.length > 2).toSet();
    if (aa.isEmpty || bb.isEmpty) return false;
    final overlap = aa.intersection(bb).length;
    return overlap >= (aa.length < bb.length ? aa.length : bb.length) / 2;
  }
}

class _Broadcast {
  const _Broadcast(this.name, this.logo);
  final String name;
  final String logo;
}

class _CachedBroadcast {
  const _CachedBroadcast(this.broadcast, this.savedAt);
  final _Broadcast? broadcast;
  final DateTime savedAt;
}

class _CachedHero {
  const _CachedHero(this.data, this.savedAt);
  final SportsMatchHeroData data;
  final DateTime savedAt;
}
