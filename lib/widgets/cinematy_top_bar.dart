import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'brand_logo.dart';

class CinematyTopBar extends StatelessWidget implements PreferredSizeWidget {
  const CinematyTopBar({
    super.key,
    this.section,
    this.onContinue,
    this.onDownloads,
    this.downloadsCount = 0,
    this.showQuickActions = true,
    this.onBack,
  });

  final String? section;
  final VoidCallback? onContinue;
  final VoidCallback? onDownloads;
  final int downloadsCount;
  final bool showQuickActions;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(74);

  @override
  Widget build(BuildContext context) => AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 74,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.background.withOpacity(.82),
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(.035))),
              ),
            ),
          ),
        ),
        titleSpacing: 16,
        title: CinematyTopBarContent(
          section: section,
          onContinue: onContinue,
          onDownloads: onDownloads,
          downloadsCount: downloadsCount,
          showQuickActions: showQuickActions,
          onBack: onBack,
        ),
      );
}

class CinematyTopBarContent extends StatelessWidget {
  const CinematyTopBarContent({
    super.key,
    this.section,
    this.onContinue,
    this.onDownloads,
    this.downloadsCount = 0,
    this.showQuickActions = true,
    this.onBack,
  });

  final String? section;
  final VoidCallback? onContinue;
  final VoidCallback? onDownloads;
  final int downloadsCount;
  final bool showQuickActions;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: [
          if (showQuickActions) ...[
            _TopAction(
              icon: Icons.play_circle_outline_rounded,
              tooltip: 'متابعة المشاهدة',
              onTap: onContinue,
            ),
            const SizedBox(width: 8),
            _TopAction(
              icon: Icons.download_for_offline_outlined,
              tooltip: 'التنزيلات',
              badge: downloadsCount,
              onTap: onDownloads,
            ),
          ],
          const Spacer(),
          Directionality(
            textDirection: TextDirection.rtl,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandLogo(size: 38),
                if (section != null && section!.trim().isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.045),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withOpacity(.06)),
                    ),
                    child: Text(
                      section!,
                      style: TextStyle(
                        color: Colors.white.withOpacity(.72),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onBack != null) ...[
            const SizedBox(width: 8),
            _TopAction(
              icon: Icons.arrow_forward_ios_rounded,
              tooltip: 'رجوع',
              onTap: onBack,
            ),
          ],
        ],
      ),
    );
  }
}

class _TopAction extends StatelessWidget {
  const _TopAction({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final int badge;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Material(
              color: Colors.white.withOpacity(.055),
              child: InkWell(
                onTap: onTap,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(.07)),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Center(child: Icon(icon, size: 22)),
                      if (badge > 0)
                        Positioned(
                          right: 4,
                          top: 4,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: AppColors.redBright,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              badge > 99 ? '99+' : '$badge',
                              style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
