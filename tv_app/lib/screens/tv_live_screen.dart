
import 'package:flutter/material.dart';

import '../features/tv/tv_models.dart';
import '../features/tv/xtream_tv_service.dart';
import '../tv_context.dart';
import '../tv_focus.dart';
import '../tv_image.dart';
import '../tv_nav.dart';
import '../tv_theme.dart';
import '../tv_platform_ui.dart';
import 'tv_live_player_screen.dart';

class TvLiveScreen extends StatefulWidget {
  const TvLiveScreen({super.key});

  @override
  State<TvLiveScreen> createState() => _TvLiveScreenState();
}

class _TvLiveScreenState extends State<TvLiveScreen> {
  final XtreamTvService _service = XtreamTvService();
  List<TvCategory> _allCategories = const [];
  List<TvChannel> _channels = const [];
  String _server = 'N';
  String? _selectedId;
  bool _loading = true;
  String? _error;

  static const _servers = <String>['N', 'G', 'F'];

  @override
  void initState() {
    super.initState();
    _load();
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

  String? _serverOf(String value) {
    final upper = value.toUpperCase();
    for (final server in _servers) {
      if (RegExp('(^|[^A-Z])$server([^A-Z]|\$)').hasMatch(upper) ||
          upper.contains('SERVER $server') ||
          upper.contains('سيرفر $server')) {
        return server;
      }
    }
    return null;
  }

  List<TvCategory> get _visibleCategories {
    final tagged = _allCategories.where((category) {
      final marker = _serverOf(category.name);
      if (_server == 'N' && _isBein(category.name)) return true;
      return marker == _server;
    }).toList(growable: false);

    final source = tagged.isEmpty ? _allCategories : tagged;
    return [...source]..sort((a, b) {
      final ab = _isBein(a.name);
      final bb = _isBein(b.name);
      if (ab != bb) return ab ? -1 : 1;
      return a.name.compareTo(b.name);
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _allCategories = (await _service.getCategories())
          .where((category) => !_isIntro(category.name))
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

  Future<void> _selectServer(String server) async {
    if (_server == server) return;
    setState(() {
      _server = server;
      _loading = true;
    });
    await _selectFirstCategory();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _selectFirstCategory() async {
    final categories = _visibleCategories;
    if (categories.isEmpty) {
      _selectedId = null;
      _channels = const [];
      return;
    }
    await _select(categories.first, force: true);
  }

  Future<void> _select(TvCategory category, {bool force = false}) async {
    if (!force && _selectedId == category.id) return;
    setState(() {
      _selectedId = category.id;
      _loading = true;
    });
    try {
      final channels = (await _service.getChannels(categoryId: category.id))
          .where((channel) => !_isIntro(channel.name))
          .where((channel) {
            final marker = _serverOf(channel.name);
            if (_server == 'N' && _isBein(channel.name)) return true;
            return marker == null || marker == _server;
          })
          .toList(growable: false);
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
      ..sort((a, b) => _channelOrder(a.title).compareTo(_channelOrder(b.title)));
    return groups;
  }

  int _channelOrder(String value) {
    final normalized = value.toLowerCase();
    final bein = normalized.contains('bein') ||
        normalized.contains('بين') ||
        normalized.contains('بي إن');
    final number = int.tryParse(
          RegExp(r'(\d+)').firstMatch(normalized)?.group(1) ?? '',
        ) ??
        999;
    return (bein ? 0 : 10000) + number;
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

  Future<void> _openGroup(_ChannelGroup group) async {
    if (group.channels.length == 1) {
      _play(group.channels.first);
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
            itemCount: group.channels.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final channel = group.channels[index];
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
                        child: Text(channel.name, textAlign: TextAlign.right),
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
    if (picked != null) _play(picked);
  }

  void _play(TvChannel tapped) {
    final group = _groups.firstWhere(
      (group) => group.channels.any((channel) => channel.id == tapped.id),
      orElse: () => _ChannelGroup(tapped.groupKey, [tapped]),
    );
    final playback = _smoothVariantFor(group.channels);
    final playlist = _groups.map((g) => _smoothVariantFor(g.channels)).toList(growable: false);
    final index = playlist.indexWhere((channel) => channel.groupKey == playback.groupKey);

    Navigator.of(context).push(
      tvVideoRoute(
        TvLivePlayerScreen(
          channel: playback,
          url: _service.streamUrl(playback),
          channels: playlist,
          initialIndex: index < 0 ? 0 : index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: tvChannelFavorites,
      builder: (context, _) {
        final categories = _visibleCategories;
        final favorites = tvChannelFavorites.items;
        final groups = _groups;

        return Column(
          children: [
            Padding(
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
                  ..._servers.map((server) {
                    final selected = _server == server;
                    return Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: TvFocus(
                        onPressed: () => _selectServer(server),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                          decoration: BoxDecoration(
                            color: selected ? TvColors.red : Colors.white.withOpacity(.06),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'سيرفر $server',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            if (favorites.isNotEmpty)
              SizedBox(
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
                        onPressed: () => _play(channel),
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
                                child: TvImage(channel.icon, cacheWidth: 100, borderRadius: 8),
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
            if (categories.isNotEmpty)
              SizedBox(
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
                      onPressed: () => _select(category),
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
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _error != null
                  ? Center(child: Text(_error!))
                  : GridView.builder(
                      cacheExtent: 650,
                      padding: const EdgeInsets.fromLTRB(22, 12, 22, 30),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: tvIsWindowsDesktop ? 360 : 310,
                        mainAxisExtent: tvIsWindowsDesktop ? 205 : 174,
                        crossAxisSpacing: tvIsWindowsDesktop ? 20 : 16,
                        mainAxisSpacing: tvIsWindowsDesktop ? 20 : 16,
                      ),
                      itemCount: groups.length,
                      itemBuilder: (context, index) {
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
                                  child: TvImage(channel.icon, cacheWidth: 180, borderRadius: 10),
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
                    ),
            ),
          ],
        );
      },
    );
  }
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
