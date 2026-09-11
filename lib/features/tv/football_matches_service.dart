import 'package:dio/dio.dart';

import 'football_match_models.dart';

/// Reads today's football fixtures from a public, keyless football feed.
///
/// The previous Drama Live endpoint guess (`app.dramalive.co/events`) is not a
/// valid JSON matches endpoint, which is why the UI showed
/// "تعذر تحميل مباريات اليوم".
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
            ),
        _logoDio = Dio(
          BaseOptions(
            baseUrl: 'https://api.sofascore.com/api/v1/',
            connectTimeout: const Duration(seconds: 7),
            receiveTimeout: const Duration(seconds: 9),
            responseType: ResponseType.json,
            headers: const {
              'Accept': 'application/json',
              'User-Agent':
                  'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1',
              'Referer': 'https://www.sofascore.com/',
            },
          ),
        ),
        _sportsDbDio = Dio(
          BaseOptions(
            baseUrl: 'https://www.thesportsdb.com/api/v1/json/123/',
            connectTimeout: const Duration(seconds: 7),
            receiveTimeout: const Duration(seconds: 9),
            responseType: ResponseType.json,
            headers: const {
              'Accept': 'application/json',
              'User-Agent': 'Cinematy/1.0',
            },
          ),
        );

  final Dio _dio;
  final Dio _logoDio;
  final Dio _sportsDbDio;

  String? _logoCacheDate;
  Map<String, String> _logoByTeam = const {};
  Map<String, String> _logoByLeague = const {};
  final Map<String, String> _sportsDbLogoCache = {};
  final Map<String, String> _sofaSearchLogoCache = {};

  Future<List<FootballMatch>> getTodayMatches() async {
    final now = DateTime.now();
    final date = _yyyyMmDd(now);

    final response = await _dio.get<dynamic>(
      'schedule',
      queryParameters: {'date': date},
    );

    final rows = _extractRows(response.data);
    var matches = rows
        .whereType<Map>()
        .map((row) => _parse(Map<String, dynamic>.from(row)))
        .whereType<FootballMatch>()
        .where(_isTodayOrUndated)
        .where(_isAllowedMatch)
        .toList(growable: false);

    // Matchora's public schedule feed does not consistently include team logos.
    // Enrich today's visible matches from Sofascore's team image ids. This is
    // best-effort only: if the enrichment endpoint is unavailable the
    // scoreboard still works with the existing fallback shield icon.
    final logos = await _todayTeamLogos(date);
    if (logos.isNotEmpty || _logoByLeague.isNotEmpty) {
      matches = matches
          .map((match) => _withResolvedLogos(match, logos, _logoByLeague))
          .toList(growable: false);
    }

    // Saudi league badges: resolve every still-missing RSL team from the SAME
    // Sofascore source. The daily scheduled-events endpoint may not expose a
    // matching spelling for every Saudi club, so use Sofascore universal search
    // as a second pass and keep the result cached for the whole session.
    matches = _fillSaudiLogosFromSplOfficial(matches);

    // Non-Saudi fallback only. RSL teams stay on the official SPL source.
    matches = await _fillMissingLogosFromSportsDb(matches);

    matches.sort((a, b) {
      if (a.isLive != b.isLive) return a.isLive ? -1 : 1;
      if (a.isFinished != b.isFinished) return a.isFinished ? 1 : -1;
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
    String two(int v) => v.toString().padLeft(2, '0');
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

    final score = _string(json['score']);
    final parsedScore = _parseScore(score);

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
          json['startsAt'],
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
          _scalarString(json['home_crest']) ??
          _scalarString(json['homeCrest']) ??
          _teamLogo(json['homeTeam']) ??
          _teamLogo(json['home_team']) ??
          _teamLogo(json['home']) ??
          '',
      awayLogo: _scalarString(json['away_logo']) ??
          _scalarString(json['awayLogo']) ??
          _scalarString(json['away_badge']) ??
          _scalarString(json['awayBadge']) ??
          _scalarString(json['away_crest']) ??
          _scalarString(json['awayCrest']) ??
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
      homeScore: homeScore,
      awayScore: awayScore,
      minute: minute,
      status: _status(rawStatus, live, minute, homeScore, awayScore),
      startsAt: startsAt,
    );
  }


  static bool _isAllowedMatch(FootballMatch match) {
    final value = _normalizeLeague(match.league);
    if (value.isEmpty) return false;

    // The five major European domestic leagues.
    if (value == 'premier league' ||
        value.contains('english premier league') ||
        value.contains('england premier league') ||
        value == 'la liga' ||
        value.contains('spanish la liga') ||
        value.contains('spain la liga') ||
        value == 'serie a' ||
        value.contains('italian serie a') ||
        value.contains('italy serie a') ||
        value == 'bundesliga' ||
        value.contains('german bundesliga') ||
        value.contains('germany bundesliga') ||
        value == 'ligue 1' ||
        value.contains('french ligue 1') ||
        value.contains('france ligue 1')) {
      return true;
    }

    // Saudi Pro League / Roshn Saudi League (RSL).
    // Match providers use several names for the same competition, so keep this
    // explicit rather than matching every competition containing "Saudi".
    if (value == 'rsl' ||
        value.contains('saudi pro league') ||
        value.contains('saudi professional league') ||
        value.contains('saudi arabia pro league') ||
        value.contains('saudi arabia - pro league') ||
        value.contains('saudi arabia professional league') ||
        value.contains('roshn saudi league') ||
        value.contains('roshn saudi pro league') ||
        value.contains('roshn league') ||
        value.contains('دوري روشن') ||
        value.contains('الدوري السعودي')) {
      return true;
    }

    // Iraqi Stars League (including older/common feed names).
    if (value.contains('iraq stars league') ||
        value.contains('iraqi stars league') ||
        value.contains('iraq premier league') ||
        value.contains('iraqi premier league') ||
        value.contains('دوري نجوم العراق') ||
        value.contains('الدوري العراقي')) {
      return true;
    }

    // Champions League competitions are region-aware. Do not treat every
    // competition containing "Champions League" as UEFA.
    if (value.contains('uefa champions league') ||
        value.contains('europe champions league') ||
        value.contains('european champions league') ||
        value.contains('دوري ابطال اوروبا') ||
        value.contains('دوري أبطال أوروبا')) {
      return true;
    }

    // CAF Champions League is intentionally excluded from the TV scoreboard.
    if (value.contains('caf champions league') ||
        value.contains('africa champions league') ||
        value.contains('african champions league') ||
        value.contains('دوري ابطال افريقيا') ||
        value.contains('دوري أبطال أفريقيا')) {
      return false;
    }

    // Inter Miami is the only MLS club allowed in the scoreboard.
    if (value.contains('major league soccer') ||
        value == 'mls' ||
        value.contains('usa mls') ||
        value.contains('us major league soccer')) {
      return _isInterMiami(match.homeName) || _isInterMiami(match.awayName);
    }

    // National-team football. Exclude the FIFA Club World Cup explicitly.
    if (value.contains('club world cup') ||
        value.contains('كاس العالم للاندية') ||
        value.contains('كأس العالم للأندية')) {
      return false;
    }

    // AFC Asian Cup and qualification.
    if (value.contains('afc asian cup') ||
        value == 'asian cup' ||
        value.contains('asian cup qualification') ||
        value.contains('asian cup qualifier') ||
        value.contains('كاس اسيا') ||
        value.contains('كأس آسيا')) {
      return true;
    }

    // Arabian Gulf Cup / Khaleeji Cup.
    if (value.contains('arabian gulf cup') ||
        value.contains('gulf cup') ||
        value.contains('khaleeji') ||
        value.contains('khaleeji cup') ||
        value.contains('كاس الخليج') ||
        value.contains('كأس الخليج') ||
        value.contains('خليجي')) {
      return true;
    }

    // Africa Cup of Nations / AFCON and qualification.
    if (value.contains('africa cup of nations') ||
        value.contains('african cup of nations') ||
        value.contains('afcon') ||
        value.contains('afcon qualification') ||
        value.contains('كاس امم افريقيا') ||
        value.contains('كأس أمم أفريقيا') ||
        value.contains('كأس الأمم الأفريقية')) {
      return true;
    }

    return value.contains('international friendly') ||
        value.contains('international friendlies') ||
        value.contains('friendly international') ||
        value == 'international' ||
        value.contains('fifa world cup') ||
        value.contains('world cup qualification') ||
        value.contains('world cup qualifier') ||
        value.contains('uefa nations league') ||
        value.contains('uefa euro') ||
        value.contains('european championship') ||
        value.contains('copa america') ||
        value.contains('concacaf nations league') ||
        value.contains('concacaf gold cup') ||
        value.contains('كاس العالم') ||
        value.contains('كأس العالم') ||
        value.contains('دوري الامم') ||
        value.contains('دوري الأمم') ||
        value.contains('مباراة ودية') ||
        value.contains('مباريات ودية');
  }

  static bool _isSaudiLeagueName(String league) {
    final value = _normalizeLeague(league);
    return value == 'rsl' ||
        value.contains('saudi pro league') ||
        value.contains('saudi professional league') ||
        value.contains('saudi arabia pro league') ||
        value.contains('saudi arabia - pro league') ||
        value.contains('saudi arabia professional league') ||
        value.contains('roshn saudi league') ||
        value.contains('roshn saudi pro league') ||
        value.contains('roshn league') ||
        value.contains('دوري روشن') ||
        value.contains('الدوري السعودي');
  }

  static bool _isInterMiami(String name) {
    final value = _normalizeTeamName(name);
    return value == 'inter miami' ||
        value == 'inter miami cf' ||
        value.contains('inter miami');
  }

  static String _normalizeLeague(String value) {
    return value
        .toLowerCase()
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<Map<String, String>> _todayTeamLogos(String date) async {
    if (_logoCacheDate == date && _logoByTeam.isNotEmpty) {
      return _logoByTeam;
    }

    try {
      final response = await _logoDio.get<dynamic>(
        'sport/football/scheduled-events/$date',
      );
      final root = response.data;
      if (root is! Map) return _logoByTeam;
      final events = root['events'];
      if (events is! List) return _logoByTeam;

      final result = <String, String>{};
      final leagueResult = <String, String>{};
      for (final raw in events) {
        if (raw is! Map) continue;
        _putTeamLogo(result, raw['homeTeam']);
        _putTeamLogo(result, raw['awayTeam']);
        _putLeagueLogo(leagueResult, raw);
      }

      if (result.isNotEmpty) {
        _logoByTeam = Map.unmodifiable(result);
      }
      if (leagueResult.isNotEmpty) {
        _logoByLeague = Map.unmodifiable(leagueResult);
      }
      if (result.isNotEmpty || leagueResult.isNotEmpty) {
        _logoCacheDate = date;
      }
    } catch (_) {
      // Logo enrichment must never break the scoreboard.
    }
    return _logoByTeam;
  }

  static void _putTeamLogo(Map<String, String> out, dynamic rawTeam) {
    if (rawTeam is! Map) return;
    final id = _int(rawTeam['id']);
    if (id == null) return;
    final logo = 'https://img.sofascore.com/api/v1/team/$id/image';

    for (final key in const ['name', 'shortName', 'code', 'slug']) {
      final name = _scalarString(rawTeam[key]);
      if (name == null) continue;
      final normalized = _normalizeTeamName(name);
      if (normalized.isNotEmpty) out[normalized] = logo;
    }
  }

  static void _putLeagueLogo(
    Map<String, String> out,
    Map event,
  ) {
    final tournament = event['tournament'];
    if (tournament is! Map) return;

    final unique = tournament['uniqueTournament'];
    final source = unique is Map ? unique : tournament;
    if (source is! Map) return;

    final id = _int(source['id']);
    if (id == null) return;

    final image = unique is Map
        ? 'https://img.sofascore.com/api/v1/unique-tournament/$id/image'
        : 'https://img.sofascore.com/api/v1/tournament/$id/image';

    for (final key in const ['name', 'slug']) {
      final name = _scalarString(source[key]);
      if (name == null) continue;
      final normalized = _normalizeLeague(name);
      if (normalized.isNotEmpty) out[normalized] = image;
    }

    // Some feeds expose a shorter parent tournament name than uniqueTournament.
    final parentName = _scalarString(tournament['name']);
    if (parentName != null) {
      final normalized = _normalizeLeague(parentName);
      if (normalized.isNotEmpty) out[normalized] = image;
    }
  }

  static String _resolveLeagueLogo(
    String leagueName,
    Map<String, String> logos,
  ) {
    final target = _normalizeLeague(leagueName);
    if (target.isEmpty) return '';
    final exact = logos[target];
    if (exact != null && exact.isNotEmpty) return exact;

    String? bestUrl;
    double bestScore = 0;
    final targetTokens = target.split(' ').where((e) => e.length > 2).toSet();
    for (final entry in logos.entries) {
      final candidate = entry.key;
      if (target.contains(candidate) || candidate.contains(target)) {
        return entry.value;
      }
      final candidateTokens = candidate.split(' ').where((e) => e.length > 2).toSet();
      if (targetTokens.isEmpty || candidateTokens.isEmpty) continue;
      final intersection = targetTokens.intersection(candidateTokens).length.toDouble();
      final union = targetTokens.union(candidateTokens).length.toDouble();
      final score = union == 0 ? 0.0 : intersection / union;
      if (score > bestScore) {
        bestScore = score;
        bestUrl = entry.value;
      }
    }
    return bestScore >= .5 ? (bestUrl ?? '') : '';
  }

  static FootballMatch _withResolvedLogos(
    FootballMatch match,
    Map<String, String> logos,
    Map<String, String> leagueLogos,
  ) {
    final homeLogo = match.homeLogo.isNotEmpty
        ? match.homeLogo
        : _resolveLogoByName(match.homeName, logos);
    final awayLogo = match.awayLogo.isNotEmpty
        ? match.awayLogo
        : _resolveLogoByName(match.awayName, logos);

    final leagueLogo = match.leagueLogo.isNotEmpty
        ? match.leagueLogo
        : _resolveLeagueLogo(match.league, leagueLogos);

    if (homeLogo == match.homeLogo &&
        awayLogo == match.awayLogo &&
        leagueLogo == match.leagueLogo) {
      return match;
    }

    return FootballMatch(
      id: match.id,
      homeName: match.homeName,
      awayName: match.awayName,
      homeLogo: homeLogo,
      awayLogo: awayLogo,
      league: match.league,
      leagueLogo: leagueLogo,
      homeScore: match.homeScore,
      awayScore: match.awayScore,
      minute: match.minute,
      status: match.status,
      startsAt: match.startsAt,
    );
  }


  static String _resolveLogoByName(
    String teamName,
    Map<String, String> logos,
  ) {
    final target = _normalizeTeamName(teamName);
    if (target.isEmpty) return '';

    final exact = logos[target];
    if (exact != null && exact.isNotEmpty) return exact;

    // Feeds often use slightly different team names ("Man United" vs
    // "Manchester United", "Inter" vs "Inter Milan", Arabic transliteration,
    // FC/SC suffixes, etc). Compare normalized tokens so the Sofascore team id
    // can still be resolved without making a separate request per team.
    final targetAliases = _teamAliases(target);
    String? bestUrl;
    double bestScore = 0;

    for (final entry in logos.entries) {
      final candidateAliases = _teamAliases(entry.key);
      for (final a in targetAliases) {
        for (final b in candidateAliases) {
          final score = _teamNameScore(a, b);
          if (score > bestScore) {
            bestScore = score;
            bestUrl = entry.value;
          }
        }
      }
    }

    // Keep the threshold conservative to avoid showing the wrong club badge.
    return bestScore >= .72 ? (bestUrl ?? '') : '';
  }

  static Set<String> _teamAliases(String normalized) {
    final out = <String>{normalized};

    const aliases = <String, List<String>>{
      'manchester united': ['man united', 'man utd'],
      'manchester city': ['man city'],
      'tottenham hotspur': ['tottenham', 'spurs'],
      'paris saint germain': ['psg', 'paris sg'],
      'inter milan': ['inter', 'internazionale'],
      'internazionale': ['inter', 'inter milan'],
      'ac milan': ['milan'],
      'atletico madrid': ['atl madrid', 'atletico'],
      'athletic bilbao': ['athletic club'],
      'bayern munich': ['bayern munchen', 'bayern'],
      'borussia dortmund': ['dortmund', 'bvb'],
      'rb leipzig': ['leipzig'],
      'al hilal': ['alhilal', 'الهلال'],
      'al nassr': ['alnassr', 'النصر'],
      'al ittihad': ['al ittihad jeddah', 'الاتحاد'],
      'al ahli': ['al ahli saudi', 'الاهلي', 'الأهلي'],
      'al shorta': ['الشرطة'],
      'al zawraa': ['الزوراء'],
      'al quwa al jawiya': ['air force club', 'القوة الجوية'],
      'iraq': ['العراق'],
      'saudi arabia': ['السعودية'],
      'england': ['انجلترا', 'إنجلترا'],
      'france': ['فرنسا'],
      'germany': ['المانيا', 'ألمانيا'],
      'spain': ['اسبانيا', 'إسبانيا'],
      'italy': ['ايطاليا', 'إيطاليا'],
      'argentina': ['الارجنتين', 'الأرجنتين'],
      'brazil': ['البرازيل'],
      'portugal': ['البرتغال'],
    };

    for (final entry in aliases.entries) {
      final canonical = _normalizeTeamName(entry.key);
      final values = entry.value.map(_normalizeTeamName).toList();
      if (normalized == canonical || values.contains(normalized)) {
        out.add(canonical);
        out.addAll(values);
      }
    }
    return out;
  }

  static double _teamNameScore(String a, String b) {
    if (a == b) return 1;
    if (a.isEmpty || b.isEmpty) return 0;
    if (a.contains(b) || b.contains(a)) {
      final shorter = a.length < b.length ? a.length : b.length;
      final longer = a.length > b.length ? a.length : b.length;
      if (shorter >= 4) return .86 + (.14 * shorter / longer);
    }

    final aTokens = a.split(' ').where((e) => e.length > 1).toSet();
    final bTokens = b.split(' ').where((e) => e.length > 1).toSet();
    if (aTokens.isEmpty || bTokens.isEmpty) return 0;
    final intersection = aTokens.intersection(bTokens).length.toDouble();
    final union = aTokens.union(bTokens).length.toDouble();
    final jaccard = union == 0 ? 0 : intersection / union;
    final coverage = intersection /
        (aTokens.length < bTokens.length ? aTokens.length : bTokens.length);
    return (jaccard * .55) + (coverage * .45);
  }

  static String _normalizeTeamName(String value) {
    var text = value.toLowerCase().trim();
    text = text
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r"[^a-z0-9\u0600-\u06ff]+"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Common feed prefixes/suffixes that otherwise prevent logo matching.
    for (final token in const [
      'fc ',
      'cf ',
      'sc ',
      'afc ',
    ]) {
      if (text.startsWith(token) && text.length > token.length + 2) {
        text = text.substring(token.length);
      }
    }
    for (final token in const [' fc', ' cf', ' sc']) {
      if (text.endsWith(token) && text.length > token.length + 2) {
        text = text.substring(0, text.length - token.length);
      }
    }
    return text.trim();
  }

  static const Map<String, String> _splOfficialClubLogos = {
    // Official Saudi Pro League CDN (2026-2027 season).
    'abha': 'https://media-sdp.spl.com.sa/clubLogos/b950674ec2cf4184a0dea482414ac915_light.webp',
    'أبها': 'https://media-sdp.spl.com.sa/clubLogos/b950674ec2cf4184a0dea482414ac915_light.webp',

    'al ahli': 'https://media-sdp.spl.com.sa/clubLogos/efdd3327b51d4fbd95b83d784301d411_light.webp',
    'al ahli saudi': 'https://media-sdp.spl.com.sa/clubLogos/efdd3327b51d4fbd95b83d784301d411_light.webp',
    'alahli': 'https://media-sdp.spl.com.sa/clubLogos/efdd3327b51d4fbd95b83d784301d411_light.webp',
    'الأهلي': 'https://media-sdp.spl.com.sa/clubLogos/efdd3327b51d4fbd95b83d784301d411_light.webp',
    'الاهلي': 'https://media-sdp.spl.com.sa/clubLogos/efdd3327b51d4fbd95b83d784301d411_light.webp',

    'al ettifaq': 'https://media-sdp.spl.com.sa/clubLogos/ab988d0ad28b419b96ab3cf2c49e0f6f_light.webp',
    'ettifaq': 'https://media-sdp.spl.com.sa/clubLogos/ab988d0ad28b419b96ab3cf2c49e0f6f_light.webp',
    'الاتفاق': 'https://media-sdp.spl.com.sa/clubLogos/ab988d0ad28b419b96ab3cf2c49e0f6f_light.webp',

    'al faisaly': 'https://media-sdp.spl.com.sa/clubLogos/874890145b9d43d59ec3f646e8bd4fee_light.webp',
    'alfaisaly': 'https://media-sdp.spl.com.sa/clubLogos/874890145b9d43d59ec3f646e8bd4fee_light.webp',
    'الفيصلي': 'https://media-sdp.spl.com.sa/clubLogos/874890145b9d43d59ec3f646e8bd4fee_light.webp',

    'al fateh': 'https://media-sdp.spl.com.sa/clubLogos/02f22b11aa604566a1858f96addb669c_light.webp',
    'alfateh': 'https://media-sdp.spl.com.sa/clubLogos/02f22b11aa604566a1858f96addb669c_light.webp',
    'الفتح': 'https://media-sdp.spl.com.sa/clubLogos/02f22b11aa604566a1858f96addb669c_light.webp',

    'al fayha': 'https://media-sdp.spl.com.sa/clubLogos/504ab03d43954464917361ed38f5cad2.webp',
    'al feiha': 'https://media-sdp.spl.com.sa/clubLogos/504ab03d43954464917361ed38f5cad2.webp',
    'alfayha': 'https://media-sdp.spl.com.sa/clubLogos/504ab03d43954464917361ed38f5cad2.webp',
    'الفيحاء': 'https://media-sdp.spl.com.sa/clubLogos/504ab03d43954464917361ed38f5cad2.webp',

    'al hazem': 'https://media-sdp.spl.com.sa/clubLogos/8a2bfb4eeaad41e9a84107e0a9c75744.webp',
    'al hazm': 'https://media-sdp.spl.com.sa/clubLogos/8a2bfb4eeaad41e9a84107e0a9c75744.webp',
    'alhazem': 'https://media-sdp.spl.com.sa/clubLogos/8a2bfb4eeaad41e9a84107e0a9c75744.webp',
    'الحزم': 'https://media-sdp.spl.com.sa/clubLogos/8a2bfb4eeaad41e9a84107e0a9c75744.webp',

    'al hilal': 'https://media-sdp.spl.com.sa/clubLogos/ae14a651fb584440979f8c4d02b89428_light.webp',
    'alhilal': 'https://media-sdp.spl.com.sa/clubLogos/ae14a651fb584440979f8c4d02b89428_light.webp',
    'الهلال': 'https://media-sdp.spl.com.sa/clubLogos/ae14a651fb584440979f8c4d02b89428_light.webp',

    'al ittihad': 'https://media-sdp.spl.com.sa/clubLogos/5c55f144687d497da1249c312392bb47.webp',
    'al ittihad jeddah': 'https://media-sdp.spl.com.sa/clubLogos/5c55f144687d497da1249c312392bb47.webp',
    'alittihad': 'https://media-sdp.spl.com.sa/clubLogos/5c55f144687d497da1249c312392bb47.webp',
    'الاتحاد': 'https://media-sdp.spl.com.sa/clubLogos/5c55f144687d497da1249c312392bb47.webp',

    'al khaleej': 'https://media-sdp.spl.com.sa/clubLogos/6bb24501d8c04b7e8cbd05fe89d8910f.webp',
    'alkhaleej': 'https://media-sdp.spl.com.sa/clubLogos/6bb24501d8c04b7e8cbd05fe89d8910f.webp',
    'الخليج': 'https://media-sdp.spl.com.sa/clubLogos/6bb24501d8c04b7e8cbd05fe89d8910f.webp',

    'al kholood': 'https://media-sdp.spl.com.sa/clubLogos/8f7c588e0292459f98d90969682dc2ae_light.webp',
    'alkholood': 'https://media-sdp.spl.com.sa/clubLogos/8f7c588e0292459f98d90969682dc2ae_light.webp',
    'الخلود': 'https://media-sdp.spl.com.sa/clubLogos/8f7c588e0292459f98d90969682dc2ae_light.webp',

    'al nassr': 'https://media-sdp.spl.com.sa/clubLogos/94263b19841944c38cb20892b176c862.webp',
    'alnasr': 'https://media-sdp.spl.com.sa/clubLogos/94263b19841944c38cb20892b176c862.webp',
    'alnassr': 'https://media-sdp.spl.com.sa/clubLogos/94263b19841944c38cb20892b176c862.webp',
    'النصر': 'https://media-sdp.spl.com.sa/clubLogos/94263b19841944c38cb20892b176c862.webp',

    'al qadsiah': 'https://media-sdp.spl.com.sa/clubLogos/dd29e62730be4d848e1be4c244fbfe5f_light.webp',
    'al qadisiyah': 'https://media-sdp.spl.com.sa/clubLogos/dd29e62730be4d848e1be4c244fbfe5f_light.webp',
    'al qadisiya': 'https://media-sdp.spl.com.sa/clubLogos/dd29e62730be4d848e1be4c244fbfe5f_light.webp',
    'القادسية': 'https://media-sdp.spl.com.sa/clubLogos/dd29e62730be4d848e1be4c244fbfe5f_light.webp',

    'al riyadh': 'https://media-sdp.spl.com.sa/clubLogos/2ba5364e60854fb8a7ca60903875e1ff_light.webp',
    'alriyadh': 'https://media-sdp.spl.com.sa/clubLogos/2ba5364e60854fb8a7ca60903875e1ff_light.webp',
    'الرياض': 'https://media-sdp.spl.com.sa/clubLogos/2ba5364e60854fb8a7ca60903875e1ff_light.webp',

    'al shabab': 'https://media-sdp.spl.com.sa/clubLogos/8169ad25b0754c44a49375717b3f9fb2.webp',
    'alshabab': 'https://media-sdp.spl.com.sa/clubLogos/8169ad25b0754c44a49375717b3f9fb2.webp',
    'الشباب': 'https://media-sdp.spl.com.sa/clubLogos/8169ad25b0754c44a49375717b3f9fb2.webp',

    'al taawoun': 'https://media-sdp.spl.com.sa/clubLogos/d234b1ebf80e481a888ce64cab2dcd89.webp',
    'al taawon': 'https://media-sdp.spl.com.sa/clubLogos/d234b1ebf80e481a888ce64cab2dcd89.webp',
    'altaawoun': 'https://media-sdp.spl.com.sa/clubLogos/d234b1ebf80e481a888ce64cab2dcd89.webp',
    'التعاون': 'https://media-sdp.spl.com.sa/clubLogos/d234b1ebf80e481a888ce64cab2dcd89.webp',

    'diriyah': 'https://media-sdp.spl.com.sa/clubLogos/1a2a221d20d34ffa8f41246ce61f2079_light.webp',
    'diriyah club': 'https://media-sdp.spl.com.sa/clubLogos/1a2a221d20d34ffa8f41246ce61f2079_light.webp',
    'al diriyah': 'https://media-sdp.spl.com.sa/clubLogos/1a2a221d20d34ffa8f41246ce61f2079_light.webp',
    'الدرعية': 'https://media-sdp.spl.com.sa/clubLogos/1a2a221d20d34ffa8f41246ce61f2079_light.webp',

    'neom': 'https://media-sdp.spl.com.sa/clubLogos/aaac358d37704691aadcfd92ebd53c7b_light.webp',
    'neom sc': 'https://media-sdp.spl.com.sa/clubLogos/aaac358d37704691aadcfd92ebd53c7b_light.webp',
    'نيوم': 'https://media-sdp.spl.com.sa/clubLogos/aaac358d37704691aadcfd92ebd53c7b_light.webp',
  };

  static String _resolveSplOfficialLogo(String teamName) {
    final key = _normalizeTeamName(teamName);
    final exact = _splOfficialClubLogos[key];
    if (exact != null) return exact;

    // Match small feed variations while keeping this restricted to the 18
    // official 2026-2027 RSL clubs above.
    for (final entry in _splOfficialClubLogos.entries) {
      final alias = _normalizeTeamName(entry.key);
      if (alias.length < 4) continue;
      if (key == alias || key.contains(alias) || alias.contains(key)) {
        return entry.value;
      }
    }
    return '';
  }

  List<FootballMatch> _fillSaudiLogosFromSplOfficial(
    List<FootballMatch> matches,
  ) {
    return matches.map((match) {
      if (!_isSaudiLeagueName(match.league)) return match;

      // For RSL, deliberately prefer the official SPL badge over any logo URL
      // supplied by Matchora/Sofascore so the whole league uses one source.
      final officialHome = _resolveSplOfficialLogo(match.homeName);
      final officialAway = _resolveSplOfficialLogo(match.awayName);
      final home = officialHome.isNotEmpty ? officialHome : match.homeLogo;
      final away = officialAway.isNotEmpty ? officialAway : match.awayLogo;

      if (home == match.homeLogo && away == match.awayLogo) return match;
      return FootballMatch(
        id: match.id,
        homeName: match.homeName,
        awayName: match.awayName,
        homeLogo: home,
        awayLogo: away,
        league: match.league,
        leagueLogo: match.leagueLogo,
        homeScore: match.homeScore,
        awayScore: match.awayScore,
        minute: match.minute,
        status: match.status,
        startsAt: match.startsAt,
      );
    }).toList(growable: false);
  }

  Future<List<FootballMatch>> _fillMissingLogosFromSportsDb(
    List<FootballMatch> matches,
  ) async {
    final missingNames = <String>{};
    for (final match in matches) {
      // Saudi league logos must come from Sofascore only.
      if (_isSaudiLeagueName(match.league)) continue;
      if (match.homeLogo.isEmpty) missingNames.add(match.homeName);
      if (match.awayLogo.isEmpty) missingNames.add(match.awayName);
    }
    if (missingNames.isEmpty) return matches;

    // Keep requests comfortably below the public API's per-minute allowance.
    final names = missingNames.take(24).toList(growable: false);
    await Future.wait(names.map(_fetchSportsDbBadge));

    return matches.map((match) {
      final home = match.homeLogo.isNotEmpty
          ? match.homeLogo
          : _sportsDbLogoCache[_normalizeTeamName(match.homeName)] ?? '';
      final away = match.awayLogo.isNotEmpty
          ? match.awayLogo
          : _sportsDbLogoCache[_normalizeTeamName(match.awayName)] ?? '';
      if (home == match.homeLogo && away == match.awayLogo) return match;
      return FootballMatch(
        id: match.id,
        homeName: match.homeName,
        awayName: match.awayName,
        homeLogo: home,
        awayLogo: away,
        league: match.league,
        leagueLogo: match.leagueLogo,
        homeScore: match.homeScore,
        awayScore: match.awayScore,
        minute: match.minute,
        status: match.status,
        startsAt: match.startsAt,
      );
    }).toList(growable: false);
  }

  Future<void> _fetchSportsDbBadge(String teamName) async {
    final cacheKey = _normalizeTeamName(teamName);
    if (cacheKey.isEmpty || _sportsDbLogoCache.containsKey(cacheKey)) return;

    // Mark as attempted first so simultaneous home/away aliases do not duplicate
    // the same request during a refresh.
    _sportsDbLogoCache[cacheKey] = '';
    try {
      final response = await _sportsDbDio.get<dynamic>(
        'searchteams.php',
        queryParameters: {'t': teamName},
      );
      final root = response.data;
      if (root is! Map || root['teams'] is! List) return;
      final teams = (root['teams'] as List).whereType<Map>().toList();
      if (teams.isEmpty) return;

      Map? best;
      double bestScore = 0;
      for (final team in teams) {
        final sport = _scalarString(team['strSport'])?.toLowerCase() ?? '';
        if (sport.isNotEmpty && sport != 'soccer' && sport != 'football') continue;
        final candidate = _scalarString(team['strTeam']);
        if (candidate == null) continue;
        final score = _teamNameScore(
          _normalizeTeamName(teamName),
          _normalizeTeamName(candidate),
        );
        if (score > bestScore) {
          bestScore = score;
          best = team;
        }
      }

      // The free endpoint normally returns one team. A modest threshold still
      // protects against unrelated clubs with similar short names.
      if (best == null || bestScore < .58) return;
      final badge = _scalarString(
        best['strBadge'] ?? best['strTeamBadge'] ?? best['strLogo'],
      );
      if (badge != null && badge.startsWith('http')) {
        _sportsDbLogoCache[cacheKey] = badge;
      }
    } catch (_) {
      // Badge lookup is visual enrichment only.
    }
  }

  static (int, int)? _parseScore(String? value) {
    if (value == null) return null;
    final m = RegExp(r'(\d+)\s*[-:]\s*(\d+)').firstMatch(value);
    if (m == null) return null;
    final a = int.tryParse(m.group(1)!);
    final b = int.tryParse(m.group(2)!);
    if (a == null || b == null) return null;
    return (a, b);
  }

  static DateTime? _parseKickoff(dynamic value) {
    if (value is num) {
      final n = value.toInt();
      final ms = n < 100000000000 ? n * 1000 : n;
      return DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    }

    final text = _string(value);
    if (text == null) return null;

    final numeric = int.tryParse(text);
    if (numeric != null && numeric > 1000000000) {
      final ms = numeric < 100000000000 ? numeric * 1000 : numeric;
      return DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    }

    return DateTime.tryParse(text)?.toLocal();
  }

  static FootballMatchStatus _status(
    String raw,
    bool live,
    int? minute,
    int? home,
    int? away,
  ) {
    final s = raw.toLowerCase();

    if (live ||
        s == '1h' ||
        s == '2h' ||
        s == 'ht' ||
        s.contains('live') ||
        s.contains('progress') ||
        s.contains('half') ||
        s.contains('مباشر')) {
      return FootballMatchStatus.live;
    }

    if (s == 'ft' ||
        s.contains('finish') ||
        s.contains('ended') ||
        s.contains('انته')) {
      return FootballMatchStatus.finished;
    }

    if (s.contains('postpon') || s.contains('cancel') || s.contains('تأجل')) {
      return FootballMatchStatus.postponed;
    }

    if (minute != null && minute > 0) {
      return FootballMatchStatus.live;
    }

    if (s.contains('schedule') ||
        s.contains('upcoming') ||
        s.contains('not started') ||
        s.contains('ns')) {
      return FootballMatchStatus.scheduled;
    }

    if (home != null && away != null) {
      return FootballMatchStatus.live;
    }

    return FootballMatchStatus.scheduled;
  }

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
            value['image_url'] ??
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
        final uniqueName = _scalarString(unique['name'] ?? unique['title']);
        if (uniqueName != null) return uniqueName;
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
    return int.tryParse(RegExp(r'\d+').firstMatch(text)?.group(0) ?? '');
  }

  static bool _isTodayOrUndated(FootballMatch match) {
    final date = match.startsAt;
    if (date == null) return true;
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }
}
