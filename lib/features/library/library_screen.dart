import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/image_cache.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/media_item.dart';
import '../../data/stores/download_store.dart';
import '../../providers.dart';
import '../../widgets/app_notice.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/media_card.dart';
import '../../widgets/network_image.dart';
import '../../widgets/section_header.dart';
import '../details/details_screen.dart';
import '../player/player_screen.dart';
import 'app_settings_screen.dart';
import 'subtitle_settings_screen.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    final downloads = ref.watch(downloadProvider);
    final favorites = library.favoriteItems();
    final later = library.watchLaterItems();

    return Scaffold(
      appBar: AppBar(title: const Text('مكتبتي'), centerTitle: false, backgroundColor: Colors.transparent),
      body: ListView(
        key: const PageStorageKey('library-scroll'),
        padding: const EdgeInsets.only(bottom: 130),
        children: [
          const SectionHeader(title: 'المفضلة', subtitle: 'الأعمال التي حفظتها للوصول السريع'),
          if (favorites.isEmpty)
            const SizedBox(height: 170, child: EmptyState(icon: Icons.bookmark_border_rounded, title: 'مفضلتك فارغة', message: 'احفظ أي فيلم أو مسلسل حتى يرجع هنا.'))
          else
            _Rail(items: favorites, library: library, showProgress: false),
          const SectionHeader(title: 'مكتبتي', subtitle: 'تنزيلاتك وقوائمك وإعدادات المشاهدة'),
          _LibraryQuickGrid(
            downloadsCount: downloads.items.length + downloads.activeItems.length,
            laterCount: later.length,
            onDownloads: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _DownloadsScreen())),
            onLater: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _WatchLaterScreen())),
            onSubtitles: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SubtitleSettingsScreen())),
          ),
          const SectionHeader(title: 'التطبيق'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: DecoratedBox(
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(.06))),
              child: Column(children: [
                _SettingTile(
                  icon: Icons.settings_rounded,
                  title: 'إعدادات التطبيق',
                  subtitle: 'اللغة، خط التطبيق وخيارات الواجهة',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AppSettingsScreen())),
                ),
                Divider(height: 1, indent: 62, color: Colors.white.withOpacity(.06)),
                _SettingTile(
                  icon: Icons.subtitles_rounded,
                  title: 'إعدادات الترجمة',
                  subtitle: 'الخط، الألوان، الحواف والخلفية',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SubtitleSettingsScreen())),
                ),
                Divider(height: 1, indent: 62, color: Colors.white.withOpacity(.06)),
                _SettingTile(
                  icon: Icons.delete_sweep_outlined,
                  title: 'مسح الكاش',
                  subtitle: 'يمسح الصور والبيانات المؤقتة فقط',
                  onTap: () async {
                    await CinematyImageCacheManager.instance.emptyCache();
                    await ref.read(apiProvider).clearApiCache();
                    if (context.mounted) {
                      AppNotice.show(context, title: 'تم مسح الكاش', message: 'لن تتأثر التنزيلات أو المفضلة.', type: AppNoticeType.success);
                    }
                  },
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryQuickGrid extends StatelessWidget {
  const _LibraryQuickGrid({required this.downloadsCount, required this.laterCount, required this.onDownloads, required this.onLater, required this.onSubtitles});
  final int downloadsCount, laterCount;
  final VoidCallback onDownloads, onLater, onSubtitles;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
        child: Row(children: [
          Expanded(child: _QuickCard(icon: Icons.download_for_offline_rounded, title: 'التنزيلات', subtitle: '$downloadsCount عنصر', onTap: onDownloads)),
          const SizedBox(width: 10),
          Expanded(child: _QuickCard(icon: Icons.watch_later_rounded, title: 'مشاهدة لاحقاً', subtitle: '$laterCount عمل', onTap: onLater)),
          const SizedBox(width: 10),
          Expanded(child: _QuickCard(icon: Icons.closed_caption_rounded, title: 'الترجمة', subtitle: 'تخصيص كامل', onTap: onSubtitles)),
        ]),
      );
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.white.withOpacity(.06))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 26),
            const SizedBox(height: 14),
            Text(title, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
            const SizedBox(height: 3),
            Text(subtitle, maxLines: 1, style: TextStyle(color: Colors.white.withOpacity(.42), fontSize: 10.5)),
          ]),
        ),
      );
}

