import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/media_item.dart';
import '../../providers.dart';
import '../../widgets/cinematy_top_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/media_card.dart';
import '../../widgets/shimmer.dart';
import '../details/details_screen.dart';
import '../library/library_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with AutomaticKeepAliveClientMixin {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<MediaItem> _allResults = const [];
  List<MediaItem> _results = const [];
  bool _loading = false;
  String _filter = 'الكل';
  String? _error;
  int _requestSerial = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () => _search(value));
    setState(() {});
  }

  Future<void> _search(String value) async {
    final q = value.trim();
    final serial = ++_requestSerial;
    if (q.length < 2) {
      if (!mounted) return;
      setState(() {
        _allResults = const [];
        _results = const [];
        _loading = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await ref.read(apiProvider).searchAll(q);
      if (!mounted || serial != _requestSerial) return;
      _allResults = data;
      _applyFilter();
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _applyFilter() {
    switch (_filter) {
      case 'أفلام':
        _results = _allResults.where((e) => !e.isSeries).toList();
        break;
      case 'مسلسلات':
        _results = _allResults.where((e) => e.isSeries).toList();
        break;
      default:
        _results = [..._allResults];
    }
  }

  void _changeFilter(String value) {
    setState(() {
      _filter = value;
      _applyFilter();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final downloads = ref.watch(downloadProvider);
    return Scaffold(
      appBar: CinematyTopBar(
        section: 'البحث',
        downloadsCount: downloads.items.length + downloads.activeItems.length,
        onContinue: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ContinueWatchingScreen()),
        ),
        onDownloads: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DownloadsScreen()),
        ),
      ),
      body: CustomScrollView(
        key: const PageStorageKey('search-scroll'),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
              child: TextField(
                controller: _controller,
                autofocus: false,
                textInputAction: TextInputAction.search,
                onChanged: _changed,
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: 'ابحث عن فيلم، مسلسل أو ممثل…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _controller.clear();
                            _changed('');
                          },
                        ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 48,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                scrollDirection: Axis.horizontal,
                children: ['الكل', 'أفلام', 'مسلسلات']
                    .map(
                      (f) => Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ChoiceChip(
                          selected: _filter == f,
                          label: Text(f),
                          selectedColor: AppColors.red.withOpacity(.35),
                          onSelected: (_) => _changeFilter(f),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          if (_loading) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(18, 18, 18, 4),
                child: Row(
                  children: [
                    SkeletonBox(width: 118, height: 14, radius: 7),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 130),
              sliver: SliverGrid.builder(
                itemCount: 9,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 16,
                  childAspectRatio: .52,
                ),
                itemBuilder: (_, __) => const SkeletonPosterCard(width: double.infinity),
              ),
            ),
          ] else if (_error != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                title: 'تعذر البحث',
                message: 'حاول مرة أخرى بعد قليل.',
                onRetry: () => _search(_controller.text),
              ),
            )
          else if (_controller.text.trim().length < 2)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.search_rounded,
                title: 'شنو تحب تشوف اليوم؟',
                message:
                    'اكتب حرفين أو أكثر. البحث يجرب الاسم الكامل والتهجئات القريبة والنتائج المشابهة.',
              ),
            )
          else if (_results.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                title: 'ما لقينا نتائج',
                message:
                    'جرّب الاسم بالعربية أو الإنجليزية. البحث لا يعتمد على التطابق الحرفي فقط.',
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                child: Row(
                  children: [
                    Text(
                      '${_results.length} نتيجة',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'مرتبة حسب الأقرب للاسم الذي كتبته',
                      style: TextStyle(
                        color: Colors.white.withOpacity(.42),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 130),
              sliver: SliverGrid.builder(
                itemCount: _results.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 16,
                  childAspectRatio: .52,
                ),
                itemBuilder: (_, i) {
                  final item = _results[i];
                  return MediaPosterCard(
                    item: item,
                    width: double.infinity,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => DetailsScreen(item: item)),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
