import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/navigation/cinematy_page_route.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/cinematy_top_bar.dart';
import '../../widgets/network_image.dart';
import '../../widgets/shimmer.dart';
import 'tv_models.dart';
import 'football_match_models.dart';
import 'football_matches_service.dart';
import 'tv_channel_group_screen.dart';
import 'xtream_tv_service.dart';

class TvScreen extends StatefulWidget {
  const TvScreen({super.key});

  @override
  State<TvScreen> createState() => _TvScreenState();
}

class _TvScreenState extends State<TvScreen>
    with AutomaticKeepAliveClientMixin {
  final XtreamTvService _service = XtreamTvService();
  final FootballMatchesService _matchesService = FootballMatchesService();
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  Timer? _matchesRefreshTimer;

  List<TvCategory> _categories = const [];
  List<TvChannel> _channels = const [];
  List<TvChannel> _allChannels = const [];
  String? _selectedCategory;
  bool _loadingCategories = true;
  bool _loadingChannels = true;
  String? _error;
  String _query = '';
  int _requestSerial = 0;
  List<FootballMatch> _todayMatches = const [];
  bool _loadingMatches = true;
  String? _matchesError;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _loadMatches();
    _matchesRefreshTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _loadMatches(silent: true),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _matchesRefreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMatches({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loadingMatches = true;
        _matchesError = null;
      });
    }
    try {
      final matches = await _matchesService.getTodayMatches();
      if (!mounted) return;
      setState(() {
        _todayMatches = matches;
        _loadingMatches = false;
        _matchesError = null;
      });
    } catch (e) {
      if (!mounted) return;
      // Keep the TV screen usable, but surface the football-feed failure.
      setState(() {
        _loadingMatches = false;
        _matchesError = e.toString();
      });
    }
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
    return _channels
        .where((e) => e.name.toLowerCase().contains(_query))
        .toList(growable: false);
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

    return Scaffold(
      appBar: const CinematyTopBar(section: 'التلفاز'),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([_loadInitial(), _loadMatches()]);
        },
        child: CustomScrollView(
          key: const PageStorageKey('tv-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                child: _TvSearchField(
                  controller: _searchController,
                  onChanged: _onSearch,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _TodayMatchesStrip(
                matches: _todayMatches,
                loading: _loadingMatches,
                error: _matchesError,
                onRetry: _loadMatches,
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
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 130),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisExtent: 154,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
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
                        '${match.homeScore ?? 0}  -  ${match.awayScore ?? 0}',
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
