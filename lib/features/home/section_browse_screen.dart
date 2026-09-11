import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cinematy/core/navigation/cinematy_page_route.dart';
import '../../data/models/media_item.dart';
import '../../providers.dart';
import '../../widgets/cinematy_top_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/media_card.dart';
import '../../widgets/shimmer.dart';
import '../details/details_screen.dart';
import '../library/library_screen.dart';

enum SectionBrowseKind { group, newlyAdded, collection }

class SectionBrowseScreen extends ConsumerStatefulWidget {
  const SectionBrowseScreen({
    super.key,
    required this.title,
    required this.id,
    required this.kind,
    this.initialItems = const <MediaItem>[],
  });

  final String title;
  final String id;
  final SectionBrowseKind kind;
  final List<MediaItem> initialItems;

  @override
  ConsumerState<SectionBrowseScreen> createState() => _SectionBrowseScreenState();
}

class _SectionBrowseScreenState extends ConsumerState<SectionBrowseScreen> {
  final _controller = ScrollController();
  final _items = <MediaItem>[];
  int _page = 1;
  bool _loading = false;
  bool _more = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _items.addAll(widget.initialItems);
    _controller.addListener(_listen);
    _load(reset: widget.initialItems.isEmpty);
  }

  void _listen() {
    if (_controller.hasClients &&
        _controller.position.extentAfter < 700 &&
        !_loading &&
        _more &&
        widget.kind == SectionBrowseKind.group) {
      _load();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items.clear();
        _page = 1;
      }
    });
    try {
      final api = ref.read(apiProvider);
      final List<MediaItem> next;
      switch (widget.kind) {
        case SectionBrowseKind.group:
          next = await api.groupVideos(widget.id, page: _page);
          break;
        case SectionBrowseKind.newlyAdded:
          next = await api.newlyAdded(refresh: reset);
          break;
        case SectionBrowseKind.collection:
          next = await api.collectionVideos(widget.id);
          break;
      }
      if (!mounted) return;
      final seen = _items.map((e) => e.id).toSet();
      setState(() {
        _items.addAll(next.where((e) => e.id.isNotEmpty && seen.add(e.id)));
        if (widget.kind == SectionBrowseKind.group) _page++;
        _more = widget.kind == SectionBrowseKind.group && next.isNotEmpty;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
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
        section: widget.title,
        downloadsCount: downloads.items.length + downloads.activeItems.length,
        onBack: () => Navigator.pop(context),
        onContinue: () => Navigator.push(context, CinematyPageRoute(builder: (_) => const ContinueWatchingScreen())),
        onDownloads: () => Navigator.push(context, CinematyPageRoute(builder: (_) => const DownloadsScreen())),
      ),
      body: _items.isEmpty && _loading
          ? const _SectionSkeleton()
          : _items.isEmpty
              ? EmptyState(
                  title: _error == null ? 'لا يوجد محتوى حالياً' : 'تعذر تحميل القسم',
                  message: _error == null ? '' : 'حاول مرة أخرى.',
                  onRetry: () => _load(reset: true),
                )
              : GridView.builder(
                  controller: _controller,
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
                  cacheExtent: 1000,
                  itemCount: _items.length + (_loading ? 3 : 0),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 16,
                    childAspectRatio: .52,
                  ),
                  itemBuilder: (_, i) {
                    if (i >= _items.length) return const SkeletonPosterCard(width: double.infinity);
                    final item = _items[i];
                    return MediaPosterCard(
                      item: item,
                      width: double.infinity,
                      onTap: () => Navigator.push(context, CinematyPageRoute(builder: (_) => DetailsScreen(item: item))),
                    );
                  },
                ),
    );
  }
}

class _SectionSkeleton extends StatelessWidget {
  const _SectionSkeleton();
  @override
  Widget build(BuildContext context) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
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
