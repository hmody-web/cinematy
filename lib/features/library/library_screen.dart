import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/image_cache.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/download_item.dart';
import '../../data/models/media_item.dart';
import '../../data/stores/download_store.dart';
import '../../providers.dart';
import '../../widgets/app_notice.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/cinematy_top_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/media_card.dart';
import '../../widgets/network_image.dart';
import '../../widgets/section_header.dart';
import '../auth/account_screen.dart';
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
      appBar: CinematyTopBar(
        section: 'مكتبتي',
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
      body: ListView(
        key: const PageStorageKey('library-scroll'),
        padding: const EdgeInsets.only(bottom: 130),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: _LibraryAccountCard(),
          ),
          const SectionHeader(
            title: 'مكتبتي',
            subtitle: 'تنزيلاتك وقوائمك وإعدادات المشاهدة',
          ),
          _LibraryQuickGrid(
            downloadsCount: downloads.items.length + downloads.activeItems.length,
            laterCount: later.length,
            favoritesCount: favorites.length,
            onDownloads: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DownloadsScreen()),
            ),
            onLater: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WatchLaterScreen()),
            ),
            onFavorites: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FavoritesScreen()),
            ),
          ),
          const SectionHeader(title: 'حول سينماتي'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: _AboutCinematyCard(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutCinematyScreen()),
              ),
            ),
          ),
          const SectionHeader(title: 'التطبيق'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(.06)),
              ),
              child: Column(
                children: [
                  _SettingTile(
                    icon: Icons.settings_rounded,
                    title: 'إعدادات التطبيق',
                    subtitle: 'اللغة، خط التطبيق وخيارات الواجهة',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AppSettingsScreen()),
                    ),
                  ),
                  Divider(height: 1, indent: 62, color: Colors.white.withOpacity(.06)),
                  _SettingTile(
                    icon: Icons.subtitles_rounded,
                    title: 'إعدادات الترجمة',
                    subtitle: 'الخط، الألوان، الحواف والخلفية',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SubtitleSettingsScreen()),
                    ),
                  ),
                  Divider(height: 1, indent: 62, color: Colors.white.withOpacity(.06)),
                  _SettingTile(
                    icon: Icons.delete_sweep_outlined,
                    title: 'مسح الكاش',
                    subtitle: 'يمسح الصور والبيانات المؤقتة فقط',
                    onTap: () => _confirmClearCache(context, ref),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearCache(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        title: const Row(
          children: [
            Icon(Icons.cleaning_services_rounded),
            SizedBox(width: 10),
            Text('مسح الكاش؟'),
          ],
        ),
        content: const Text(
          'سيتم حذف الصور والبيانات المؤقتة فقط. التنزيلات والمفضلة وسجل المشاهدة لن تتأثر.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('مسح الآن'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await CinematyImageCacheManager.instance.emptyCache();
    await ref.read(apiProvider).clearApiCache();
    ref.invalidate(homeFeedProvider);
    ref.invalidate(categoriesProvider);
    if (context.mounted) {
      AppNotice.show(
        context,
        title: 'تم مسح الكاش',
        message: 'تم تنظيف الملفات المؤقتة بنجاح.',
        type: AppNoticeType.success,
      );
    }
  }
}

class _AboutCinematyCard extends StatelessWidget {
  const _AboutCinematyCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.035),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(.065)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.045),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const BrandLogo(size: 34),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'حول سينماتي',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'معلومات التطبيق والمطور',
                      style: TextStyle(
                        color: Colors.white.withOpacity(.46),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left_rounded, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeveloperCard extends StatelessWidget {
  const _DeveloperCard();

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  Colors.white.withOpacity(.065),
                  AppColors.redBright.withOpacity(.035),
                  Colors.white.withOpacity(.025),
                ],
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withOpacity(.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 74,
                      height: 74,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(.18)),
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/branding/developer_mohammed_alsaray.jpeg',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const BrandLogo(size: 40),
                          const SizedBox(height: 6),
                          Text(
                            'تجربة سينمائية عربية سريعة، مصممة لتضع المحتوى والمشاهدة والتنزيلات في مكان واحد.',
                            style: TextStyle(
                              color: Colors.white.withOpacity(.58),
                              fontSize: 11.2,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'المطور • محمد السراي',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 7),
                Text(
                  'تم تطوير سينماتي بعناية ليجمع السرعة والبساطة وتجربة مشاهدة عملية، مع اهتمام بالتفاصيل الصغيرة التي تجعل التنقل والمشاهدة والتنزيل أكثر سلاسة ووضوحاً.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(.68),
                    fontSize: 12.4,
                    height: 1.65,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(
                      'للتواصل',
                      style: TextStyle(
                        color: Colors.white.withOpacity(.46),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () async {
                        final uri = Uri.parse('https://scrptaty.com');
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.background,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: const Icon(Icons.public_rounded, size: 18),
                      label: const Text(
                        'سكربتاتي',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class _LibraryAccountCard extends StatelessWidget {
  const _LibraryAccountCard();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        final signedIn = user != null;
        final name = user?.displayName?.trim();
        final email = user?.email?.trim();

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AccountScreen()),
            ),
            borderRadius: BorderRadius.circular(28),
            child: Ink(
              padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    Colors.white.withOpacity(.062),
                    AppColors.redBright.withOpacity(signedIn ? .045 : .075),
                    Colors.white.withOpacity(.026),
                  ],
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withOpacity(.075)),
              ),
              child: Row(
                children: [
                  _LibraryAccountAvatar(user: user),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                signedIn
                                    ? (name?.isNotEmpty == true ? name! : 'حساب سينماتي')
                                    : 'سجّل دخولك إلى سينماتي',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            if (signedIn) ...[
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.verified_rounded,
                                size: 16,
                                color: AppColors.success,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          signedIn
                              ? (email?.isNotEmpty == true
                                  ? email!
                                  : 'حساب Google متصل')
                              : 'الوصول إلى حسابك وميزات سينماتي',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(.48),
                            fontSize: 10.8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: signedIn
                          ? AppColors.success.withOpacity(.075)
                          : AppColors.redBright.withOpacity(.09),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: signedIn
                            ? AppColors.success.withOpacity(.16)
                            : AppColors.redBright.withOpacity(.16),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          signedIn ? Icons.person_rounded : Icons.login_rounded,
                          size: 14,
                          color: signedIn ? AppColors.success : AppColors.redBright,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          signedIn ? 'ملفي' : 'دخول',
                          style: TextStyle(
                            color: signedIn ? AppColors.success : AppColors.redBright,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LibraryAccountAvatar extends StatelessWidget {
  const _LibraryAccountAvatar({required this.user});

  final User? user;

  @override
  Widget build(BuildContext context) {
    final photo = user?.photoURL?.trim();
    return Container(
      width: 54,
      height: 54,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: user == null
            ? null
            : const LinearGradient(
                colors: [AppColors.redBright, Color(0xFFFF8A80)],
              ),
        color: user == null ? Colors.white.withOpacity(.055) : null,
        border: user == null
            ? Border.all(color: Colors.white.withOpacity(.07))
            : null,
      ),
      child: ClipOval(
        child: ColoredBox(
          color: AppColors.surfaceHigh,
          child: photo?.isNotEmpty == true
              ? Image.network(
                  photo!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _fallback(),
                )
              : _fallback(),
        ),
      ),
    );
  }

  Widget _fallback() => Icon(
        user == null ? Icons.person_outline_rounded : Icons.person_rounded,
        size: 25,
        color: Colors.white.withOpacity(.78),
      );
}

class _LibraryQuickGrid extends StatelessWidget {
  const _LibraryQuickGrid({
    required this.downloadsCount,
    required this.laterCount,
    required this.onDownloads,
    required this.onLater,
    required this.favoritesCount,
    required this.onFavorites,
  });

  final int downloadsCount;
  final int laterCount;
  final int favoritesCount;
  final VoidCallback onDownloads;
  final VoidCallback onLater;
  final VoidCallback onFavorites;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
        child: Row(
          children: [
            Expanded(
              child: _QuickCard(
                icon: Icons.download_for_offline_rounded,
                title: 'التنزيلات',
                subtitle: '$downloadsCount عنصر',
                onTap: onDownloads,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickCard(
                icon: Icons.watch_later_rounded,
                title: 'مشاهدة لاحقاً',
                subtitle: '$laterCount عمل',
                onTap: onLater,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickCard(
                icon: Icons.bookmark_rounded,
                title: 'المفضلة',
                subtitle: '$favoritesCount عمل',
                onTap: onFavorites,
              ),
            ),
          ],
        ),
      );
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 26),
              const SizedBox(height: 14),
              Text(
                title,
                maxLines: 1,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                style: TextStyle(color: Colors.white.withOpacity(.42), fontSize: 10.5),
              ),
            ],
          ),
        ),
      );
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.items,
    required this.library,
    this.showProgress = true,
  });

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
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DetailsScreen(item: item)),
              ),
            );
          },
        ),
      );
}

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(downloadProvider);
    final completed = store.items;
    final active = store.activeItems;
    return Scaffold(
      appBar: CinematyTopBar(
        section: 'التنزيلات',
        showQuickActions: false,
        onBack: () => Navigator.pop(context),
      ),
      body: completed.isEmpty && active.isEmpty
          ? const EmptyState(
              icon: Icons.download_for_offline_outlined,
              title: 'ما عندك تنزيلات بعد',
            )
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
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 16,
                        childAspectRatio: .52,
                      ),
                      itemBuilder: (_, i) {
                        final d = completed[i];
                        return _DownloadedPoster(
                          download: d,
                          onPlay: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PlayerScreen(
                                media: d.media,
                                localPath: d.localPath,
                              ),
                            ),
                          ),
                          onDelete: () => store.remove(d.id),
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

