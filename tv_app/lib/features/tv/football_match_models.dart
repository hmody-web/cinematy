class FootballMatch {
  const FootballMatch({
    required this.id,
    required this.homeName,
    required this.awayName,
    this.homeLogo = '',
    this.awayLogo = '',
    this.league = '',
    this.leagueLogo = '',
    this.homeScore,
    this.awayScore,
    this.minute,
    this.status = FootballMatchStatus.scheduled,
    this.startsAt,
  });

  final String id;
  final String homeName;
  final String awayName;
  final String homeLogo;
  final String awayLogo;
  final String league;
  final String leagueLogo;
  final int? homeScore;
  final int? awayScore;
  final int? minute;
  final FootballMatchStatus status;
  final DateTime? startsAt;

  bool get isLive => status == FootballMatchStatus.live;
  bool get isFinished => status == FootballMatchStatus.finished;
}

enum FootballMatchStatus { scheduled, live, finished, postponed, unknown }
