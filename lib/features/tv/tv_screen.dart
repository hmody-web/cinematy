import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/navigation/cinematy_page_route.dart';
import '../../core/theme/app_theme.dart';
import '../../data/stores/app_settings_store.dart';
import '../../providers.dart';
import '../../widgets/cinematy_top_bar.dart';
import '../../widgets/network_image.dart';
import '../../widgets/shimmer.dart';
import 'bein_channel_resolver.dart';
import 'football_match_models.dart';
import 'football_matches_service.dart';
import 'mobile_match_hero.dart';
import 'sports_match_hero_service.dart';
import 'tv_channel_group_screen.dart';
import 'tv_models.dart';
import 'tv_player_screen.dart';
import 'tv_runtime_state.dart';
import 'xtream_tv_service.dart';

class TvScreen extends ConsumerStatefulWidget {
  const TvScreen({super.key});

  @override
  ConsumerState<TvScreen> createState() => _TvScreenState();
}

class _TvScreenState extends ConsumerState<TvScreen>
    with AutomaticKeepAliveClientMixin {
  final XtreamTvService _service = XtreamTvService();
  final FootballMatchesService _matchesService = FootballMatchesService();
  final SportsMatchHeroService _heroService = SportsMatchHeroService();
  final TextEditingController _searchController = TextEditingController();
  final PageController _heroPageController = PageController();

  Timer? _searchDebounce;
  Timer? _heroRefreshTimer;
  Timer? _heroEnrichDelay;
  Timer? _heroAutoPageTimer;

  List<TvCategory> _categories = const [];
  List<TvChannel> _channels = const [];
  List<TvChannel> _allChannels = const [];
  String? _selectedCategory;
  bool _loadingCategories = true;
  bool _loadingChannels = true;
  String? _error;
  String _query = '';
  int _requestSerial = 0;

  List<SportsMatchHeroData> _heroes = const [];
  final Set<String> _heroEnriching = <String>{};
  final Set<String> _heroEnriched = <String>{};
  int _heroIndex = 0;
  bool _heroLoading = true;
  bool _heroAutoForward = true;
  late final AppSettingsStore _settings;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _settings = ref.read(appSettingsProvider);
    _settings.addListener(_onSettingsChanged);
    tvLivePlaybackActive.addListener(_onPlaybackStateChanged);
    _loadInitial();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_settings.hideTvScoreboard) {
        _loadHero();
        _startHeroRefreshTimer();
      } else {
        setState(() => _heroLoading = false);
      }
    });
  }

  Duration get _heroRefreshInterval => _settings.lowEndLiveOptimization
      ? const Duration(minutes: 15)
      : const Duration(minutes: 5);

  void _onSettingsChanged() {
    if (!mounted) return;
    if (_settings.hideTvScoreboard) {
      _heroRefreshTimer?.cancel();
      _heroAutoPageTimer?.cancel();
      _heroEnrichDelay?.cancel();
      if (_heroLoading) setState(() => _heroLoading = false);
      return;
    }
    _startHeroRefreshTimer();
    _scheduleHeroAutoAdvance();
    if (_heroes.isEmpty && !_heroLoading) unawaited(_loadHero());
    setState(() {});
  }

  void _onPlaybackStateChanged() {
    if (!mounted || !_settings.lowEndLiveOptimization) return;
    if (tvLivePlaybackActive.value) {
      _heroRefreshTimer?.cancel();
      _heroAutoPageTimer?.cancel();
      _heroEnrichDelay?.cancel();
      return;
    }
    if (!_settings.hideTvScoreboard) {
      _startHeroRefreshTimer();
      _scheduleHeroAutoAdvance();
    }
  }

  void _startHeroRefreshTimer() {
    _heroRefreshTimer?.cancel();
    if (_settings.hideTvScoreboard ||
        (_settings.lowEndLiveOptimization && tvLivePlaybackActive.value)) {
      return;
    }
    _heroRefreshTimer = Timer.periodic(
      _heroRefreshInterval,
      (_) => _loadHero(silent: true),
    );
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    tvLivePlaybackActive.removeListener(_onPlaybackStateChanged);
    _searchDebounce?.cancel();
    _heroRefreshTimer?.cancel();
    _heroEnrichDelay?.cancel();
    _heroAutoPageTimer?.cancel();
    _heroPageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadHero({bool silent = false}) async {
    if (_settings.hideTvScoreboard) return;
    if (!silent && mounted) setState(() => _heroLoading = true);
    try {
      final matches = await _matchesService.getNext24HourMatches();
      if (!mounted) return;

      final hasRealInWindow = matches.any((match) {
        final home = _clubKey(match.homeName);
        final away = _clubKey(match.awayName);
        return home.contains('real madrid') ||
            away.contains('real madrid') ||
            home.contains('ريال مدريد') ||
            away.contains('ريال مدريد');
      });
      final hasBarcaInWindow = matches.any((match) {
        final home = _clubKey(match.homeName);
        final away = _clubKey(match.awayName);
        return home.contains('barcelona') ||
            away.contains('barcelona') ||
            home.contains('برشلونة') ||
            away.contains('برشلونة');
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
      final ordered = byId.values.toList(growable: false)..sort(_compareHeroMatches);
      final previous = <String, SportsMatchHeroData>{
        for (final item in _heroes) item.match.id: item,
      };
      final next = ordered
          .map(
            (match) => previous[match.id]?.withMatch(match) ??
                SportsMatchHeroData(
                  match: match,
                  homeBadge: match.homeLogo,
                  awayBadge: match.awayLogo,
                  leagueBadge: match.leagueLogo,
                ),
          )
          .toList(growable: false);
      var nextIndex = _heroIndex;
      if (next.isEmpty) {
        nextIndex = 0;
      } else if (nextIndex >= next.length) {
        nextIndex = next.length - 1;
      }
      setState(() {
        _heroes = next;
        _heroIndex = nextIndex;
        _heroLoading = false;
      });
      if (next.isNotEmpty) {
        if (silent) _heroEnriched.remove(next[nextIndex].match.id);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_heroPageController.hasClients) return;
          final current = _heroPageController.page?.round();
          if (current != nextIndex) _heroPageController.jumpToPage(nextIndex);
        });
        _scheduleHeroEnrich(nextIndex);
        _scheduleHeroAutoAdvance();
      } else {
        _heroAutoPageTimer?.cancel();
      }
    } catch (_) {
      if (mounted) setState(() => _heroLoading = false);
    }
  }

  int _compareHeroMatches(FootballMatch a, FootballMatch b) {
    final pa = _featuredPriority(a);
    final pb = _featuredPriority(b);
    if (pa != pb) return pb.compareTo(pa);
    if (a.isLive != b.isLive) return a.isLive ? -1 : 1;
    final at = a.startsAt ?? DateTime(9999, 12, 31);
    final bt = b.startsAt ?? DateTime(9999, 12, 31);
    return at.compareTo(bt);
  }

  int _featuredPriority(FootballMatch match) {
    final home = _clubKey(match.homeName);
    final away = _clubKey(match.awayName);
    final real = home.contains('real madrid') || away.contains('real madrid') ||
        home.contains('ريال مدريد') || away.contains('ريال مدريد');
    final barca = home.contains('barcelona') || away.contains('barcelona') ||
        home.contains('برشلونة') || away.contains('برشلونة');
    if (real && barca) return 3;
    if (real || barca) return 2;
    return 0;
  }

  String _clubKey(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9؀-ۿ]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  void _scheduleHeroEnrich(int index) {
    _heroEnrichDelay?.cancel();
    _heroEnrichDelay = Timer(
      const Duration(milliseconds: 180),
      () => _enrichHeroAt(index),
    );
  }

  Future<void> _enrichHeroAt(int index) async {
    if (_settings.hideTvScoreboard || index < 0 || index >= _heroes.length) return;
    final match = _heroes[index].match;
    if (_heroEnriched.contains(match.id) || _heroEnriching.contains(match.id)) return;
    _heroEnriching.add(match.id);
    try {
      final enriched = await _heroService.enrich(match);
      if (!mounted) return;
      final current = _heroes.indexWhere((item) => item.match.id == match.id);
      if (current < 0) return;
      final updated = [..._heroes];
      updated[current] = enriched;
      setState(() => _heroes = updated);
      _heroEnriched.add(match.id);
    } catch (_) {
      // Base match card stays usable if artwork enrichment is unavailable.
    } finally {
      _heroEnriching.remove(match.id);
    }
  }

  void _onHeroPageChanged(int index) {
    if (_heroIndex != index) setState(() => _heroIndex = index);
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
    if (_settings.hideTvScoreboard ||
        _heroes.length <= 1 ||
        (_settings.lowEndLiveOptimization && tvLivePlaybackActive.value)) {
      return;
    }

    // Prepare the next scoreboard while the current one is still visible.
    // This keeps network/image work out of the actual page animation.
    final warmIndex = _nextHeroIndex();
    if (warmIndex != _heroIndex) {
      unawaited(_enrichHeroAt(warmIndex));
    }

    _heroAutoPageTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted || !_heroPageController.hasClients || _heroes.length <= 1) return;
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
    });
  }

  Future<void> _watchHero(SportsMatchHeroData data) async {
    final broadcast = data.broadcastName.trim();
    if (broadcast.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لم تُعلن القناة الناقلة لهذه المباراة بعد.')),
      );
      return;
    }

    final channel = _bestBroadcastMatch(_allChannels, broadcast);
    if (!mounted) return;
    if (channel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('القناة الناقلة: $broadcast — لم أجد قناة مطابقة ضمن مصادر التلفاز الحالية.')),
      );
      return;
    }

    final lowEnd = _settings.lowEndLiveOptimization;
    if (lowEnd) {
      _heroRefreshTimer?.cancel();
      _heroEnrichDelay?.cancel();
    }
    await Navigator.of(context).push(
      CinematyPageRoute(
        builder: (_) => TvPlayerScreen(
          channel: channel,
          channels: _allChannels,
          service: _service,
        ),
      ),
    );
    if (mounted && lowEnd && !_settings.hideTvScoreboard) {
      _startHeroRefreshTimer();
    }
  }

  TvChannel? _bestBroadcastMatch(List<TvChannel> channels, String broadcast) {
    if (channels.isEmpty || broadcast.trim().isEmpty) return null;

    // IMPORTANT: resolve beIN against the *real* channels currently returned
    // by this app's Xtream source. This also understands providers that put
    // "beIN" only in the category while naming the stream simply "6 FHD".
    final broadcastIsBein = BeinChannelResolver.isBeinLabel(broadcast);
    final realBein = BeinChannelResolver.resolve(
      channels: channels,
      categories: _categories,
      broadcast: broadcast,
      preferredVariant: _settings.lowEndLiveOptimization ? 'F' : 'N',
    );
    if (realBein != null) return realBein;

    // If the scoreboard says beIN, never fall through to a generic same-number
    // channel from another network. Keep searching real beIN rows only.
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
    final id = _channelIdentity(value);
    final match = RegExp(r'(\d{1,2})').firstMatch(id);
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

  Future<void> _loadInitial() async {
    final serial = ++_requestSerial;
    setState(() {
      _loadingCategories = true;
      _loadingChannels = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.getCategories(),
        _service.getChannels(),
      ]);
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _categories = results[0] as List<TvCategory>;
        _channels = results[1] as List<TvChannel>;
        _allChannels = results[1] as List<TvChannel>;
        _loadingCategories = false;
        _loadingChannels = false;
      });
    } catch (e) {
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _loadingCategories = false;
        _loadingChannels = false;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _selectCategory(String? id) async {
    if (_selectedCategory == id && !_loadingChannels) return;
    final serial = ++_requestSerial;
    setState(() {
      _selectedCategory = id;
      _loadingChannels = true;
      _error = null;
    });
    try {
      final channels = await _service.getChannels(categoryId: id);
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _channels = channels;
        _loadingChannels = false;
      });
    } catch (e) {
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _loadingChannels = false;
        _error = _friendlyError(e);
      });
    }
  }

  void _onSearch(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => _query = value.trim().toLowerCase());
    });
  }

  List<TvChannel> get _visibleChannels {
    if (_query.isEmpty) return _channels;
    return _channels.where((e) => e.name.toLowerCase().contains(_query)).toList(growable: false);
  }

  String _friendlyError(Object error) {
    final text = '$error';
    if (text.contains('TV_SOURCE_NOT_CONFIGURED')) {
      return 'مصدر التلفاز غير مهيأ بعد. أضف بيانات اشتراك Xtream المصرح لك باستخدامها إلى إعدادات البناء.';
    }
    return 'تعذر تحميل القنوات. تحقق من اتصال الإنترنت ومصدر التلفاز ثم حاول مرة أخرى.';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final channels = _visibleChannels;
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    final heroHeight = landscape
        ? (size.height * .78).clamp(300.0, 520.0).toDouble()
        : (size.height * .64).clamp(430.0, 620.0).toDouble();

    return Scaffold(
      appBar: const CinematyTopBar(section: 'التلفاز'),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadInitial();
          if (!_settings.hideTvScoreboard) await _loadHero();
        },
        child: CustomScrollView(
          key: const PageStorageKey('tv-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (!_settings.hideTvScoreboard && (_heroLoading || _heroes.isNotEmpty))
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    landscape ? 12 : 10,
                    landscape ? 8 : 10,
                    landscape ? 12 : 10,
                    landscape ? 12 : 14,
                  ),
                  child: SizedBox(
                    height: heroHeight,
                    child: _heroLoading && _heroes.isEmpty
                        ? _MobileHeroLoading(landscape: landscape)
                        : MobileMatchHeroCarousel(
                            items: _heroes,
                            controller: _heroPageController,
                            currentIndex: _heroIndex,
                            onPageChanged: _onHeroPageChanged,
                            onWatch: _watchHero,
                          ),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(kIsWeb ? 30 : 18, kIsWeb ? 24 : 8, kIsWeb ? 30 : 18, 12),
                child: _TvSearchField(
                  controller: _searchController,
                  onChanged: _onSearch,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 48,
                child: _loadingCategories
                    ? const _CategorySkeleton()
                    : ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        children: [
                          _CategoryChip(
                            title: 'الكل',
                            selected: _selectedCategory == null,
                            onTap: () => _selectCategory(null),
                          ),
                          ..._categories.map(
                            (category) => _CategoryChip(
                              title: category.name,
                              selected: _selectedCategory == category.id,
                              onTap: () => _selectCategory(category.id),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _TvErrorState(message: _error!, onRetry: _loadInitial),
              )
            else if (_loadingChannels)
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(18, 4, 18, 130),
                sliver: _ChannelSkeletonGrid(),
              )
            else if (channels.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 20, 28, 130),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.live_tv_rounded,
                          size: 48,
                          color: Colors.white.withOpacity(.18),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'لا توجد قنوات',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _query.isEmpty
                              ? 'هذا التصنيف لا يحتوي على قنوات.'
                              : 'لا توجد قناة مطابقة لبحثك.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white.withOpacity(.55)),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(kIsWeb ? 30 : 18, 4, kIsWeb ? 30 : 18, kIsWeb ? 48 : 130),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: kIsWeb ? 300 : 220,
                    mainAxisExtent: kIsWeb ? 200 : 154,
                    crossAxisSpacing: kIsWeb ? 18 : 12,
                    mainAxisSpacing: kIsWeb ? 18 : 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final channel = channels[index];
                      return _ChannelCard(
                        channel: channel,
                        onTap: () {
                          final key = channel.groupKey;
                          final variants = _allChannels
                              .where((item) => item.groupKey == key)
                              .toList(growable: false);
                          Navigator.of(context).push(
                            CinematyPageRoute(
                              builder: (_) => TvChannelGroupScreen(
                                channel: channel,
                                variants: variants.isEmpty ? [channel] : variants,
                                allChannels: _allChannels,
                              ),
                            ),
                          );
                        },
                      );
                    },
                    childCount: channels.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MobileHeroLoading extends StatelessWidget {
  const _MobileHeroLoading({required this.landscape});
  final bool landscape;

  @override
  Widget build(BuildContext context) {
    return CinematyShimmer(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(landscape ? 18 : 28),
          border: Border.all(color: Colors.white.withOpacity(.05)),
        ),
      ),
    );
  }
}

class _TvSearchField extends StatelessWidget {
  const _TvSearchField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'ابحث عن قناة…',
        prefixIcon: const Icon(Icons.search_rounded),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withOpacity(.06)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withOpacity(.06)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: AppColors.redBright.withOpacity(.7)),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.title,
    required this.selected,
    required this.onTap,
  });
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(title),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.redBright.withOpacity(.18),
        backgroundColor: AppColors.surface,
        side: BorderSide(
          color: selected
              ? AppColors.redBright.withOpacity(.45)
              : Colors.white.withOpacity(.05),
        ),
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.white.withOpacity(.68),
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({required this.channel, required this.onTap});
  final TvChannel channel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 42),
                child: CinematyNetworkImage(
                  url: channel.icon,
                  fit: BoxFit.contain,
                  memCacheWidth: 420,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(.88),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 6, color: Colors.white),
                    SizedBox(width: 5),
                    Text(
                      'مباشر',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh.withOpacity(.96),
                  border: Border(top: BorderSide(color: Colors.white.withOpacity(.04))),
                ),
                child: Text(
                  channel.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TvErrorState extends StatelessWidget {
  const _TvErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 130),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.live_tv_rounded, size: 50, color: Colors.white.withOpacity(.22)),
            const SizedBox(height: 14),
            const Text(
              'تعذر فتح التلفاز',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.6, color: Colors.white.withOpacity(.58)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategorySkeleton extends StatelessWidget {
  const _CategorySkeleton();
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (_, i) => CinematyShimmer(
        child: Container(
          width: i == 0 ? 66 : 94,
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

class _ChannelSkeletonGrid extends StatelessWidget {
  const _ChannelSkeletonGrid();
  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 154,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      delegate: SliverChildBuilderDelegate(
        (_, __) => CinematyShimmer(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        childCount: 10,
      ),
    );
  }
}


class _TodayMatchesStrip extends StatelessWidget {
  const _TodayMatchesStrip({
    required this.matches,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final List<FootballMatch> matches;
  final bool loading;
  final String? error;
  final Future<void> Function({bool silent}) onRetry;

  @override
  Widget build(BuildContext context) {
    final hasLive = matches.any((m) => m.isLive);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: Row(
              children: [
                const Text(
                  'مباريات اليوم',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                if (hasLive) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.redBright.withOpacity(.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.redBright.withOpacity(.28)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _LiveDot(),
                        SizedBox(width: 5),
                        Text('مباشر', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.redBright)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Directionality(
            textDirection: TextDirection.rtl,
            child: SizedBox(
              height: 132,
              child: loading
                ? ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    itemCount: 3,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, __) => Container(
                      width: 238,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.045),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.white.withOpacity(.055)),
                      ),
                    ),
                  )
                : matches.isNotEmpty
                    ? ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        physics: const BouncingScrollPhysics(),
                        itemCount: matches.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, index) => _MatchCard(match: matches[index]),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(.035),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: Colors.white.withOpacity(.06)),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 16),
                              Icon(
                                error == null ? Icons.sports_soccer_rounded : Icons.cloud_off_rounded,
                                color: Colors.white.withOpacity(.45),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  error == null
                                      ? 'لا توجد مباريات متاحة حالياً.'
                                      : 'تعذر تحميل مباريات اليوم. اضغط لإعادة المحاولة.',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(.66),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'إعادة المحاولة',
                                onPressed: () => onRetry(silent: false),
                                icon: const Icon(Icons.refresh_rounded),
                              ),
                              const SizedBox(width: 6),
                            ],
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

class _LiveDot extends StatelessWidget {
  const _LiveDot();
  @override
  Widget build(BuildContext context) => Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(color: AppColors.redBright, shape: BoxShape.circle),
      );
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match});
  final FootballMatch match;

  String _arabicLeagueName(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return 'كرة القدم';
    final name = value.toLowerCase();

    if (name.contains('premier league') &&
        (name.contains('england') || name == 'premier league' || name.contains('english'))) {
      return 'الدوري الإنجليزي الممتاز';
    }
    if (name.contains('la liga') || name.contains('laliga') || name.contains('primera division')) {
      return 'الدوري الإسباني';
    }
    if (name.contains('serie a') && (name.contains('ital') || name == 'serie a')) {
      return 'الدوري الإيطالي';
    }
    if (name.contains('bundesliga')) return 'الدوري الألماني';
    if (name.contains('ligue 1')) return 'الدوري الفرنسي';

    if (name == 'rsl' ||
        name.contains('saudi pro league') ||
        name.contains('saudi professional league') ||
        name.contains('saudi arabia pro league') ||
        name.contains('saudi arabia - pro league') ||
        name.contains('roshn saudi league') ||
        name.contains('roshn saudi pro league') ||
        name.contains('roshn league') ||
        name.contains('roshn') ||
        name.contains('دوري روشن') ||
        name.contains('الدوري السعودي')) {
      return 'دوري روشن السعودي';
    }
    if (name.contains('iraq stars league') ||
        name.contains('iraqi stars league') ||
        name.contains('iraq premier league') ||
        name.contains('iraqi premier league') ||
        name.contains('دوري نجوم العراق')) {
      return 'دوري نجوم العراق';
    }
    // CAF Champions League is intentionally not part of this scoreboard.
    if (name.contains('afc champions league elite')) return 'دوري أبطال آسيا للنخبة';
    if (name.contains('afc champions league two')) return 'دوري أبطال آسيا 2';
    if (name.contains('afc champions league')) return 'دوري أبطال آسيا';
    if (name.contains('uefa champions league') ||
        name.contains('europe champions league') ||
        name.contains('european champions league')) {
      return 'دوري أبطال أوروبا';
    }

    if (name.contains('afc asian cup') ||
        name == 'asian cup' ||
        name.contains('asian cup qualification') ||
        name.contains('asian cup qualifier')) {
      return name.contains('qualif') ? 'تصفيات كأس آسيا' : 'كأس آسيا';
    }
    if (name.contains('arabian gulf cup') ||
        name.contains('gulf cup') ||
        name.contains('khaleeji') ||
        name.contains('خليجي')) {
      return 'كأس الخليج العربي';
    }
    if (name.contains('africa cup of nations') ||
        name.contains('african cup of nations') ||
        name.contains('afcon')) {
      return name.contains('qualif') ? 'تصفيات كأس أمم أفريقيا' : 'كأس أمم أفريقيا';
    }

    if (name.contains('fifa world cup') || name == 'world cup') {
      return name.contains('qualif') ? 'تصفيات كأس العالم' : 'كأس العالم';
    }
    if (name.contains('world cup qualification') || name.contains('world cup qualifier')) {
      return 'تصفيات كأس العالم';
    }
    if (name.contains('uefa euro') || name == 'euro' || name.contains('european championship')) {
      return name.contains('qualif') ? 'تصفيات كأس أمم أوروبا' : 'كأس أمم أوروبا';
    }
    if (name.contains('copa america')) return 'كوبا أمريكا';
    if (name.contains('uefa nations league')) return 'دوري الأمم الأوروبية';
    if (name.contains('concacaf nations league')) return 'دوري أمم الكونكاكاف';
    if (name.contains('friendly') || name.contains('international friendly')) return 'مباراة دولية ودية';

    if (name == 'mls' || name.contains('major league soccer') || name.contains('usa mls')) {
      return 'الدوري الأمريكي';
    }

    return value;
  }

  String _timeLabel(BuildContext context) {
    if (match.isLive) {
      final minute = match.minute;
      return minute == null ? 'مباشر' : "$minute′";
    }
    if (match.isFinished) return 'انتهت';
    if (match.status == FootballMatchStatus.postponed) return 'مؤجلة';
    final date = match.startsAt;
    if (date == null) return 'قريباً';
    return TimeOfDay.fromDateTime(date).format(context);
  }

  @override
  Widget build(BuildContext context) {
    final showScore = match.isLive || match.isFinished ||
        (match.homeScore != null && match.awayScore != null);
    return Container(
      width: 238,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          stops: const [0.0, .48, 1.0],
          colors: match.isLive
              ? [
                  const Color(0xFF321014),
                  const Color(0xFF17090B),
                  const Color(0xFF09090B),
                ]
              : [
                  const Color(0xFF230D10),
                  const Color(0xFF130A0C),
                  const Color(0xFF09090B),
                ],
        ),
        border: Border.all(
          color: match.isLive
              ? AppColors.redBright.withOpacity(.34)
              : AppColors.redBright.withOpacity(.13),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.30),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: AppColors.redBright.withOpacity(match.isLive ? .10 : .045),
            blurRadius: 22,
            spreadRadius: -8,
            offset: const Offset(6, -4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(.82, -.88),
              radius: 1.18,
              colors: [
                AppColors.redBright.withOpacity(match.isLive ? .13 : .065),
                AppColors.redBright.withOpacity(.018),
                Colors.transparent,
              ],
              stops: const [0.0, .42, 1.0],
            ),
          ),
          child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    if (match.leagueLogo.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: Image.network(
                          match.leagueLogo,
                          width: 18,
                          height: 18,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        _arabicLeagueName(match.league),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(.48)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _timeLabel(context),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: match.isLive ? AppColors.redBright : Colors.white.withOpacity(.76),
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: _MatchTeam(name: match.homeName, logo: match.homeLogo)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: showScore
                    ? Text(
                        '${match.awayScore ?? 0}  -  ${match.homeScore ?? 0}',
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: .4),
                      )
                    : Text(
                        'VS',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white.withOpacity(.28)),
                      ),
              ),
              Expanded(child: _MatchTeam(name: match.awayName, logo: match.awayLogo)),
            ],
          ),
          const Spacer(),
        ],
          ),
        ),
      ),
    );
  }
}

class _MatchTeam extends StatelessWidget {
  const _MatchTeam({required this.name, required this.logo});
  final String name;
  final String logo;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 36,
          height: 36,
          child: logo.isEmpty
              ? Icon(Icons.shield_rounded, size: 30, color: Colors.white.withOpacity(.28))
              : ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CinematyNetworkImage(
                    url: logo,
                    fit: BoxFit.contain,
                  ),
                ),
        ),
        const SizedBox(height: 7),
        Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}