class _DownloadedPoster extends StatelessWidget {
  const _DownloadedPoster({
    required this.download,
    required this.onPlay,
    required this.onDelete,
  });

  final DownloadItem download;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        children: [
          MediaPosterCard(
            item: download.media,
            width: double.infinity,
            onTap: onPlay,
          ),
          if ((download.media.episode ?? 0) > 0)
            Positioned(
              right: 7,
              top: 7,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.78),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withOpacity(.16)),
                ),
                child: Text(
                  'الحلقة ${download.media.episode}',
                  style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          Positioned(
            left: 4,
            top: 4,
            child: PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'delete', child: Text('حذف التنزيل')),
              ],
              icon: const Icon(Icons.more_horiz_rounded),
            ),
          ),
          if (download.subtitles.isNotEmpty)
            Positioned(
              right: 7,
              bottom: 43,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.72),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.subtitles_rounded, size: 15),
              ),
            ),
        ],
      );
}

class _ActiveDownloadCard extends StatelessWidget {
  const _ActiveDownloadCard({required this.download});
  final ActiveDownload download;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(.07)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 62,
              height: 82,
              child: CinematyNetworkImage(
                url: download.media.posterUrl,
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    download.media.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${download.quality} • جاري التنزيل',
                    style: TextStyle(color: Colors.white.withOpacity(.48), fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: LinearProgressIndicator(
                      value: download.progress.clamp(0.0, 1.0).toDouble(),
                      minHeight: 5,
                      backgroundColor: Colors.white10,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${(download.progress * 100).round()}٪',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      );
}

class AboutCinematyScreen extends StatelessWidget {
  const AboutCinematyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CinematyTopBar(
        section: 'حول سينماتي',
        showQuickActions: false,
        onBack: () => Navigator.pop(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 34),
        children: const [
          _DeveloperCard(),
        ],
      ),
    );
  }
}

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(libraryProvider).favoriteItems();
    return Scaffold(
      appBar: CinematyTopBar(
        section: 'المفضلة',
        showQuickActions: false,
        onBack: () => Navigator.pop(context),
      ),
      body: items.isEmpty
          ? const EmptyState(
              icon: Icons.bookmark_border_rounded,
              title: 'المفضلة فارغة',
              message: 'الأعمال التي تحفظها في المفضلة ستظهر هنا.',
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
              itemCount: items.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 16,
                childAspectRatio: .52,
              ),
              itemBuilder: (_, i) => MediaPosterCard(
                item: items[i],
                width: double.infinity,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => DetailsScreen(item: items[i])),
                ),
              ),
            ),
    );
  }
}

