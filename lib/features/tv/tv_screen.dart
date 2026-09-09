import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/navigation/cinematy_page_route.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/cinematy_top_bar.dart';
import '../../widgets/network_image.dart';
import '../../widgets/shimmer.dart';
import 'tv_models.dart';
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
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  List<TvCategory> _categories = const [];
  List<TvChannel> _channels = const [];
  List<TvChannel> _allChannels = const [];
  String? _selectedCategory;
  bool _loadingCategories = true;
  bool _loadingChannels = true;
  String? _error;
  String _query = '';
  int _requestSerial = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
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
        onRefresh: _loadInitial,
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
