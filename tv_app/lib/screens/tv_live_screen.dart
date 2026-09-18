import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/tv/bein_channel_resolver.dart';
import '../features/tv/football_match_models.dart';
import '../features/tv/football_matches_service.dart';
import '../features/tv/sports_match_hero_service.dart';
import '../features/tv/tv_models.dart';
import '../features/tv/xtream_tv_service.dart';
import '../tv_context.dart';
import '../tv_focus.dart';
import '../tv_image.dart';
import '../tv_nav.dart';
import '../tv_platform_ui.dart';
import '../tv_theme.dart';
import 'tv_live_player_screen.dart';

class TvLiveScreen extends StatefulWidget {
  const TvLiveScreen({super.key});

  @override
  State<TvLiveScreen> createState() => _TvLiveScreenState();
}

class _TvLiveScreenState extends State<TvLiveScreen> {
  final XtreamTvService _service = XtreamTvService();
  final FootballMatchesService _matchesService = FootballMatchesService();
  final SportsMatchHeroService _heroService = SportsMatchHeroService();

  List<TvCategory> _allCategories = const [];
  List<TvChannel> _channels = const [];
  List<TvChannel> _allChannels = const [];
  String? _selectedId;
  bool _loading = true;
  String? _error;

  final PageController _heroPageController = PageController();
  final ScrollController _pageScrollController = ScrollController();
  List<SportsMatchHeroData> _heroes = const [];
  final Set<String> _heroEnriching = <String>{};
  final Set<String> _heroEnriched = <String>{};
  int _heroIndex = 0;
  bool _heroLoading = true;
  Timer? _heroRefreshTimer;
  Timer? _heroEnrichDelay;
  Timer? _heroAutoPageTimer;
  Timer? _heroRevealTimer;
  bool _heroAutoForward = true;

  @override
  void initState() {
    super.initState();
    tvDisplayPreferences.addListener(_onDisplayPreferencesChanged);
    _load();

    // When the user hides the scoreboard, do not spend API/network work
    // preparing hero artwork in the background.
    if (!tvDisplayPreferences.hideScoreboard) {
      _loadHero();
      _startHeroRefreshTimer();
    } else {
      _heroLoading = false;
    }
  }

  Duration get _heroRefreshInterval => tvDisplayPreferences.lowEndLiveOptimization
      ? const Duration(minutes: 15)
      : const Duration(minutes: 5);

  void _startHeroRefreshTimer() {
    _heroRefreshTimer?.cancel();
    if (tvDisplayPreferences.hideScoreboard) {
      _heroRefreshTimer = null;
      return;
    }
    _heroRefreshTimer = Timer.periodic(
      _heroRefreshInterval,
      (_) => _loadHero(silent: true),
    );
  }

  void _onDisplayPreferencesChanged() {
    if (!mounted) return;
    if (tvDisplayPreferences.hideScoreboard) {
      _heroRefreshTimer?.cancel();
      _heroRefreshTimer = null;
      _heroEnrichDelay?.cancel();
      _heroAutoPageTimer?.cancel();
      _heroAutoPageTimer = null;
      _heroRevealTimer?.cancel();
      if (_heroLoading) setState(() => _heroLoading = false);
      return;
    }

    // Rebuild cache widths & other lightweight UI choices immediately.
    setState(() {});
    _startHeroRefreshTimer();
    _scheduleHeroAutoAdvance();
    if (_heroes.isEmpty && !_heroLoading) {
      unawaited(_loadHero());
    }
  }

