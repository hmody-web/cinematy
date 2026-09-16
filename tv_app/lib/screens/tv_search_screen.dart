import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models/media_item.dart';
import '../tv_context.dart';
import '../tv_focus.dart';
import '../tv_image.dart';
import '../tv_nav.dart';
import '../tv_platform_ui.dart';
import 'tv_details_screen.dart';

class TvSearchScreen extends StatefulWidget {
  const TvSearchScreen({super.key});

  @override
  State<TvSearchScreen> createState() => _TvSearchScreenState();
}

class _TvSearchScreenState extends State<TvSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<MediaItem> _items = const [];
  bool _loading = false;
  int _serial = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value));
  }

  Future<void> _search(String query) async {
    final q = query.trim();
    if (q.length < 2) {
      if (mounted) setState(() => _items = const []);
      return;
    }
    final serial = ++_serial;
    setState(() => _loading = true);
    try {
      final result = await tvApi.searchAll(q, page: 1);
      if (!mounted || serial != _serial) return;
      setState(() {
        _items = result.take(80).toList(growable: false);
        _loading = false;
      });
    } catch (_) {
      if (!mounted || serial != _serial) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
          child: TextField(
            autofocus: true,
            controller: _controller,
            onChanged: _changed,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 18),
            decoration: InputDecoration(
              hintText: 'ابحث عن فيلم أو مسلسل',
              prefixIcon: const Icon(Icons.search_rounded, size: 24),
              filled: true,
              fillColor: Colors.white.withOpacity(.07),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _items.isEmpty
              ? const Center(
                  child: Text('اكتب كلمتين أو أكثر للبحث', style: TextStyle(fontSize: 14, color: Colors.white54)),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 30),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: tvIsWindowsDesktop ? 286 : 232,
                    childAspectRatio: tvIsWindowsDesktop ? .62 : .61,
                    crossAxisSpacing: tvIsWindowsDesktop ? 24 : 20,
                    mainAxisSpacing: tvIsWindowsDesktop ? 28 : 22,
                  ),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return TvFocus(
                      onPressed: () => Navigator.of(context).push(tvRoute(TvDetailsScreen(item: item))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: TvImage(item.posterUrl, cacheWidth: 340)),
                          const SizedBox(height: 10),
                          Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, textDirection: TextDirection.rtl, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
