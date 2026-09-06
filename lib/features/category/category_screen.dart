import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/category.dart';
import '../../data/models/media_item.dart';
import '../../providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/media_card.dart';
import '../details/details_screen.dart';

class CategoryScreen extends ConsumerStatefulWidget {
  const CategoryScreen({super.key, required this.category});
  final MediaCategory category;

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
    _load();
  }

  void _listen() {
    if (_controller.position.extentAfter < 600 && !_loading && _more) _load();
  }

  Future<void> _load() async {
    if (_loading && _items.isNotEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      final next = await ref.read(apiProvider).categoryVideos(widget.category.id, page: _page);
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
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.category.title), centerTitle: false),
      body: _items.isEmpty && _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty && _error != null
              ? EmptyState(title: 'تعذر تحميل هذا التصنيف', onRetry: _load)
              : GridView.builder(
                  controller: _controller,
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
                  cacheExtent: 1000,
                  itemCount: _items.length + (_loading ? 1 : 0),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 16, childAspectRatio: .52),
                  itemBuilder: (_, i) {
                    if (i == _items.length) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                    final item = _items[i];
                    return MediaPosterCard(item: item, width: double.infinity, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailsScreen(item: item))));
                  },
                ),
    );
  }
}