  @override
  void dispose() {
    tvDisplayPreferences.removeListener(_onDisplayPreferencesChanged);
    _heroRefreshTimer?.cancel();
    _heroEnrichDelay?.cancel();
    _heroAutoPageTimer?.cancel();
    _heroRevealTimer?.cancel();
    _heroPageController.dispose();
    _pageScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHero({bool silent = false}) async {
    if (!silent && mounted) setState(() => _heroLoading = true);
    try {
      final matches = await _matchesService.getNext24HourMatches();
      if (!mounted) return;

      final hasRealInWindow = matches.any((match) {
        final home = _normalizeClubName(match.homeName);
        final away = _normalizeClubName(match.awayName);
        return _isRealMadrid(home) || _isRealMadrid(away);
      });
      final hasBarcaInWindow = matches.any((match) {
        final home = _normalizeClubName(match.homeName);
        final away = _normalizeClubName(match.awayName);
        return _isBarcelona(home) || _isBarcelona(away);
      });

      final featuredFuture = await _matchesService.getNextFeaturedClubMatches(
        needRealMadrid: !hasRealInWindow,
        needBarcelona: !hasBarcaInWindow,
      );
      if (!mounted) return;

      final byId = <String, FootballMatch>{
        for (final match in matches) match.id: match,
        for (final match in featuredFuture) match.id: match,
      };

      // Real Madrid and Barcelona stay at the front. When they have no match
      // in the rolling 24-hour window, their next scheduled fixture is added.
      final orderedMatches = byId.values.toList(growable: false)..sort(_compareHeroMatches);

      final previousById = <String, SportsMatchHeroData>{
        for (final item in _heroes) item.match.id: item,
      };
      final nextHeroes = orderedMatches
          .map(
            (match) => previousById[match.id]?.withMatch(match) ??
                SportsMatchHeroData(
                  match: match,
                  homeBadge: match.homeLogo,
                  awayBadge: match.awayLogo,
                  leagueBadge: match.leagueLogo,
                ),
          )
          .toList(growable: false);

      var nextIndex = _heroIndex;
      if (nextHeroes.isEmpty) {
        nextIndex = 0;
      } else if (nextIndex >= nextHeroes.length) {
        nextIndex = nextHeroes.length - 1;
      }

      setState(() {
        _heroes = nextHeroes;
        _heroIndex = nextIndex;
        _heroLoading = false;
      });

      if (nextHeroes.isNotEmpty) {
        // Artwork stays cached, but broadcaster data is time-sensitive. Allow
        // the currently visible hero to refresh on the 5-minute schedule.
        if (silent) {
          _heroEnriched.remove(nextHeroes[nextIndex].match.id);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_heroPageController.hasClients) return;
          if (_heroPageController.page?.round() != nextIndex) {
            _heroPageController.jumpToPage(nextIndex);
          }
        });
        _scheduleHeroEnrich(nextIndex);
        _scheduleHeroAutoAdvance();
      } else {
        _heroAutoPageTimer?.cancel();
        _heroAutoPageTimer = null;
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _heroLoading = false);
    }
  }

  int _compareHeroMatches(FootballMatch a, FootballMatch b) {
    final featuredA = _featuredClubPriority(a);
    final featuredB = _featuredClubPriority(b);
    if (featuredA != featuredB) return featuredB.compareTo(featuredA);

    // Inside the same priority tier, live matches come first, then the nearest
    // kickoff. This keeps the carousel useful without losing the marquee-club
    // preference requested for Real Madrid and Barcelona.
    if (a.isLive != b.isLive) return a.isLive ? -1 : 1;
    final aTime = a.startsAt ?? DateTime(9999, 12, 31);
    final bTime = b.startsAt ?? DateTime(9999, 12, 31);
    return aTime.compareTo(bTime);
  }

  int _featuredClubPriority(FootballMatch match) {
    final home = _normalizeClubName(match.homeName);
    final away = _normalizeClubName(match.awayName);
    final hasReal = _isRealMadrid(home) || _isRealMadrid(away);
    final hasBarca = _isBarcelona(home) || _isBarcelona(away);
    if (hasReal && hasBarca) return 3; // El Clásico always first.
    if (hasReal || hasBarca) return 2;
    return 0;
  }

  String _normalizeClubName(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  bool _isRealMadrid(String value) =>
      value.contains('real madrid') || value.contains('ريال مدريد');

  bool _isBarcelona(String value) =>
      value.contains('barcelona') ||
      value.contains('fc barcelona') ||
      value.contains('برشلونة');

  void _scheduleHeroEnrich(int index) {
    _heroEnrichDelay?.cancel();
    _heroEnrichDelay = Timer(
      const Duration(milliseconds: 220),
      () => _enrichHeroAt(index),
    );
  }

  Future<void> _enrichHeroAt(int index) async {
    if (index < 0 || index >= _heroes.length) return;
    final match = _heroes[index].match;
    if (_heroEnriched.contains(match.id) || _heroEnriching.contains(match.id)) {
      return;
    }

    _heroEnriching.add(match.id);
    try {
      final enriched = await _heroService.enrich(match);
      if (!mounted) return;
      final currentIndex = _heroes.indexWhere((item) => item.match.id == match.id);
      if (currentIndex < 0) return;
      final updated = [..._heroes];
      updated[currentIndex] = enriched;
      setState(() => _heroes = updated);
      _heroEnriched.add(match.id);
    } catch (_) {
      // Keep the base scoreboard visible even when artwork enrichment fails.
    } finally {
      _heroEnriching.remove(match.id);
    }
  }

  void _onHeroPageChanged(int index) {
    if (_heroIndex != index) {
      setState(() => _heroIndex = index);
    }
    _scheduleHeroEnrich(index);
    _scheduleHeroAutoAdvance();
  }

  int _nextHeroIndex() {
    if (_heroes.length <= 1) return _heroIndex;
    if (_heroIndex >= _heroes.length - 1) {
      _heroAutoForward = false;
    } else if (_heroIndex <= 0) {
      _heroAutoForward = true;
    }
    return (_heroIndex + (_heroAutoForward ? 1 : -1))
        .clamp(0, _heroes.length - 1)
        .toInt();
  }

  void _scheduleHeroAutoAdvance() {
    _heroAutoPageTimer?.cancel();
    _heroAutoPageTimer = null;
    if (!mounted ||
        tvDisplayPreferences.hideScoreboard ||
        _heroes.length <= 1) {
      return;
    }

    // Enrich the next card during the 10-second dwell, never while the
    // scoreboard itself is moving.
    final warmIndex = _nextHeroIndex();
    if (warmIndex != _heroIndex) {
      unawaited(_enrichHeroAt(warmIndex));
    }

    _heroAutoPageTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted ||
          tvDisplayPreferences.hideScoreboard ||
          _heroes.length <= 1 ||
          !_heroPageController.hasClients) {
        return;
      }
      _advanceHeroAutomatically();
    });
  }

  void _advanceHeroAutomatically() {
    if (_heroes.length <= 1 || !_heroPageController.hasClients) return;

    final next = _nextHeroIndex();
    if (next == _heroIndex) {
      _scheduleHeroAutoAdvance();
      return;
    }

    _heroPageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
    );
  }

  void _moveHero(int delta) {
    if (_heroes.length <= 1 || !_heroPageController.hasClients) return;
    _heroAutoPageTimer?.cancel();
    _heroAutoPageTimer = null;
    final next = _heroIndex + delta;
    if (next < 0 || next >= _heroes.length) {
      _scheduleHeroAutoAdvance();
      return;
    }
    _heroAutoForward = delta > 0;
    _heroPageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeInOutCubic,
    );
  }

  void _revealHeroFully() {
    _heroRevealTimer?.cancel();
    _heroRevealTimer = Timer(const Duration(milliseconds: 70), () {
      if (!mounted || !_pageScrollController.hasClients) return;
      final position = _pageScrollController.position;
      if (position.pixels <= 1.0) return;
      _pageScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 620),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  Future<void> _moveHeroToChannels(double heroHeight) async {
    if (!_pageScrollController.hasClients) return;

    final position = _pageScrollController.position;
    final target = heroHeight.clamp(0.0, position.maxScrollExtent).toDouble();
    if ((position.pixels - target).abs() < 1.0) return;

    await _pageScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeInOutCubic,
    );
  }

  bool _isIntro(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'intro' || normalized.contains(' intro ');
  }

  bool _isBein(String value) {
    final normalized = value.toLowerCase().replaceAll(' ', '');
    return normalized.contains('bein') ||
        value.contains('بين سبورت') ||
        value.contains('بي إن');
  }

  static const List<_QualitySection> _qualitySections = <_QualitySection>[
    _QualitySection('__all__', 'الكل'),
    _QualitySection('4k', '4K'),
    _QualitySection('hevc', 'HEVC'),
    _QualitySection('fhd', 'FHD'),
    _QualitySection('hd', 'HD'),
    _QualitySection('sd', 'SD'),
  ];

  String _channelQualityKey(TvChannel channel) {
    final categoryName = _allCategories
        .where((category) => category.id == channel.categoryId)
        .map((category) => category.name)
        .cast<String?>()
        .firstWhere((_) => true, orElse: () => null);
    final value = '${channel.name} ${categoryName ?? ''}'.toLowerCase();

    // Dedicated 4K section, separate from HEVC.
    if (value.contains('4k') ||
        value.contains('uhd') ||
        value.contains('2160')) {
      return '4k';
    }
    if (value.contains('hevc') || value.contains('h265')) {
      return 'hevc';
    }
    if (value.contains('fhd') || value.contains('1080')) return 'fhd';
    if (value.contains('720') ||
        RegExp(r'(^|[^a-z])hd([^a-z]|$)').hasMatch(value)) {
      return 'hd';
    }
    if (value.contains('sd') || value.contains('480')) return 'sd';

    // Streams without an explicit marker stay visible in All only.
    return 'other';
  }

  List<TvChannel> _channelsForSection(String sectionId) {
    final source = _allChannels.where((channel) {
      if (_isIntro(channel.name)) return false;
      final category = _allCategories
          .where((item) => item.id == channel.categoryId)
          .map((item) => item.name)
          .cast<String?>()
          .firstWhere((_) => true, orElse: () => null);
      return category == null || !_isIntro(category);
    });
    if (sectionId == '__all__') return source.toList(growable: false);
    return source
        .where((channel) => _channelQualityKey(channel) == sectionId)
        .toList(growable: false);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.getCategories(),
        _service.getChannels(),
      ]);
      _allCategories = (results[0] as List<TvCategory>)
          .where((category) => !_isIntro(category.name))
          .toList(growable: false);
      _allChannels = (results[1] as List<TvChannel>)
          .where((channel) => !_isIntro(channel.name))
          .toList(growable: false);
      await _selectFirstCategory();
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل القنوات';
      });
    }
  }

  Future<void> _selectFirstCategory() async {
    await _selectQuality(_qualitySections.first, force: true);
  }

  Future<void> _selectQuality(_QualitySection section, {bool force = false}) async {
    if (!force && _selectedId == section.id) return;
    setState(() {
      _selectedId = section.id;
      _loading = true;
    });
    try {
      final channels = _channelsForSection(section.id);
      if (!mounted) return;
      setState(() {
        _channels = channels;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _channels = const [];
        _loading = false;
      });
    }
  }

  List<_ChannelGroup> get _groups {
    final map = <String, List<TvChannel>>{};
    for (final channel in _channels) {
      final key = channel.groupKey.isEmpty ? '${channel.id}' : channel.groupKey;
      map.putIfAbsent(key, () => <TvChannel>[]).add(channel);
    }
    final groups = map.entries
        .map((entry) => _ChannelGroup(entry.key, entry.value))
        .toList(growable: false)
      ..sort((a, b) {
        // IMPORTANT: sort by the REAL stream names inside the group, not
        // by the cleaned display title. This keeps Qatar beIN 1..9 pinned
        // first in "الكل" and in every quality section independently.
        final aPriority = _qatariBeinGroupPriority(a);
        final bPriority = _qatariBeinGroupPriority(b);

        if (aPriority != null && bPriority != null) {
          final order = aPriority.compareTo(bPriority);
          if (order != 0) return order;
        } else if (aPriority != null) {
          return -1;
        } else if (bPriority != null) {
          return 1;
        }

        return _normalizeChannelName(a.title)
            .compareTo(_normalizeChannelName(b.title));
      });
    return groups;
  }

  int _channelOrder(String value) {
    final priority = _qatariBeinPriority(value);
    if (priority != null) return priority;

    // Anything that is not one of the exact Qatar beIN 1..9 variants
    // comes strictly after the complete priority block. This prevents
    // beIN France / USA / Australia / etc. from appearing between them.
    return 10000;
  }

  int? _qatariBeinGroupPriority(_ChannelGroup group) {
    int? best;
    for (final channel in group.channels) {
      final priority = _qatariBeinPriority(channel.name);
      if (priority != null && (best == null || priority < best)) {
        best = priority;
      }
    }
    return best;
  }

  int? _qatariBeinPriority(String value) {
    final normalized = _normalizeChannelName(value);

    // The actual Qatar family in this playlist starts with:
    // -beIN SPORT 1 ... -beIN SPORT 9
    // and carries an isolated variant marker such as (N), (G), or (F).
    final numberMatch = RegExp(
      r'^\s*[-•|:]*\s*bein\s*sports?\s*[-_: ]*([1-9])(?:\D|$)',
      caseSensitive: false,
    ).firstMatch(normalized);

    if (numberMatch == null) return null;

    final number = int.tryParse(numberMatch.group(1) ?? '');
    if (number == null) return null;

    final variant = _qatariBeinVariant(normalized);
    if (variant == null) return null;

    // Keep every channel number together in exact 1 -> 9 order.
    // Within each number: N first, then G, then F.
    final variantRank = switch (variant) {
      'n' => 0,
      'g' => 1,
      'f' => 2,
      _ => 9,
    };

    return (number * 10) + variantRank;
  }

  String? _qatariBeinVariant(String value) {
    // Only accept an isolated N/G/F marker, e.g.:
    // (N), [G], - F, "_N". Do not mistake the F in FHD for variant F.
    final match = RegExp(
      r'(?:^|[\s\(\[\{_\-])([ngf])(?:$|[\s\)\]\}_\-])',
      caseSensitive: false,
    ).firstMatch(value);

    return match?.group(1)?.toLowerCase();
  }

  String _normalizeChannelName(String value) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const western = '0123456789';

    var result = value.toLowerCase();
    for (var i = 0; i < 10; i++) {
      result = result
          .replaceAll(eastern[i], western[i])
          .replaceAll(persian[i], western[i]);
    }
    return result
        .replaceAll('إ', 'ا')
        .replaceAll('أ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  TvChannel _smoothVariantFor(List<TvChannel> variants) {
    if (variants.length <= 1) return variants.first;
    int score(TvChannel channel) {
      final name = channel.name.toLowerCase();
      var value = 0;
      if (name.contains('4k') || name.contains('uhd') || name.contains('2160')) value += 120;
      if (name.contains('hevc') || name.contains('h265')) value += 70;
      if (name.contains('fhd') || name.contains('1080')) value += 45;
      if (name.contains('60fps') || name.contains('50fps')) value += 30;
      if (name.contains('720') || (name.contains('hd') && !name.contains('fhd'))) value -= 20;
      if (name.contains('h264') || name.contains('avc')) value -= 12;
      return value;
    }
    final ordered = [...variants]..sort((a, b) => score(a).compareTo(score(b)));
    return ordered.first;
  }

  int _qualityRank(String value) {
    final name = value.toLowerCase();
    if (name.contains('sd') || name.contains('480')) return 10;
    if ((name.contains('hd') && !name.contains('fhd')) || name.contains('720')) return 20;
    if (name.contains('fhd') || name.contains('1080')) return 30;
    if (name.contains('4k') || name.contains('uhd') || name.contains('2160')) return 40;
    if (name.contains('hevc') || name.contains('h265')) return 50;
    return 35;
  }

  String _qualityLabel(String value) {
    final name = value.toLowerCase();
    if (name.contains('hevc') || name.contains('h265')) return 'HEVC';
    if (name.contains('4k') || name.contains('uhd') || name.contains('2160')) return '4K';
    if (name.contains('fhd') || name.contains('1080')) return 'FHD';
    if ((name.contains('hd') && !name.contains('fhd')) || name.contains('720')) return 'HD';
    if (name.contains('sd') || name.contains('480')) return 'SD';
    return 'نسخة';
  }

  Future<void> _openGroup(_ChannelGroup group) async {
    final allVariants = _allChannels
        .where((channel) => channel.groupKey == group.key && !_isIntro(channel.name))
        .toList(growable: false);
    final variants = allVariants.isEmpty ? group.channels : allVariants;
    final orderedVariants = [...variants]..sort((a, b) => _qualityRank(a.name).compareTo(_qualityRank(b.name)));

    if (orderedVariants.length == 1) {
      unawaited(_play(orderedVariants.first));
      return;
    }

    final picked = await showDialog<TvChannel>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF151515),
        title: Text(group.title, textAlign: TextAlign.right),
        content: SizedBox(
          width: 520,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: orderedVariants.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final channel = orderedVariants[index];
              return Row(
                textDirection: TextDirection.rtl,
                children: [
                  Expanded(
                    child: TvFocus(
                      autofocus: index == 0,
                      onPressed: () => Navigator.pop(dialogContext, channel),
                      child: Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(.05),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          textDirection: TextDirection.rtl,
                          children: [
                            Expanded(
                              child: Text(
                                channel.name,
                                textAlign: TextAlign.right,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: TvColors.red.withOpacity(.14),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _qualityLabel(channel.name),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  TvFocus(
                    onPressed: () async {
                      await tvChannelFavorites.toggle(channel);
                      if (mounted) setState(() {});
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Icon(
                        tvChannelFavorites.contains(channel)
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: tvChannelFavorites.contains(channel)
                            ? TvColors.red
                            : Colors.white54,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    if (picked != null) unawaited(_play(picked));
  }

  Future<void> _play(TvChannel tapped) async {
    final variants = _allChannels
        .where((channel) => channel.groupKey == tapped.groupKey && !_isIntro(channel.name))
        .toList(growable: false);
    final playback = tapped;
    final playlist = _groups.map((g) => _smoothVariantFor(g.channels)).toList(growable: false);
    final index = playlist.indexWhere((channel) => channel.groupKey == playback.groupKey);

    final lowEndMode = tvDisplayPreferences.lowEndLiveOptimization;
    if (lowEndMode) {
      // While a live channel is playing, stop artwork/API work behind the
      // player. This leaves CPU, RAM and network scheduling to the video.
      _heroRefreshTimer?.cancel();
      _heroRefreshTimer = null;
      _heroEnrichDelay?.cancel();
    }

    await Navigator.of(context).push(
      tvVideoRoute(
        TvLivePlayerScreen(
          channel: playback,
          url: _service.streamUrl(playback),
          channels: playlist,
          initialIndex: index < 0 ? 0 : index,
        ),
      ),
    );

    if (!mounted) return;
    if (lowEndMode && !tvDisplayPreferences.hideScoreboard) {
      // Resume the normal section refresh only after leaving playback.
      _startHeroRefreshTimer();
    }
  }

  Future<void> _watchHero(SportsMatchHeroData data) async {
    final broadcast = data.broadcastName.trim();
    TvChannel? channel;

    if (broadcast.isNotEmpty) {
      channel = _bestBroadcastMatch(_channels, broadcast, categories: _allCategories);
      if (channel == null) {
        final seenCategoryIds = <String>{};
        final categories = <TvCategory>[
          ..._allCategories,
        ].where((category) => seenCategoryIds.add(category.id)).toList(growable: false);
        if (BeinChannelResolver.isBeinLabel(broadcast)) {
          categories.sort((a, b) {
            final aBein = BeinChannelResolver.isBeinLabel(a.name);
            final bBein = BeinChannelResolver.isBeinLabel(b.name);
            if (aBein != bBein) return aBein ? -1 : 1;
            return 0;
          });
        }

        for (final category in categories) {
          try {
            final rows = await _service.getChannels(categoryId: category.id);
            channel = _bestBroadcastMatch(rows, broadcast, categories: <TvCategory>[category]);
            if (channel != null) break;
          } catch (_) {
            // Continue with the next category.
          }
        }
      }
    }

    if (!mounted) return;
    if (channel != null) {
      await _play(channel);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          broadcast.isEmpty
              ? 'لم تُعلن القناة الناقلة لهذه المباراة بعد.'
              : 'القناة الناقلة: $broadcast — لم أجد قناة مطابقة ضمن مصادر التلفاز الحالية.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  TvChannel? _bestBroadcastMatch(
    List<TvChannel> channels,
    String broadcast, {
    List<TvCategory> categories = const <TvCategory>[],
  }) {
    if (channels.isEmpty || broadcast.trim().isEmpty) return null;

    // Resolve against the actual Xtream rows loaded from the current source.
    // Category-aware matching handles providers where the category is named
    // beIN Sports but individual streams are only named "6", "6 FHD", etc.
    final broadcastIsBein = BeinChannelResolver.isBeinLabel(broadcast);
    final realBein = BeinChannelResolver.resolve(
      channels: channels,
      categories: categories,
      broadcast: broadcast,
      preferredVariant: tvDisplayPreferences.lowEndLiveOptimization ? 'F' : 'N',
    );
    if (realBein != null) return realBein;

    // A beIN match must stay inside the beIN family. Do not let generic
    // name/number matching select another network just because it also has 6.
    if (broadcastIsBein) return null;

    final target = _channelIdentity(broadcast);
    final targetNumber = RegExp(r'(\d{1,2})').firstMatch(target)?.group(1);
    TvChannel? best;
    var bestScore = 0;

    for (final channel in channels) {
      final candidate = _channelIdentity(channel.name);
      if (candidate.isEmpty) continue;
      var score = 0;
      if (candidate == target) score = 100;
      if (candidate.contains(target) || target.contains(candidate)) score = 82;

      final targetTokens = target.split(' ').where((e) => e.length > 1).toSet();
      final candidateTokens = candidate.split(' ').where((e) => e.length > 1).toSet();
      score += targetTokens.intersection(candidateTokens).length * 12;

      final candidateNumber = RegExp(r'(\d{1,2})').firstMatch(candidate)?.group(1);
      if (targetNumber != null && candidateNumber != null) {
        score += targetNumber == candidateNumber ? 30 : -45;
      }
      if (score > bestScore) {
        bestScore = score;
        best = channel;
      }
    }
    return bestScore >= 44 ? best : null;
  }

  bool _isBeinChannel(String value) {
    final id = _channelIdentity(value).replaceAll(' ', '');
    return id.contains('bein') || id.contains('beinsports');
  }

  String? _beinChannelNumber(String value) {
    if (!_isBeinChannel(value)) return null;
    final match = RegExp(r'(\d{1,2})').firstMatch(_channelIdentity(value));
    return match?.group(1);
  }

  String _channelIdentity(String value) {
    var prepared = value
        .replaceAll('إ', 'ا')
        .replaceAll('أ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي');
    prepared = normalizeTvChannelName(prepared);
    return prepared
        .replaceAll('mena', ' ')
        .replaceAll('qatar', ' ')
        .replaceAll('arabic', ' ')
        .replaceAll('english', ' ')
        .replaceAll('middle east', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: tvChannelFavorites,
      builder: (context, _) {
        final categories = _qualitySections;
        final favorites = tvChannelFavorites.items;
        final groups = _groups;

        return LayoutBuilder(
          builder: (context, constraints) {
            final heroHeight = constraints.maxHeight.clamp(460.0, 980.0).toDouble();
            return CustomScrollView(
              controller: _pageScrollController,
              cacheExtent: 900,
              slivers: [
                if (!tvDisplayPreferences.hideScoreboard &&
                    (_heroLoading || _heroes.isNotEmpty))
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: heroHeight,
                      child: _heroLoading && _heroes.isEmpty
                          ? const _HeroLoading()
                          : _MatchHeroPager(
                              items: _heroes,
                              controller: _heroPageController,
                              currentIndex: _heroIndex,
                              onPageChanged: _onHeroPageChanged,
                              onMove: _moveHero,
                              onMoveDown: () => _moveHeroToChannels(heroHeight),
                              onHeroControlFocused: _revealHeroFully,
                              onWatch: _watchHero,
                            ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
                    child: Row(
                      textDirection: TextDirection.rtl,
                      children: [
                        const Expanded(
                          child: Text(
                            'البث المباشر',
                            textAlign: TextAlign.right,
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (favorites.isNotEmpty)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: tvIsWindowsDesktop ? 96 : 82,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 7),
                        scrollDirection: Axis.horizontal,
                        itemCount: favorites.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final channel = favorites[index];
                          return SizedBox(
                            width: tvIsWindowsDesktop ? 280 : 235,
                            child: TvFocus(
                              onPressed: () => unawaited(_play(channel)),
                              child: Container(
                                padding: const EdgeInsets.all(9),
                                decoration: BoxDecoration(
                                  color: TvColors.red.withOpacity(.10),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  textDirection: TextDirection.rtl,
                                  children: [
                                    SizedBox(
                                      width: tvIsWindowsDesktop ? 56 : 46,
                                      height: tvIsWindowsDesktop ? 56 : 46,
                                      child: TvImage(
                                          channel.icon,
                                          cacheWidth: tvDisplayPreferences.lowEndLiveOptimization ? 64 : 100,
                                          borderRadius: 8,
                                        ),
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Text(
                                        channel.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                    const Icon(Icons.favorite_rounded, size: 17, color: TvColors.red),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                if (categories.isNotEmpty)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: tvIsWindowsDesktop ? 70 : 60,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 5),
                        itemCount: categories.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 9),
                        itemBuilder: (context, index) {
                          final category = categories[index];
                          final selected = _selectedId == category.id;
                          return TvFocus(
                            onPressed: () => _selectQuality(category),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                              decoration: BoxDecoration(
                                color: selected ? TvColors.red : Colors.white.withOpacity(.07),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                category.name,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                if (_loading)
                  const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
                if (_error != null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text(_error!)),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 30),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: tvIsWindowsDesktop ? 360 : 310,
                        mainAxisExtent: tvIsWindowsDesktop ? 205 : 174,
                        crossAxisSpacing: tvIsWindowsDesktop ? 20 : 16,
                        mainAxisSpacing: tvIsWindowsDesktop ? 20 : 16,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final group = groups[index];
                          final channel = _smoothVariantFor(group.channels);
                          return TvFocus(
                            onPressed: () => _openGroup(group),
                            child: Container(
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(.045),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: tvIsWindowsDesktop ? 98 : 80,
                                    height: tvIsWindowsDesktop ? 98 : 80,
                                    child: TvImage(
                                      channel.icon,
                                      cacheWidth: tvDisplayPreferences.lowEndLiveOptimization ? 112 : 180,
                                      borderRadius: 10,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    group.title,
                                    maxLines: 2,
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                                  ),
                                  if (group.channels.length > 1)
                                    Text(
                                      '${group.channels.length} مصادر',
                                      style: const TextStyle(fontSize: 10, color: Colors.white38),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                        childCount: groups.length,
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _MatchHeroPager extends StatefulWidget {
  const _MatchHeroPager({
    required this.items,
    required this.controller,
    required this.currentIndex,
    required this.onPageChanged,
    required this.onMove,
    required this.onMoveDown,
    required this.onHeroControlFocused,
    required this.onWatch,
  });

  final List<SportsMatchHeroData> items;
  final PageController controller;
  final int currentIndex;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onMove;
  final Future<void> Function() onMoveDown;
  final VoidCallback onHeroControlFocused;
  final ValueChanged<SportsMatchHeroData> onWatch;

  @override
  State<_MatchHeroPager> createState() => _MatchHeroPagerState();
}

class _MatchHeroPagerState extends State<_MatchHeroPager> {
  final FocusNode _leftArrowFocusNode = FocusNode(debugLabel: 'hero_left_arrow');
  final FocusNode _rightArrowFocusNode = FocusNode(debugLabel: 'hero_right_arrow');
  final Map<String, FocusNode> _watchFocusNodes = <String, FocusNode>{};

  FocusNode _watchNodeFor(SportsMatchHeroData data) {
    return _watchFocusNodes.putIfAbsent(
      data.match.id,
      () => FocusNode(debugLabel: 'hero_watch_${data.match.id}'),
    );
  }

  FocusNode? get _currentWatchNode {
    if (widget.currentIndex < 0 || widget.currentIndex >= widget.items.length) {
      return null;
    }
    final data = widget.items[widget.currentIndex];
    if (!data.match.isLive) return null;
    return _watchNodeFor(data);
  }

  void _focusWatchIfAvailable() {
    final node = _currentWatchNode;
    if (node == null || !node.canRequestFocus) return;
    node.requestFocus();
    widget.onHeroControlFocused();
  }

  void _focusLeftControlOrMove() {
    final hasLeftControl = widget.items.length > 1 &&
        widget.currentIndex < widget.items.length - 1;
    if (hasLeftControl && _leftArrowFocusNode.canRequestFocus) {
      _leftArrowFocusNode.requestFocus();
      widget.onHeroControlFocused();
      return;
    }
    widget.onMove(1);
  }

  void _focusRightControlOrMove() {
    final hasRightControl = widget.items.length > 1 && widget.currentIndex > 0;
    if (hasRightControl && _rightArrowFocusNode.canRequestFocus) {
      _rightArrowFocusNode.requestFocus();
      widget.onHeroControlFocused();
      return;
    }
    widget.onMove(-1);
  }

  @override
  void didUpdateWidget(covariant _MatchHeroPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    final validIds = widget.items.map((e) => e.match.id).toSet();
    final stale = _watchFocusNodes.keys.where((id) => !validIds.contains(id)).toList();
    for (final id in stale) {
      _watchFocusNodes.remove(id)?.dispose();
    }
  }

  @override
  void dispose() {
    _leftArrowFocusNode.dispose();
    _rightArrowFocusNode.dispose();
    for (final node in _watchFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final currentIndex = widget.currentIndex;
    if (items.isEmpty) return const SizedBox.shrink();

    final currentHasWatch = currentIndex >= 0 &&
        currentIndex < items.length &&
        items[currentIndex].match.isLive;

    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          widget.onMove(1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          widget.onMove(-1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          widget.onMoveDown().whenComplete(() {
            if (!context.mounted) return;
            FocusScope.of(context).focusInDirection(TraversalDirection.down);
          });
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: widget.controller,
            itemCount: items.length,
            onPageChanged: widget.onPageChanged,
            allowImplicitScrolling: true,
            physics: const PageScrollPhysics(),
            itemBuilder: (context, index) {
              final data = items[index];
              final isCurrent = index == currentIndex;
              // The hero is visually heavy (large transparent players, club
              // gradients and logos). Isolate each page and let PageView move
              // a cached layer instead of repainting opacity/scale effects on
              // every animation frame.
              return RepaintBoundary(
                child: _MatchHero(
                  data: data,
                  autofocusWatch: isCurrent && data.match.isLive,
                  watchFocusNode: isCurrent && data.match.isLive
                      ? _watchNodeFor(data)
                      : null,
                  onFocused: widget.onHeroControlFocused,
                  // When "شاهد الآن" exists, horizontal navigation from it
                  // lands on the visual arrow controls. From an arrow, moving
                  // back toward the centre returns focus to "شاهد الآن".
                  onArrowLeft: isCurrent && data.match.isLive
                      ? _focusLeftControlOrMove
                      : () => widget.onMove(1),
                  onArrowRight: isCurrent && data.match.isLive
                      ? _focusRightControlOrMove
                      : () => widget.onMove(-1),
                  onWatch: data.match.isLive ? () => widget.onWatch(data) : null,
                ),
              );
            },
          ),
          if (items.length > 1 && currentIndex > 0)
            Positioned(
              right: 22,
              top: 0,
              bottom: 0,
              child: Center(
                child: TvFocus(
                  focusNode: _rightArrowFocusNode,
                  onFocused: widget.onHeroControlFocused,
                  // Left is toward the centre of the hero. If the live-match
                  // button exists, select it instead of skipping over it.
                  onArrowLeft: currentHasWatch ? _focusWatchIfAvailable : null,
                  onPressed: () => widget.onMove(-1),
                  child: _HeroArrow(icon: Icons.chevron_right_rounded),
                ),
              ),
            ),
          if (items.length > 1 && currentIndex < items.length - 1)
            Positioned(
              left: 22,
              top: 0,
              bottom: 0,
              child: Center(
                child: TvFocus(
                  focusNode: _leftArrowFocusNode,
                  onFocused: widget.onHeroControlFocused,
                  // Right is toward the centre of the hero.
                  onArrowRight: currentHasWatch ? _focusWatchIfAvailable : null,
                  onPressed: () => widget.onMove(1),
                  child: _HeroArrow(icon: Icons.chevron_left_rounded),
                ),
              ),
            ),
          if (items.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 64,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(.34),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withOpacity(.09)),
                    ),
                    child: Text(
                      '${currentIndex + 1} / ${items.length}',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontSize: tvIsWindowsDesktop ? 13 : 12,
                        fontWeight: FontWeight.w900,
                        color: Colors.white.withOpacity(.78),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HeroArrow extends StatelessWidget {
  const _HeroArrow({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tvIsWindowsDesktop ? 54 : 48,
      height: tvIsWindowsDesktop ? 54 : 48,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.34),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.24),
            blurRadius: 18,
            spreadRadius: -6,
          ),
        ],
      ),
      child: Icon(
        icon,
        size: tvIsWindowsDesktop ? 36 : 32,
        textDirection: TextDirection.ltr,
      ),
    );
  }
}


class _MatchHero extends StatelessWidget {
  const _MatchHero({
    required this.data,
    required this.onWatch,
    required this.onArrowLeft,
    required this.onArrowRight,
    required this.onFocused,
    this.autofocusWatch = false,
    this.watchFocusNode,
  });

  final SportsMatchHeroData data;
  final VoidCallback? onWatch;
  final VoidCallback onArrowLeft;
  final VoidCallback onArrowRight;
  final VoidCallback onFocused;
  final bool autofocusWatch;
  final FocusNode? watchFocusNode;

  static const Map<String, String> _leagueArabic = <String, String>{
    'uefa champions league': 'دوري أبطال أوروبا',
    'champions league': 'دوري أبطال أوروبا',
    'english premier league': 'الدوري الإنجليزي الممتاز',
    'premier league': 'الدوري الإنجليزي الممتاز',
    'la liga': 'الدوري الإسباني',
    'spanish la liga': 'الدوري الإسباني',
    'serie a': 'الدوري الإيطالي',
    'italian serie a': 'الدوري الإيطالي',
    'bundesliga': 'الدوري الألماني',
    'german bundesliga': 'الدوري الألماني',
    'ligue 1': 'الدوري الفرنسي',
    'french ligue 1': 'الدوري الفرنسي',
  };

  static const Map<String, String> _teamArabic = <String, String>{
    // Spain
    'real madrid': 'ريال مدريد',
    'real madrid cf': 'ريال مدريد',
    'barcelona': 'برشلونة',
    'fc barcelona': 'برشلونة',
    'atletico madrid': 'أتلتيكو مدريد',
    'atletico de madrid': 'أتلتيكو مدريد',
    'athletic club': 'أتلتيك بلباو',
    'athletic bilbao': 'أتلتيك بلباو',
    'real betis': 'ريال بيتيس',
    'getafe': 'خيتافي',
    'getafe cf': 'خيتافي',
    'real sociedad': 'ريال سوسيداد',
    'villarreal': 'فياريال',
    'villarreal cf': 'فياريال',
    'sevilla': 'إشبيلية',
    'sevilla fc': 'إشبيلية',
    'valencia': 'فالنسيا',
    'valencia cf': 'فالنسيا',
    'celta vigo': 'سيلتا فيغو',
    'celta de vigo': 'سيلتا فيغو',
    'osasuna': 'أوساسونا',
    'ca osasuna': 'أوساسونا',
    'mallorca': 'ريال مايوركا',
    'rcd mallorca': 'ريال مايوركا',
    'girona': 'جيرونا',
    'girona fc': 'جيرونا',
    'rayo vallecano': 'رايو فايكانو',
    'espanyol': 'إسبانيول',
    'rcd espanyol': 'إسبانيول',
    'alaves': 'ديبورتيفو ألافيس',
    'deportivo alaves': 'ديبورتيفو ألافيس',
    'levante': 'ليفانتي',
    'elche': 'إلتشي',
    'las palmas': 'لاس بالماس',
    'real oviedo': 'ريال أوفييدو',
    'malaga': 'مالقة',
    'malaga cf': 'مالقة',

    // England
    'arsenal': 'أرسنال',
    'arsenal fc': 'أرسنال',
    'manchester city': 'مانشستر سيتي',
    'man city': 'مانشستر سيتي',
    'manchester united': 'مانشستر يونايتد',
    'man united': 'مانشستر يونايتد',
    'liverpool': 'ليفربول',
    'chelsea': 'تشيلسي',
    'tottenham hotspur': 'توتنهام هوتسبير',
    'tottenham': 'توتنهام هوتسبير',
    'newcastle united': 'نيوكاسل يونايتد',
    'aston villa': 'أستون فيلا',
    'crystal palace': 'كريستال بالاس',
    'brighton': 'برايتون',
    'brighton and hove albion': 'برايتون',
    'west ham united': 'وست هام يونايتد',
    'west ham': 'وست هام يونايتد',
    'everton': 'إيفرتون',
    'fulham': 'فولهام',
    'brentford': 'برينتفورد',
    'bournemouth': 'بورنموث',
    'afc bournemouth': 'بورنموث',
    'wolverhampton wanderers': 'وولفرهامبتون',
    'wolves': 'وولفرهامبتون',
    'nottingham forest': 'نوتنغهام فورست',
    'leeds united': 'ليدز يونايتد',
    'leicester city': 'ليستر سيتي',
    'southampton': 'ساوثهامبتون',
    'burnley': 'بيرنلي',
    'sunderland': 'سندرلاند',
    'ipswich town': 'إيبسويتش تاون',

    // Italy
    'juventus': 'يوفنتوس',
    'inter': 'إنتر ميلان',
    'inter milan': 'إنتر ميلان',
    'internazionale': 'إنتر ميلان',
    'ac milan': 'ميلان',
    'milan': 'ميلان',
    'napoli': 'نابولي',
    'roma': 'روما',
    'as roma': 'روما',
    'lazio': 'لاتسيو',
    'atalanta': 'أتالانتا',
    'fiorentina': 'فيورنتينا',
    'bologna': 'بولونيا',
    'torino': 'تورينو',
    'udinese': 'أودينيزي',
    'genoa': 'جنوى',
    'como': 'كومو',
    'parma': 'بارما',
    'lecce': 'ليتشي',
    'cagliari': 'كالياري',
    'hellas verona': 'هيلاس فيرونا',
    'verona': 'هيلاس فيرونا',
    'sassuolo': 'ساسولو',
    'cremonese': 'كريمونيزي',
    'pisa': 'بيزا',
    'monza': 'مونزا',
    'empoli': 'إمبولي',

    // Germany
    'bayern munich': 'بايرن ميونخ',
    'fc bayern munich': 'بايرن ميونخ',
    'bayern munchen': 'بايرن ميونخ',
    'borussia dortmund': 'بوروسيا دورتموند',
    'bayer leverkusen': 'باير ليفركوزن',
    'rb leipzig': 'لايبزيغ',
    'rbl': 'لايبزيغ',
    'eintracht frankfurt': 'آينتراخت فرانكفورت',
    'vfb stuttgart': 'شتوتغارت',
    'stuttgart': 'شتوتغارت',
    'sc freiburg': 'فرايبورغ',
    'freiburg': 'فرايبورغ',
    'hoffenheim': 'هوفنهايم',
    'tsg hoffenheim': 'هوفنهايم',
    'wolfsburg': 'فولفسبورغ',
    'vfl wolfsburg': 'فولفسبورغ',
    'werder bremen': 'فيردر بريمن',
    'augsburg': 'أوغسبورغ',
    'fc augsburg': 'أوغسبورغ',
    'mainz': 'ماينز',
    'mainz 05': 'ماينز',
    'borussia monchengladbach': 'بوروسيا مونشنغلادباخ',
    'monchengladbach': 'بوروسيا مونشنغلادباخ',
    'union berlin': 'يونيون برلين',
    'st pauli': 'سانت باولي',
    'hamburg': 'هامبورغ',
    'hamburger sv': 'هامبورغ',
    'koln': 'كولن',
    'cologne': 'كولن',
    'heidenheim': 'هايدنهايم',

    // France
    'paris saint germain': 'باريس سان جيرمان',
    'paris saint-germain': 'باريس سان جيرمان',
    'psg': 'باريس سان جيرمان',
    'marseille': 'مارسيليا',
    'olympique marseille': 'مارسيليا',
    'monaco': 'موناكو',
    'as monaco': 'موناكو',
    'lyon': 'ليون',
    'olympique lyonnais': 'ليون',
    'lille': 'ليل',
    'losc lille': 'ليل',
    'nice': 'نيس',
    'ogc nice': 'نيس',
    'rennes': 'رين',
    'stade rennais': 'رين',
    'strasbourg': 'ستراسبورغ',
    'lens': 'لانس',
    'rc lens': 'لانس',
    'brest': 'بريست',
    'nantes': 'نانت',
    'toulouse': 'تولوز',
    'auxerre': 'أوكسير',
    'angers': 'أنجيه',
    'le havre': 'لوهافر',
    'metz': 'ميتز',
    'lorient': 'لوريان',
    'paris fc': 'باريس إف سي',

    // Common UEFA Champions League clubs outside the big five
    'benfica': 'بنفيكا',
    'sl benfica': 'بنفيكا',
    'sporting cp': 'سبورتينغ لشبونة',
    'sporting lisbon': 'سبورتينغ لشبونة',
    'porto': 'بورتو',
    'fc porto': 'بورتو',
    'ajax': 'أياكس',
    'psv': 'بي إس في آيندهوفن',
    'psv eindhoven': 'بي إس في آيندهوفن',
    'feyenoord': 'فينورد',
    'celtic': 'سلتيك',
    'rangers': 'رينجرز',
    'galatasaray': 'غلطة سراي',
    'fenerbahce': 'فنربخشة',
    'besiktas': 'بشكتاش',
    'club brugge': 'كلوب بروج',
    'anderlecht': 'أندرلخت',
    'olympiacos': 'أولمبياكوس',
    'olympiakos': 'أولمبياكوس',
    'panathinaikos': 'باناثينايكوس',
    'shakhtar donetsk': 'شاختار دونيتسك',
    'dynamo kyiv': 'دينامو كييف',
    'red star belgrade': 'النجم الأحمر بلغراد',
    'crvena zvezda': 'النجم الأحمر بلغراد',
    'red bull salzburg': 'ريد بول سالزبورغ',
    'salzburg': 'سالزبورغ',
    'sparta prague': 'سبارتا براغ',
    'slavia prague': 'سلافيا براغ',
    'viktoria plzen': 'فيكتوريا بلزن',
    'dinamo zagreb': 'دينامو زغرب',
    'young boys': 'يونغ بويز',
    'fc copenhagen': 'كوبنهاغن',
    'copenhagen': 'كوبنهاغن',
    'bodo glimt': 'بودو غليمت',
    'bodo/glimt': 'بودو غليمت',
    'malmo': 'مالمو',
    'qarabag': 'قره باغ',
    'maccabi tel aviv': 'مكابي تل أبيب',
    'slovan bratislava': 'سلوفان براتيسلافا',
    'sturm graz': 'شتورم غراتس',
  };

  static const Map<String, String> _venueArabic = <String, String>{
    'santiago bernabeu': 'سانتياغو برنابيو',
    'estadio santiago bernabeu': 'سانتياغو برنابيو',
    'spotify camp nou': 'سبوتيفاي كامب نو',
    'camp nou': 'كامب نو',
    'estadi olimpic lluis companys': 'الملعب الأولمبي لويس كومبانيس',
    'metropolitano': 'ميتروبوليتانو',
    'civitas metropolitano': 'ميتروبوليتانو',
    'benito villamarin': 'بينيتو فيامارين',
    'coliseum': 'كوليسيوم',
    'reale arena': 'ريالي أرينا',
    'anoeta': 'أنويتا',
    'estadio de la ceramica': 'ملعب لا سيراميكا',
    'san mames': 'سان ماميس',
    'mestalla': 'ميستايا',
    'ramon sanchez pizjuan': 'رامون سانشيز بيزخوان',
    'old trafford': 'أولد ترافورد',
    'etihad stadium': 'ملعب الاتحاد',
    'emirates stadium': 'ملعب الإمارات',
    'anfield': 'أنفيلد',
    'stamford bridge': 'ستامفورد بريدج',
    'tottenham hotspur stadium': 'ملعب توتنهام هوتسبير',
    'selhurst park': 'سيلهرست بارك',
    'villa park': 'فيلا بارك',
    'st james park': 'سانت جيمس بارك',
    'goodison park': 'غوديسون بارك',
    'hill dickinson stadium': 'ملعب هيل ديكنسون',
    'allianz arena': 'أليانز أرينا',
    'signal iduna park': 'سيغنال إيدونا بارك',
    'bayarena': 'باي أرينا',
    'red bull arena': 'ريد بول أرينا',
    'deutsche bank park': 'دويتشه بنك بارك',
    'mhparena': 'إم إتش بي أرينا',
    'san siro': 'سان سيرو',
    'giuseppe meazza': 'جوزيبي مياتزا',
    'allianz stadium': 'أليانز ستاديوم',
    'stadio diego armando maradona': 'ملعب دييغو أرماندو مارادونا',
    'stadio olimpico': 'الملعب الأولمبي',
    'gewiss stadium': 'ملعب جيويس',
    'stadio renato dall ara': 'ملعب ريناتو دال آرا',
    'parc des princes': 'بارك دي برانس',
    'stade velodrome': 'ملعب فيلودروم',
    'orange velodrome': 'أورانج فيلودروم',
    'groupama stadium': 'ملعب غروباما',
    'stade louis ii': 'ملعب لويس الثاني',
    'estadio da luz': 'ملعب دا لوز',
    'estadio jose alvalade': 'ملعب جوزيه ألفالادي',
    'estadio do dragao': 'ملعب الدراغاو',
    'johan cruyff arena': 'يوهان كرويف أرينا',
    'philips stadion': 'ملعب فيليبس',
    'de kuip': 'دي كويب',
    'celtic park': 'سلتيك بارك',
    'ibrox stadium': 'ملعب آيبروكس',
  };

  String _normalizeArabicKey(String value) => value
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String _arabicLeagueName(String value) {
    final key = _normalizeArabicKey(value);
    for (final entry in _leagueArabic.entries) {
      if (key == entry.key || key.contains(entry.key)) return entry.value;
    }
    return value.isEmpty ? 'كرة القدم' : value;
  }

  String _arabicTeamName(String value) {
    final key = _normalizeArabicKey(value);
    final exact = _teamArabic[key];
    if (exact != null) return exact;

    // Handle provider suffixes such as "FC", "CF" and "AFC" without making
    // the visible club name noisy.
    final stripped = key
        .replaceAll(RegExp(r'\b(fc|cf|afc|sc|ac)\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final strippedMatch = _teamArabic[stripped];
    if (strippedMatch != null) return strippedMatch;
    return value;
  }

  String _arabicVenueName(String value) {
    if (value.trim().isEmpty) return '';
    final key = _normalizeArabicKey(value);
    final exact = _venueArabic[key];
    if (exact != null) return exact;
    return value
        .replaceAll(RegExp(r'\bStadium\b', caseSensitive: false), 'ملعب')
        .replaceAll(RegExp(r'\bStade\b', caseSensitive: false), 'ملعب')
        .replaceAll(RegExp(r'\bStadio\b', caseSensitive: false), 'ملعب')
        .replaceAll(RegExp(r'\bEstadio\b', caseSensitive: false), 'ملعب')
        .replaceAll(RegExp(r'\bArena\b', caseSensitive: false), 'أرينا');
  }

  bool _isBeinBroadcast(String value) {
    final compact = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return compact.contains('bein') || value.contains('بين') || value.contains('بي إن');
  }

  String _arabicBroadcastName(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return '';
    if (_isBeinBroadcast(raw)) {
      final number = RegExp(r'\b(\d{1,2})\b').firstMatch(raw)?.group(1);
      final premium = raw.toLowerCase().contains('premium');
      return 'بي إن سبورتس${premium ? ' بريميوم' : ''}${number == null ? '' : ' $number'}';
    }

    final lower = raw.toLowerCase();
    if (lower.contains('sky sports')) return 'سكاي سبورتس';
    if (lower.contains('tnt sports')) return 'تي إن تي سبورتس';
    if (lower.contains('premier sports')) return 'بريمير سبورتس';
    if (lower.contains('dazn')) return 'دازن';
    if (lower.contains('espn')) return 'إي إس بي إن';
    if (lower.contains('canal')) return 'كانال بلس';
    if (lower.contains('paramount')) return 'باراماونت بلس';
    if (lower.contains('amazon')) return 'أمازون برايم';
    if (lower.contains('ssc')) {
      final number = RegExp(r'\b(\d{1,2})\b').firstMatch(raw)?.group(1);
      return 'إس إس سي${number == null ? '' : ' $number'}';
    }
    return raw;
  }

  String _formatArabicClock(DateTime value) {
    final hour24 = value.hour;
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = hour24 < 12 ? 'صباحًا' : 'مساءً';
    return '$hour12:$minute $period';
  }

  String _arabicWeekday(DateTime value) {
    const days = <int, String>{
      DateTime.monday: 'الاثنين',
      DateTime.tuesday: 'الثلاثاء',
      DateTime.wednesday: 'الأربعاء',
      DateTime.thursday: 'الخميس',
      DateTime.friday: 'الجمعة',
      DateTime.saturday: 'السبت',
      DateTime.sunday: 'الأحد',
    };
    return days[value.weekday] ?? '';
  }

  String _arabicDate(DateTime value) {
    const months = <int, String>{
      1: 'يناير', 2: 'فبراير', 3: 'مارس', 4: 'أبريل',
      5: 'مايو', 6: 'يونيو', 7: 'يوليو', 8: 'أغسطس',
      9: 'سبتمبر', 10: 'أكتوبر', 11: 'نوفمبر', 12: 'ديسمبر',
    };
    return '${value.day} ${months[value.month] ?? value.month}';
  }

  bool _isToday(DateTime value) {
    final now = DateTime.now();
    return now.year == value.year && now.month == value.month && now.day == value.day;
  }

  Color _teamColor(String value, Color fallback) {
    var text = value.trim().replaceAll('#', '');
    if (text.length == 6) text = 'FF$text';
    final parsed = int.tryParse(text, radix: 16);
    return parsed == null ? fallback : Color(parsed);
  }

  String _timeLabel(BuildContext context) {
    final match = data.match;
    if (match.isLive) {
      final minute = match.minute;
      return minute == null ? 'مباشر الآن' : 'مباشر الآن • الدقيقة $minute';
    }
    if (match.status == FootballMatchStatus.postponed) return 'المباراة مؤجلة';
    final start = match.startsAt;
    if (start == null) return 'موعد المباراة سيُعلن قريبًا';
    if (!_isToday(start)) {
      return '${_arabicWeekday(start)}، ${_arabicDate(start)} • ${_formatArabicClock(start)}';
    }
    return 'تبدأ المباراة الساعة ${_formatArabicClock(start)}';
  }

  @override
  Widget build(BuildContext context) {
    final match = data.match;
    final size = MediaQuery.sizeOf(context);
    final homeColor = _teamColor(data.homeColour, const Color(0xFF135B2E));
    final awayColor = _teamColor(data.awayColour, const Color(0xFF173F9C));
    final showScore = match.isLive && match.homeScore != null && match.awayScore != null;
    final heroWidth = size.width;
    final heroHeight = size.height;

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF030304)),
          // Stronger cinematic club-colour backdrop.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  awayColor.withOpacity(.95),
                  awayColor.withOpacity(.42),
                  Colors.black.withOpacity(.20),
                  homeColor.withOpacity(.42),
                  homeColor.withOpacity(.95),
                ],
                stops: const [0.0, .22, .50, .78, 1.0],
              ),
            ),
          ),
          // Dark cinematic vignette for contrast.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -.08),
                  radius: .95,
                  colors: [
                    Colors.black.withOpacity(.03),
                    Colors.black.withOpacity(.40),
                    Colors.black.withOpacity(.88),
                  ],
                  stops: const [.06, .55, 1],
                ),
              ),
            ),
          ),
          // Massive faint club badges as stylish background texture.
          Positioned(
            left: -heroWidth * .03,
            top: heroHeight * .10,
            width: heroWidth * .36,
            height: heroHeight * .54,
            child: _HeroBackdropBadge(url: data.awayBadge, tint: awayColor),
          ),
          Positioned(
            right: -heroWidth * .03,
            top: heroHeight * .10,
            width: heroWidth * .36,
            height: heroHeight * .54,
            child: _HeroBackdropBadge(url: data.homeBadge, tint: homeColor),
          ),
          // Left / right player renders much larger.
          Positioned(
            left: -heroWidth * .015,
            bottom: -heroHeight * .015,
            width: heroWidth * .39,
            height: heroHeight * .96,
            child: _HeroPlayerImage(
              url: data.awayPlayer,
              fallback: data.awayBadge,
              alignment: Alignment.bottomLeft,
              tint: awayColor,
            ),
          ),
          Positioned(
            right: -heroWidth * .015,
            bottom: -heroHeight * .015,
            width: heroWidth * .39,
            height: heroHeight * .96,
            child: _HeroPlayerImage(
              url: data.homePlayer,
              fallback: data.homeBadge,
              alignment: Alignment.bottomRight,
              tint: homeColor,
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: tvIsWindowsDesktop ? 64 : 36,
                vertical: tvIsWindowsDesktop ? 28 : 22,
              ),
              child: Column(
                children: [
                  const Spacer(flex: 1),
                  if (data.leagueBadge.isNotEmpty)
                    Image.network(
                      data.leagueBadge,
                      height: tvIsWindowsDesktop ? 78 : 62,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  const SizedBox(height: 10),
                  Text(
                    _arabicLeagueName(match.league),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: tvIsWindowsDesktop ? 18 : 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withOpacity(.78),
                      shadows: [
                        Shadow(color: Colors.black.withOpacity(.45), blurRadius: 12),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: tvIsWindowsDesktop ? 30 : 22,
                      vertical: tvIsWindowsDesktop ? 18 : 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(.34),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: Colors.white.withOpacity(.07)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(.28),
                          blurRadius: 34,
                          spreadRadius: -6,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _TeamIdentity(name: _arabicTeamName(match.awayName), badge: data.awayBadge),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: tvIsWindowsDesktop ? 36 : 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                showScore ? '${match.homeScore} - ${match.awayScore}' : 'ضد',
                                textDirection: TextDirection.ltr,
                                style: TextStyle(
                                  fontSize: showScore ? 38 : 24,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(color: Colors.black.withOpacity(.42), blurRadius: 14),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: match.isLive
                                      ? TvColors.red.withOpacity(.16)
                                      : Colors.white.withOpacity(.06),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: match.isLive
                                        ? TvColors.red.withOpacity(.40)
                                        : Colors.white.withOpacity(.10),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.circle,
                                      size: 8,
                                      color: match.isLive ? const Color(0xFFFF3547) : Colors.white38,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      match.isLive ? 'مباشر' : 'قادمة',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        color: match.isLive ? Colors.white : Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        _TeamIdentity(name: _arabicTeamName(match.homeName), badge: data.homeBadge),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _timeLabel(context),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: tvIsWindowsDesktop ? 26 : 21,
                      fontWeight: FontWeight.w900,
                      shadows: [
                        Shadow(color: Colors.black.withOpacity(.42), blurRadius: 14),
                      ],
                    ),
                  ),
                  if (data.stadiumName.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(.22),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white.withOpacity(.07)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.stadium_rounded,
                            size: 18,
                            color: Colors.white.withOpacity(.72),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            'الملعب: ${_arabicVenueName(data.stadiumName)}',
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              fontSize: tvIsWindowsDesktop ? 15 : 12,
                              fontWeight: FontWeight.w800,
                              color: Colors.white.withOpacity(.80),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (data.broadcastName.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _BroadcasterChip(
                      displayName: _arabicBroadcastName(data.broadcastName),
                      logo: data.broadcastLogo,
                      isBein: _isBeinBroadcast(data.broadcastName),
                    ),
                  ],
                  if (onWatch != null) ...[
                    const SizedBox(height: 24),
                    TvFocus(
                      autofocus: autofocusWatch,
                      focusNode: watchFocusNode,
                      onFocused: onFocused,
                      onArrowLeft: onArrowLeft,
                      onArrowRight: onArrowRight,
                      onPressed: onWatch!,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: tvIsWindowsDesktop ? 42 : 34,
                          vertical: tvIsWindowsDesktop ? 16 : 13,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF4343), Color(0xFFB10018)],
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF3A46).withOpacity(.40),
                              blurRadius: 26,
                              spreadRadius: -6,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow_rounded, size: 28),
                            SizedBox(width: 8),
                            Text('شاهد الآن', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const Spacer(flex: 2),
                  Icon(Icons.keyboard_arrow_down_rounded, size: 28, color: Colors.white.withOpacity(.24)),
                  Text(
                    'القنوات',
                    style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(.25)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BroadcasterChip extends StatelessWidget {
  const _BroadcasterChip({
    required this.displayName,
    required this.logo,
    required this.isBein,
  });

  final String displayName;
  final String logo;
  final bool isBein;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.30),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isBein
              ? const Color(0xFF8F60FF).withOpacity(.46)
              : Colors.white.withOpacity(.08),
        ),
        boxShadow: isBein
            ? [
                BoxShadow(
                  color: const Color(0xFF6B35D4).withOpacity(.22),
                  blurRadius: 22,
                  spreadRadius: -7,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: TextDirection.rtl,
        children: [
          Text(
            displayName,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontSize: tvIsWindowsDesktop ? 16 : 13,
              fontWeight: FontWeight.w900,
              color: Colors.white.withOpacity(.90),
            ),
          ),
          const SizedBox(width: 10),
          if (isBein)
            const _BeinSportsMark()
          else if (logo.isNotEmpty)
            Image.network(
              logo,
              width: 32,
              height: 32,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            )
          else
            Icon(
              Icons.live_tv_rounded,
              size: 22,
              color: Colors.white.withOpacity(.65),
            ),
        ],
      ),
    );
  }
}

class _BeinSportsMark extends StatelessWidget {
  const _BeinSportsMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 5, 8, 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7B45E6), Color(0xFF4D238B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Colors.white.withOpacity(.28), width: .8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7B45E6).withOpacity(.30),
            blurRadius: 14,
            spreadRadius: -5,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'beIN',
            textDirection: TextDirection.ltr,
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: -.4,
              height: 1,
            ),
          ),
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'SPORTS',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                color: Color(0xFF4D238B),
                fontSize: 7,
                fontWeight: FontWeight.w900,
                letterSpacing: .5,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroBackdropBadge extends StatelessWidget {
  const _HeroBackdropBadge({required this.url, required this.tint});
  final String url;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const SizedBox.shrink();
    return Opacity(
      opacity: .10,
      child: ColorFiltered(
        colorFilter: ColorFilter.mode(tint.withOpacity(.75), BlendMode.srcATop),
        child: Image.network(
          url,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _TeamIdentity extends StatelessWidget {
  const _TeamIdentity({required this.name, required this.badge});
  final String name;
  final String badge;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: tvIsWindowsDesktop ? 170 : 134,
      child: Column(
        children: [
          Container(
            width: tvIsWindowsDesktop ? 78 : 64,
            height: tvIsWindowsDesktop ? 78 : 64,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.08),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.18),
                  blurRadius: 12,
                  spreadRadius: -4,
                ),
              ],
            ),
            child: badge.isEmpty
                ? Icon(Icons.shield_rounded, size: 58, color: Colors.white.withOpacity(.32))
                : Image.network(
                    badge,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.shield_rounded,
                      size: 58,
                      color: Colors.white.withOpacity(.32),
                    ),
                  ),
          ),
          const SizedBox(height: 10),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _HeroPlayerImage extends StatelessWidget {
  const _HeroPlayerImage({
    required this.url,
    required this.fallback,
    required this.alignment,
    required this.tint,
  });
  final String url;
  final String fallback;
  final Alignment alignment;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final hasUrl = url.isNotEmpty;
    return Stack(
      fit: StackFit.expand,
      children: [
        Align(
          alignment: alignment,
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: alignment == Alignment.bottomLeft ? Alignment.bottomLeft : Alignment.bottomRight,
                end: Alignment.topCenter,
                colors: [tint.withOpacity(.14), Colors.transparent],
              ),
            ),
          ),
        ),
        if (!hasUrl && fallback.isNotEmpty)
          Align(
            alignment: alignment,
            child: Opacity(
              opacity: .16,
              child: Image.network(
                fallback,
                width: 230,
                height: 230,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        if (hasUrl)
          Align(
            alignment: alignment,
            child: Image.network(
              url,
              fit: BoxFit.contain,
              alignment: alignment,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        if (hasUrl)
          Align(
            alignment: alignment == Alignment.bottomLeft ? const Alignment(-.52, .95) : const Alignment(.52, .95),
            child: Container(
              width: 180,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(.42),
                    blurRadius: 42,
                    spreadRadius: 8,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
class _HeroLoading extends StatelessWidget {
  const _HeroLoading();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF1A080B), Color(0xFF080809), Color(0xFF07101C)],
        ),
      ),
      child: const Center(
        child: SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
  }
}

class _QualitySection {
  const _QualitySection(this.id, this.name);

  final String id;
  final String name;
}

class _ChannelGroup {
  const _ChannelGroup(this.key, this.channels);
  final String key;
  final List<TvChannel> channels;

  String get title {
    if (channels.isEmpty) return '';
    return channels.first.name
        .replaceAll(
          RegExp(
            r'\b(?:FHD|UHD|HD|SD|HEVC|H265|H264|4K|50FPS|60FPS)\b',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