class _Rail extends StatelessWidget {
  const _Rail({required this.items, required this.library, this.showProgress = true});
  final List<MediaItem> items;
  final dynamic library;
  final bool showProgress;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 270,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) {
            final item = items[i];
            return MediaPosterCard(
              item: item,
              progress: showProgress ? library.cardProgress(item.id)?.ratio : null,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailsScreen(item: item))),
            );
          },
        ),
      );
}

class _DownloadsScreen extends ConsumerWidget {
  const _DownloadsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(downloadProvider);
    final completed = store.items;
    final active = store.activeItems;
    return Scaffold(
      appBar: AppBar(title: const Text('التنزيلات')),
      body: completed.isEmpty && active.isEmpty
          ? const EmptyState(icon: Icons.download_for_offline_outlined, title: 'ما عندك تنزيلات بعد')
          : CustomScrollView(
              slivers: [
                if (active.isNotEmpty) ...[
                  const SliverToBoxAdapter(child: SectionHeader(title: 'جاري التنزيل')),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                    sliver: SliverList.builder(
                      itemCount: active.length,
                      itemBuilder: (_, i) => Padding(
                        padding: EdgeInsets.only(bottom: i == active.length - 1 ? 0 : 10),
                        child: _ActiveDownloadCard(download: active[i]),
                      ),
                    ),
                  ),
                ],
                if (completed.isNotEmpty) ...[
                  const SliverToBoxAdapter(child: SectionHeader(title: 'تم التنزيل')),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 30),
                    sliver: SliverGrid.builder(
                      itemCount: completed.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 16, childAspectRatio: .52),
                      itemBuilder: (_, i) {
                        final d = completed[i];
                        return Stack(children: [
                          MediaPosterCard(item: d.media, width: double.infinity, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(media: d.media, localPath: d.localPath)))),
                          Positioned(
                            left: 4,
                            top: 4,
                            child: PopupMenuButton<String>(
                              onSelected: (v) { if (v == 'delete') store.remove(d.id); },
                              itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('حذف التنزيل'))],
                              icon: const Icon(Icons.more_horiz_rounded),
                            ),
                          ),
                        ]);
                      },
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _ActiveDownloadCard extends StatelessWidget {
  const _ActiveDownloadCard({required this.download});
  final ActiveDownload download;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(.07))),
        child: Row(children: [
          SizedBox(width: 62, height: 82, child: CinematyNetworkImage(url: download.media.posterUrl, borderRadius: BorderRadius.circular(13))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(download.media.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('${download.quality} • جاري التنزيل', style: TextStyle(color: Colors.white.withOpacity(.48), fontSize: 11)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(value: download.progress.clamp(0.0, 1.0).toDouble(), minHeight: 5, backgroundColor: Colors.white10),
            ),
          ])),
          const SizedBox(width: 10),
          Text('${(download.progress * 100).round()}٪', style: const TextStyle(fontWeight: FontWeight.w900)),
        ]),
      );
}

class _WatchLaterScreen extends ConsumerWidget {
  const _WatchLaterScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(libraryProvider).watchLaterItems();
    return Scaffold(
      appBar: AppBar(title: const Text('مشاهدة لاحقاً')),
      body: items.isEmpty
          ? const EmptyState(icon: Icons.watch_later_outlined, title: 'القائمة فارغة')
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
              itemCount: items.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 16, childAspectRatio: .52),
              itemBuilder: (_, i) => MediaPosterCard(item: items[i], width: double.infinity, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailsScreen(item: items[i])))),
            ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({required this.icon, required this.title, required this.subtitle, this.onTap});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: Colors.white.withOpacity(.055), borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(.42), fontSize: 11.5)),
        trailing: onTap == null ? null : const Icon(Icons.chevron_left_rounded),
      );
}