class WatchLaterScreen extends ConsumerWidget {
  const WatchLaterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(libraryProvider).watchLaterItems();
    return Scaffold(
      appBar: CinematyTopBar(
        section: 'مشاهدة لاحقاً',
        showQuickActions: false,
        onBack: () => Navigator.pop(context),
      ),
      body: items.isEmpty
          ? const EmptyState(icon: Icons.watch_later_outlined, title: 'القائمة فارغة')
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
              itemCount: items.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 16,
                childAspectRatio: .52,
              ),
              itemBuilder: (_, i) => MediaPosterCard(
                item: items[i],
                width: double.infinity,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => DetailsScreen(item: items[i])),
                ),
              ),
            ),
    );
  }
}

class ContinueWatchingScreen extends ConsumerWidget {
  const ContinueWatchingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(libraryProvider);
    final items = store.continueWatching();
    return Scaffold(
      appBar: CinematyTopBar(
        section: 'متابعة المشاهدة',
        showQuickActions: false,
        onBack: () => Navigator.pop(context),
      ),
      body: items.isEmpty
          ? const EmptyState(
              icon: Icons.play_circle_outline_rounded,
              title: 'لا توجد مشاهدة غير مكتملة',
              message: 'عندما توقف في منتصف فيلم أو حلقة ستظهر هنا.',
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
              itemCount: items.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 16,
                childAspectRatio: .52,
              ),
              itemBuilder: (_, i) {
                final item = items[i];
                return MediaPosterCard(
                  item: item,
                  width: double.infinity,
                  progress: store.cardProgress(item.id)?.ratio,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => DetailsScreen(item: item)),
                  ),
                );
              },
            ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.055),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: Colors.white.withOpacity(.42), fontSize: 11.5),
        ),
        trailing: onTap == null ? null : const Icon(Icons.chevron_left_rounded),
      );
}
