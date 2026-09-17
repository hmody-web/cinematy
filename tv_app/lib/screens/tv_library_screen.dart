import 'dart:async';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';

import '../data/models/media_item.dart';
import '../features/activation/tv_activation_service.dart';
import '../tv_context.dart';
import '../tv_downloads.dart';
import '../tv_focus.dart';
import '../tv_image.dart';
import '../tv_nav.dart';
import '../tv_platform_ui.dart';
import '../tv_theme.dart';
import 'tv_details_screen.dart';
import 'tv_player_screen.dart';

class TvLibraryScreen extends StatelessWidget {
  const TvLibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([tvLibrary, tvDownloads, tvDisplayPreferences, TvActivationService.instance.subscription]),
      builder: (context, _) {
        final downloads = tvDownloads.items;
        final activeDownloads = tvDownloads.activeItems;
        final favorites = tvLibrary.favorites;
        final later = tvLibrary.watchLater;
        final continueItems = tvLibrary.continueWatching;
        final subscription = TvActivationService.instance.subscription.value;

        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 38),
          children: [
            const Text('مكتبتي', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text(
              'كل ما حفظته أو بدأت بمشاهدته في مكان واحد',
              style: TextStyle(fontSize: 13, color: TvColors.textMuted),
            ),
            const SizedBox(height: 18),
            _SubscriptionCard(subscription: subscription),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _LibraryFeatureCard(
                    icon: Icons.download_done_rounded,
                    title: 'التنزيلات',
                    count: downloads.length + activeDownloads.length,
                    onPressed: () => Navigator.of(context).push(
                      tvRoute(_DownloadsScreen(items: downloads)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _LibraryFeatureCard(
                    icon: Icons.favorite_rounded,
                    title: 'المفضلة',
                    count: favorites.length,
                    onPressed: () => Navigator.of(context).push(
                      tvRoute(_MediaCollectionScreen(title: 'المفضلة', items: favorites)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _LibraryFeatureCard(
                    icon: Icons.bookmark_rounded,
                    title: 'مشاهدة لاحقاً',
                    count: later.length,
                    onPressed: () => Navigator.of(context).push(
                      tvRoute(_MediaCollectionScreen(title: 'مشاهدة لاحقاً', items: later)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (activeDownloads.isNotEmpty)
              _ActiveDownloadsRow(items: activeDownloads),
            _MediaRow(title: 'أكمل المشاهدة', items: continueItems),
            _MediaRow(title: 'المفضلة', items: favorites),
            _MediaRow(title: 'مشاهدة لاحقاً', items: later),
            if (downloads.isNotEmpty)
              _DownloadsRow(items: downloads),
            const SizedBox(height: 18),
            _DisplaySettingsCard(
              hideScoreboard: tvDisplayPreferences.hideScoreboard,
              startInLiveTv: tvDisplayPreferences.startInLiveTv,
              windowsFullscreen: tvDisplayPreferences.windowsFullscreen,
              lowEndLiveOptimization: tvDisplayPreferences.lowEndLiveOptimization,
            ),
            const SizedBox(height: 18),
            const _DeveloperCard(),
          ],
        );
      },
    );
  }
}


class _DisplaySettingsCard extends StatelessWidget {
  const _DisplaySettingsCard({
    required this.hideScoreboard,
    required this.startInLiveTv,
    required this.windowsFullscreen,
    required this.lowEndLiveOptimization,
  });

  final bool hideScoreboard;
  final bool startInLiveTv;
  final bool windowsFullscreen;
  final bool lowEndLiveOptimization;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF17191E), Color(0xFF101216)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.20),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            textDirection: TextDirection.rtl,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: TvColors.red.withOpacity(.13),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.tune_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'إعدادات العرض والتلفاز',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'خصص طريقة بدء سينماتي وشكل قسم التلفاز',
                      style: TextStyle(fontSize: 12, color: TvColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          _SettingsToggleRow(
            icon: Icons.scoreboard_rounded,
            title: 'إخفاء شاشة السكوربورد',
            subtitle: 'إخفاء غلاف مباريات اليوم بالكامل من قسم التلفاز',
            value: hideScoreboard,
            onPressed: () => unawaited(
              tvDisplayPreferences.setHideScoreboard(!hideScoreboard),
            ),
          ),
          const SizedBox(height: 10),
          _SettingsToggleRow(
            icon: Icons.live_tv_rounded,
            title: 'فتح قسم التلفاز عند التشغيل',
            subtitle: 'يجعل قسم التلفاز هو الصفحة الرئيسية عند تشغيل التطبيق',
            value: startInLiveTv,
            onPressed: () => unawaited(
              tvDisplayPreferences.setStartInLiveTv(!startInLiveTv),
            ),
          ),
          const SizedBox(height: 10),
          _SettingsToggleRow(
            icon: Icons.speed_rounded,
            title: 'تحسين البث المباشر للأجهزة الضعيفة',
            subtitle: 'يخفف حمل الواجهة والبيانات أثناء مشاهدة القنوات بدون تقليل جودة البث',
            value: lowEndLiveOptimization,
            onPressed: () => unawaited(
              tvDisplayPreferences.setLowEndLiveOptimization(!lowEndLiveOptimization),
            ),
          ),
          if (tvIsWindowsDesktop) ...[
            const SizedBox(height: 10),
            _SettingsToggleRow(
              icon: windowsFullscreen
                  ? Icons.fullscreen_rounded
                  : Icons.fullscreen_exit_rounded,
              title: 'ملء الشاشة في Windows',
              subtitle: windowsFullscreen
                  ? 'مفعّل — التطبيق يغطي الشاشة بالكامل'
                  : 'متوقف — نافذة سينماتي مصغرة وبدون إطارات Windows',
              value: windowsFullscreen,
              onPressed: () => unawaited(
                tvDisplayPreferences.setWindowsFullscreen(!windowsFullscreen),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SettingsToggleRow extends StatelessWidget {
  const _SettingsToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TvFocus(
      onPressed: onPressed,
      borderRadius: 14,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: value ? TvColors.red.withOpacity(.085) : Colors.white.withOpacity(.035),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: value ? TvColors.red.withOpacity(.32) : Colors.white.withOpacity(.07),
          ),
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: value ? TvColors.red.withOpacity(.16) : Colors.white.withOpacity(.055),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 22,
                color: value ? Colors.white : Colors.white60,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: TvColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            _SettingsSwitch(value: value),
          ],
        ),
      ),
    );
  }
}

class _SettingsSwitch extends StatelessWidget {
  const _SettingsSwitch({required this.value});
  final bool value;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: 54,
      height: 30,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: value ? TvColors.red : Colors.white12,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: value ? TvColors.red : Colors.white12),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: value ? Alignment.centerLeft : Alignment.centerRight,
        child: Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: Colors.black38, blurRadius: 5, offset: Offset(0, 2)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({required this.subscription});
  final TvActivationResult? subscription;

  String _two(int value) => value.toString().padLeft(2, '0');

  String _dateTime(DateTime? value) {
    if (value == null) return 'غير محدد';
    final d = value.toLocal();
    return '${d.year}/${_two(d.month)}/${_two(d.day)}  •  ${_two(d.hour)}:${_two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final active = subscription?.ok == true;
    final expiry = subscription?.expiresAt;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            active ? const Color(0xFF17241D) : const Color(0xFF271717),
            TvColors.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? const Color(0x3358D68D) : const Color(0x33FF5A5A),
        ),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: active ? const Color(0x2058D68D) : const Color(0x20FF5A5A),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              active ? Icons.verified_rounded : Icons.error_outline_rounded,
              color: active ? const Color(0xFF6DE39B) : Colors.redAccent,
              size: 29,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('الاشتراك', style: TextStyle(fontSize: 13, color: TvColors.textMuted, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 9),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: active ? const Color(0x2058D68D) : const Color(0x20FF5A5A),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        active ? 'فعال' : 'غير فعال',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: active ? const Color(0xFF6DE39B) : Colors.redAccent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  subscription?.name?.trim().isNotEmpty == true ? subscription!.name! : 'سينماتي TV',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          Container(width: 1, height: 48, color: Colors.white10),
          const SizedBox(width: 18),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('صالح إلى', style: TextStyle(fontSize: 12, color: TvColors.textMuted, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                _dateTime(expiry),
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: .3),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LibraryFeatureCard extends StatelessWidget {
  const _LibraryFeatureCard({
    required this.icon,
    required this.title,
    required this.count,
    required this.onPressed,
  });
  final IconData icon;
  final String title;
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TvFocus(
      onPressed: onPressed,
      child: Container(
        height: 116,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [TvColors.surface2, TvColors.surface],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: TvColors.red.withOpacity(.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 25, color: Colors.white),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 5),
                  Text('$count عنصر', style: const TextStyle(fontSize: 12, color: TvColors.textMuted)),
                ],
              ),
            ),
            const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

class _MediaRow extends StatelessWidget {
  const _MediaRow({required this.title, required this.items});
  final String title;
  final List<MediaItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final cardWidth = tvIsWindowsDesktop
        ? tvDesktopValue(context, tv: 188, windows: 224)
        : 188.0;
    final rowHeight = cardWidth * 1.48 + (tvIsWindowsDesktop ? 58 : 44);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          SizedBox(
            height: rowHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 18),
              itemBuilder: (context, index) {
                final item = items[index];
                final isContinue = title == 'أكمل المشاهدة';
                final resumeTitle = item.raw['_seriesTitle']?.toString().trim();
                final displayTitle = isContinue && resumeTitle != null && resumeTitle.isNotEmpty
                    ? resumeTitle
                    : item.title;
                final resumeSubtitle = isContinue &&
                        (item.season ?? 0) > 0 &&
                        (item.episode ?? 0) > 0
                    ? 'الموسم ${item.season} • الحلقة ${item.episode}'
                    : null;
                return SizedBox(
                  width: cardWidth,
                  child: TvFocus(
                    onPressed: () => Navigator.of(context).push(tvRoute(TvDetailsScreen(item: item))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: TvImage(item.posterUrl, cacheWidth: 320)),
                        const SizedBox(height: 7),
                        Text(displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                        if (resumeSubtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            resumeSubtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: TvColors.textMuted, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveDownloadsRow extends StatelessWidget {
  const _ActiveDownloadsRow({required this.items});

  final List<TvActiveDownload> items;

  @override
  Widget build(BuildContext context) {
    final cardWidth = tvIsWindowsDesktop
        ? tvDesktopValue(context, tv: 190, windows: 226)
        : 190.0;
    final rowHeight = cardWidth * 1.48 + (tvIsWindowsDesktop ? 92 : 49);
    return Padding(
      padding: const EdgeInsets.only(bottom: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'جاري التنزيل',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 13),
          SizedBox(
            height: rowHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 18),
              itemBuilder: (context, index) {
                final item = items[index];
                final progress = item.progress.clamp(0.0, 1.0);

                return SizedBox(
                  width: cardWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              TvImage(
                                item.media.posterUrl,
                                cacheWidth: 360,
                              ),
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.center,
                                    colors: [
                                      Color(0xC7000000),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 7,
                                  backgroundColor: Colors.black45,
                                  color: TvColors.red,
                                ),
                              ),
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 11,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xD9000000),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    item.isPaused
                                        ? 'متوقف مؤقتاً'
                                        : '${(progress * 100).round()}%',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.media.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        textDirection: TextDirection.rtl,
                        children: [
                          Expanded(
                            child: TvFocus(
                              onPressed: () {
                                if (item.isPaused) {
                                  tvDownloads.resume(item.media.id);
                                } else {
                                  tvDownloads.pause(item.media.id);
                                }
                              },
                              child: Container(
                                height: 38,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(.06),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  item.isPaused
                                      ? Icons.play_arrow_rounded
                                      : Icons.pause_rounded,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TvFocus(
                              onPressed: () =>
                                  tvDownloads.cancel(item.media.id),
                              child: Container(
                                height: 38,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  size: 22,
                                  color: Colors.redAccent,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadsRow extends StatelessWidget {
  const _DownloadsRow({required this.items});
  final List<TvDownloadedItem> items;

  @override
  Widget build(BuildContext context) {
    final cardWidth = tvIsWindowsDesktop
        ? tvDesktopValue(context, tv: 176, windows: 216)
        : 176.0;
    final rowHeight = cardWidth * 1.48 + (tvIsWindowsDesktop ? 52 : 40);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'التنزيلات',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: rowHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 18),
              itemBuilder: (context, index) => SizedBox(
                width: cardWidth,
                child: _DownloadedMediaCard(item: items[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadedMediaCard extends StatefulWidget {
  const _DownloadedMediaCard({required this.item});
  final TvDownloadedItem item;

  @override
  State<_DownloadedMediaCard> createState() => _DownloadedMediaCardState();
}

class _DownloadedMediaCardState extends State<_DownloadedMediaCard> {
  final FocusNode _focusNode = FocusNode();
  Timer? _holdTimer;
  bool _focused = false;
  bool _hovered = false;
  bool _longPressTriggered = false;

  @override
  void dispose() {
    _holdTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _open() {
    Navigator.of(context).push(
      tvVideoRoute(
        TvPlayerScreen(
          media: widget.item.media,
          localPath: widget.item.localPath,
        ),
      ),
    );
  }

  Future<void> _showOptions() async {
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF171717),
        title: Text(widget.item.media.title, textAlign: TextAlign.right),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Focus(
                autofocus: true,
                child: SizedBox(
                  height: 1,
                  width: 1,
                ),
              ),
              const SizedBox(height: 8),
              TvFocus(
                onPressed: () => Navigator.pop(dialogContext, 'play'),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Icon(Icons.play_arrow_rounded),
                      SizedBox(width: 10),
                      Text('تشغيل'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TvFocus(
                onPressed: () => Navigator.pop(dialogContext, 'delete'),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                      SizedBox(width: 10),
                      Text(
                        'حذف التنزيل نهائياً',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (action == 'play') {
      _open();
      return;
    }

    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFF171717),
          title: const Text('تأكيد الحذف', textAlign: TextAlign.right),
          content: Text(
            'سيتم حذف "${widget.item.media.title}" نهائياً من ذاكرة التلفاز.',
            textAlign: TextAlign.right,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حذف نهائي'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await tvDownloads.remove(widget.item.id);
      }
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final selected = key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select;
    if (!selected) return KeyEventResult.ignored;

    if (event is KeyDownEvent) {
      _longPressTriggered = false;
      _holdTimer?.cancel();
      _holdTimer = Timer(const Duration(milliseconds: 700), () {
        _longPressTriggered = true;
        _showOptions();
      });
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    if (event is KeyUpEvent) {
      _holdTimer?.cancel();
      if (!_longPressTriggered) _open();
      _longPressTriggered = false;
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final episode = widget.item.media.episode;
    final active = _focused || (tvIsWindowsDesktop && _hovered);
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _key,
      onFocusChange: (value) {
        if (_focused != value) setState(() => _focused = value);
      },
      child: MouseRegion(
        cursor: tvIsWindowsDesktop ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) { if (tvIsWindowsDesktop && !_hovered) setState(() => _hovered = true); },
        onExit: (_) { if (_hovered) setState(() => _hovered = false); },
        child: GestureDetector(
          onTap: _open,
          onLongPress: _showOptions,
          child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: active ? Colors.white : Colors.transparent,
              width: active ? 3 : 1,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: TvColors.red.withOpacity(.34),
                      blurRadius: 22,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(14),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      TvImage(widget.item.media.posterUrl, cacheWidth: 340),
                      if (widget.item.media.isSeries && episode != null)
                        Positioned(
                          top: 9,
                          right: 9,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: TvColors.red,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              'الحلقة $episode',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.media.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      widget.item.quality,
                      style: const TextStyle(
                        fontSize: 12,
                        color: TvColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _MediaCollectionScreen extends StatelessWidget {
  const _MediaCollectionScreen({required this.title, required this.items});
  final String title;
  final List<MediaItem> items;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), backgroundColor: TvColors.background),
      body: _MediaGrid(items: items),
    );
  }
}

class _DownloadsScreen extends StatelessWidget {
  const _DownloadsScreen({required this.items});
  final List<TvDownloadedItem> items;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: tvDownloads,
      builder: (context, _) {
        final downloads = tvDownloads.items;
        return Scaffold(
          appBar: AppBar(
            title: const Text('التنزيلات'),
            backgroundColor: TvColors.background,
          ),
          body: GridView.builder(
            padding: const EdgeInsets.all(17),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: tvIsWindowsDesktop ? 286 : 235,
              childAspectRatio: tvIsWindowsDesktop ? .61 : .60,
              crossAxisSpacing: tvIsWindowsDesktop ? 24 : 20,
              mainAxisSpacing: tvIsWindowsDesktop ? 28 : 22,
            ),
            itemCount: downloads.length,
            itemBuilder: (context, index) =>
                _DownloadedMediaCard(item: downloads[index]),
          ),
        );
      },
    );
  }
}

class _MediaGrid extends StatelessWidget {
  const _MediaGrid({required this.items});
  final List<MediaItem> items;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(17),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: tvIsWindowsDesktop ? 286 : 232,
        childAspectRatio: tvIsWindowsDesktop ? .62 : .61,
        crossAxisSpacing: tvIsWindowsDesktop ? 24 : 20,
        mainAxisSpacing: tvIsWindowsDesktop ? 28 : 22,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return TvFocus(
          onPressed: () => Navigator.of(context).push(tvRoute(TvDetailsScreen(item: item))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: TvImage(item.posterUrl, cacheWidth: 340)),
              const SizedBox(height: 8),
              Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            ],
          ),
        );
      },
    );
  }
}

class _DeveloperCard extends StatelessWidget {
  const _DeveloperCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: TvColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(38),
            child: Image.asset(
              'assets/branding/scrptaty_developer.png',
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              cacheWidth: 170,
            ),
          ),
          const SizedBox(width: 15),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('مطوّر التطبيق', style: TextStyle(fontSize: 13, color: TvColors.textMuted)),
                SizedBox(height: 4),
                Text('سكربتاتي', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                SizedBox(height: 5),
                Text(
                  'الجهة المطوّرة لتطبيق سينماتي TV. تم تصميم نسخة التلفاز لتكون عربية، سريعة وخفيفة ومناسبة للتحكم الكامل بالريموت.',
                  style: TextStyle(fontSize: 14, height: 1.5, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
