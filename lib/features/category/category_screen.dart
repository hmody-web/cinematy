import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/category.dart';
import '../../data/models/media_item.dart';
import '../../providers.dart';
import '../../widgets/cinematy_top_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/media_card.dart';
import '../../widgets/shimmer.dart';
import '../details/details_screen.dart';
import '../library/library_screen.dart';

class CategoryScreen extends ConsumerStatefulWidget {
  const CategoryScreen({
    super.key,
    required this.category,
    this.initialItems = const <MediaItem>[],
  });
  final MediaCategory category;
  final List<MediaItem> initialItems;

  @override
  ConsumerState<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends ConsumerState<CategoryScreen> {
  final _controller = ScrollController();
  final _items = <MediaItem>[];
  int _page = 1;
  bool _loading = true;
  bool _more = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_listen);

    // كرت التصنيف يمرر نفس قائمة الأفلام التي كان يعرض أغلفتها.
    // بذلك أول Frame داخل التصنيف يحتوي الأفلام مباشرة ولا توجد أي رحلة API.
    final cached = widget.initialItems.isNotEmpty
        ? widget.initialItems
        : ref.read(apiProvider).categoryCachedVideos(widget.category.id);
    if (cached.isNotEmpty) {
      _items.addAll(cached);
      _loading = false;
      _page = 2;
    } else {
      // نفس endpoint الخاص بتطبيق Cinemana؛ إذا كان prefetch بالخلفية قد بدأ
      // للتو فسيستفيد من cache الذاكرة، وإلا يجلب الصفحة الأولى مباشرة.
      _load();
    }
  }

  void _listen() {
    if (_controller.hasClients &&
        _controller.offset > 24 &&
        _controller.position.extentAfter < 650 &&
        !_loading &&
        _more) {
      _load();
    }
  }

  Future<void> _load() async {
    if (_loading && _items.isNotEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final next = await ref.read(apiProvider).categoryVideos(
            widget.category.id,
            categoryTitle: widget.category.title,
            page: _page,
          );
      if (!mounted) return;
      final seen = _items.map((e) => e.id).toSet();
      setState(() {
        _items.addAll(next.where((e) => seen.add(e.id)));
        _page++;
        _more = next.isNotEmpty;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final downloads = ref.watch(downloadProvider);
    return Scaffold(
      appBar: CinematyTopBar(
        section: widget.category.title,
        downloadsCount: downloads.items.length + downloads.activeItems.length,
        onBack: () => Navigator.pop(context),
        onContinue: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ContinueWatchingScreen()),
        ),
        onDownloads: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DownloadsScreen()),
        ),
      ),
      body: _items.isEmpty && _loading
          ? const _InitialCategorySkeleton()
          : _items.isEmpty && _error != null
              ? EmptyState(title: 'تعذر تحميل هذا التصنيف', onRetry: _load)
              : GridView.builder(
                  controller: _controller,
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
                  cacheExtent: 1000,
                  itemCount: _items.length + (_loading ? 3 : 0),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 16,
                    childAspectRatio: .52,
                  ),
                  itemBuilder: (_, i) {
                    if (i >= _items.length) {
                      return const SkeletonPosterCard(width: double.infinity);
                    }
                    final item = _items[i];
                    return MediaPosterCard(
                      item: item,
                      width: double.infinity,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => DetailsScreen(item: item)),
                      ),
                    );
                  },
                ),
    );
  }
}

class _InitialCategorySkeleton extends StatelessWidget {
  const _InitialCategorySkeleton();

  @override
  Widget build(BuildContext context) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
        itemCount: 12,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 16,
          childAspectRatio: .52,
        ),
        itemBuilder: (_, __) => const SkeletonPosterCard(width: double.infinity),
      );
}
