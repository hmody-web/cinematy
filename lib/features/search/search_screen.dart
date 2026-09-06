import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/media_item.dart';
import '../../providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/media_card.dart';
import '../details/details_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> with AutomaticKeepAliveClientMixin {
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
    _debounce = Timer(const Duration(milliseconds: 360), () => _search(value));
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
      // نطلب البحث العام أولاً ثم نفصل أفلام/مسلسلات محلياً؛ بهذه الطريقة
      // لا تضيع نتائج إذا غيّر Cinemana طريقة تمييز movie/series في الـAPI.
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
    return Scaffold(
      appBar: AppBar(title: const Text('البحث'), centerTitle: false, backgroundColor: Colors.transparent),
      body: CustomScrollView(
        key: const PageStorageKey('search-scroll'),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
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
              height: 46,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                scrollDirection: Axis.horizontal,
                children: ['الكل', 'أفلام', 'مسلسلات'].map((f) => Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ChoiceChip(
                    selected: _filter == f,
                    label: Text(f),
                    selectedColor: AppColors.red.withOpacity(.35),
                    onSelected: (_) => _changeFilter(f),
                  ),
                )).toList(),
              ),
            ),
          ),
          if (_loading)
            const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator())))
          else if (_error != null)
            SliverFillRemaining(hasScrollBody: false, child: EmptyState(title: 'تعذر البحث', message: 'حاول مرة أخرى بعد قليل.', onRetry: () => _search(_controller.text)))
          else if (_controller.text.trim().length < 2)
            const SliverFillRemaining(hasScrollBody: false, child: EmptyState(icon: Icons.search_rounded, title: 'شنو تحب تشوف اليوم؟', message: 'اكتب حرفين أو أكثر وسنبحث لك في كامل مكتبة سينمانا.'))
          else if (_results.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: EmptyState(title: 'ما لقينا نتائج', message: 'جرّب الاسم بالعربية أو الإنجليزية. البحث يجرب أيضاً التهجئات القريبة تلقائياً.'))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 130),
              sliver: SliverGrid.builder(
                itemCount: _results.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 16, childAspectRatio: .52),
                itemBuilder: (_, i) {
                  final item = _results[i];
                  return MediaPosterCard(item: item, width: double.infinity, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailsScreen(item: item))));
                },
              ),
            ),
        ],
      ),
    );
  }
}
