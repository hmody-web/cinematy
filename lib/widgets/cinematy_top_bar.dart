import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../features/auth/auth_service.dart';

import '../core/theme/app_theme.dart';
import 'app_notice.dart';
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
    this.brandGlassProgress = 0,
    this.brandOpacity = 1,
  });

  final String? section;
  final VoidCallback? onContinue;
  final VoidCallback? onDownloads;
  final int downloadsCount;
  final bool showQuickActions;
  final VoidCallback? onBack;
  final double brandGlassProgress;
  final double brandOpacity;

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
          brandGlassProgress: brandGlassProgress,
          brandOpacity: brandOpacity,
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
    this.brandGlassProgress = 0,
    this.brandOpacity = 1,
  });

  final String? section;
  final VoidCallback? onContinue;
  final VoidCallback? onDownloads;
  final int downloadsCount;
  final bool showQuickActions;
  final VoidCallback? onBack;
  final double brandGlassProgress;
  final double brandOpacity;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: [
          if (showQuickActions) ...[
            const _AccountQuickAction(),
            const SizedBox(width: 8),
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
          Opacity(
            opacity: brandOpacity.clamp(0.0, 1.0),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _BrandGlass(
                    progress: brandGlassProgress.clamp(0.0, 1.0),
                    child: const BrandLogo(size: 38),
                  ),
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


class _AccountQuickAction extends StatefulWidget {
  const _AccountQuickAction();

  @override
  State<_AccountQuickAction> createState() => _AccountQuickActionState();
}

class _AccountQuickActionState extends State<_AccountQuickAction> {
  final GlobalKey _anchorKey = GlobalKey();

  Future<void> _openPopover(User? user) async {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final position = box.localToGlobal(Offset.zero);
    final size = box.size;
    if (!mounted) return;

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'الحساب',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, __) {
        final screen = MediaQuery.sizeOf(dialogContext);
        final cardWidth = screen.width < 310 ? screen.width - 24 : 268.0;
        final maxLeft = (screen.width - cardWidth - 12)
            .clamp(12.0, double.infinity)
            .toDouble();
        final left = (position.dx - 2).clamp(12.0, maxLeft).toDouble();
        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(dialogContext).pop(),
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned(
                top: position.dy + size.height + 7,
                left: left,
                width: cardWidth,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {},
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 24),
                            child: Transform.rotate(
                              angle: .785398,
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF171719),
                                  border: Border(
                                    top: BorderSide(
                                      color: Colors.white.withOpacity(.09),
                                    ),
                                    left: BorderSide(
                                      color: Colors.white.withOpacity(.09),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Transform.translate(
                          offset: const Offset(0, -7),
                          child: _AccountPopoverBody(
                            initialUser: user,
                            rootContext: context,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      transitionBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: ScaleTransition(
          scale: Tween<double>(begin: .965, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          alignment: Alignment.topLeft,
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.authStateChanges,
      initialData: AuthService.instance.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        final photo = user?.photoURL?.trim();
        return Tooltip(
          message: user == null ? 'تسجيل الدخول' : 'حسابي',
          child: ClipRRect(
            key: _anchorKey,
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Material(
                color: Colors.white.withOpacity(.055),
                child: InkWell(
                  onTap: () => _openPopover(user),
                  child: Container(
                    width: 44,
                    height: 44,
                    padding: EdgeInsets.all(user == null ? 0 : 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: user == null
                            ? Colors.white.withOpacity(.07)
                            : AppColors.redBright.withOpacity(.22),
                      ),
                    ),
                    child: user == null
                        ? const Icon(Icons.person_outline_rounded, size: 22)
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: photo?.isNotEmpty == true
                                ? Image.network(
                                    photo!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.person_rounded,
                                      size: 22,
                                    ),
                                  )
                                : const Icon(Icons.person_rounded, size: 22),
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AccountPopoverBody extends StatefulWidget {
  const _AccountPopoverBody({
    required this.initialUser,
    required this.rootContext,
  });

  final User? initialUser;
  final BuildContext rootContext;

  @override
  State<_AccountPopoverBody> createState() => _AccountPopoverBodyState();
}

class _AccountPopoverBodyState extends State<_AccountPopoverBody> {
  bool _busy = false;

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final credential = await AuthService.instance.signInWithGoogle();
      if (!mounted || credential == null) return;
      AppNotice.show(
        widget.rootContext,
        title: 'تم تسجيل الدخول',
        message: 'أهلاً ${credential.user?.displayName ?? ''}'.trim(),
        type: AppNoticeType.success,
      );
    } on CinematyAuthException catch (error) {
      if (!mounted) return;
      AppNotice.show(
        widget.rootContext,
        title: 'تعذر تسجيل الدخول',
        message: error.message,
        type: AppNoticeType.error,
        duration: const Duration(seconds: 5),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    if (_busy) return;

    final confirmed = await showModalBottomSheet<bool>(
      context: widget.rootContext,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _TopSignOutSheet(),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await AuthService.instance.signOut();
      if (!mounted) return;
      AppNotice.show(
        widget.rootContext,
        title: 'تم تسجيل الخروج',
        message: 'يمكنك تسجيل الدخول مجدداً في أي وقت.',
        type: AppNoticeType.info,
      );
    } catch (_) {
      if (!mounted) return;
      AppNotice.show(
        widget.rootContext,
        title: 'تعذر تسجيل الخروج',
        message: 'حاول مرة أخرى.',
        type: AppNoticeType.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.authStateChanges,
      initialData: widget.initialUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0xFF171719).withOpacity(.97),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(.09)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(.35),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: user == null ? _signedOut() : _signedIn(user),
            ),
          ),
        );
      },
    );
  }

  Widget _signedOut() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.redBright.withOpacity(.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.person_outline_rounded, size: 22),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'حساب سينماتي',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'سجّل دخولك للوصول لميزاتك',
                      style: TextStyle(fontSize: 10.5, color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          FilledButton(
            onPressed: _busy ? null : _signIn,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(42),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('G', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                      SizedBox(width: 9),
                      Text(
                        'تسجيل الدخول بواسطة Google',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
          ),
        ],
      );

  Widget _signedIn(User user) {
    final photo = user.photoURL?.trim();
    final created = user.metadata.creationTime;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 46,
              height: 46,
              padding: const EdgeInsets.all(1.5),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [AppColors.redBright, Color(0xFFFF8A80)],
                ),
              ),
              child: ClipOval(
                child: ColoredBox(
                  color: AppColors.surfaceHigh,
                  child: photo?.isNotEmpty == true
                      ? Image.network(photo!, fit: BoxFit.cover)
                      : const Icon(Icons.person_rounded),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.displayName?.trim().isNotEmpty == true
                              ? user.displayName!.trim()
                              : 'حساب سينماتي',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Icon(Icons.verified_rounded, size: 15, color: AppColors.success),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    user.email ?? 'حساب Google',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withOpacity(.5), fontSize: 10.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.035),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white.withOpacity(.055)),
          ),
          child: Column(
            children: [
              _AccountInfoRow(label: 'الحالة', value: user.emailVerified ? 'موثّق' : 'متصل'),
              if (created != null) ...[
                const SizedBox(height: 7),
                _AccountInfoRow(
                  label: 'منذ',
                  value: '${created.year}/${created.month}/${created.day}',
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 11),
        TextButton.icon(
          onPressed: _busy ? null : _signOut,
          icon: const Icon(Icons.logout_rounded, size: 17),
          label: const Text('تسجيل الخروج'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white60,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }
}


class _TopSignOutSheet extends StatelessWidget {
  const _TopSignOutSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            decoration: BoxDecoration(
              color: const Color(0xF2191515),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white.withOpacity(.09)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.logout_rounded,
                  size: 32,
                  color: AppColors.redBright,
                ),
                const SizedBox(height: 10),
                const Text(
                  'تسجيل الخروج؟',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                Text(
                  'سيبقى محتواك المحلي محفوظاً، ويمكنك تسجيل الدخول بالحساب نفسه لاحقاً.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(.52),
                    fontSize: 11.5,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 17),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          side: BorderSide(color: Colors.white.withOpacity(.10)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'إلغاء',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: AppColors.redBright,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'تسجيل الخروج',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountInfoRow extends StatelessWidget {
  const _AccountInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)),
        ],
      );
}

class _BrandGlass extends StatelessWidget {
  const _BrandGlass({required this.progress, required this.child});

  final double progress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Lightweight logo background: no BackdropFilter and no white glass
    // highlight. Once the threshold is crossed it becomes a stable dark
    // surface with a very subtle Cinematy-red tint.
    final visible = progress >= .5;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.symmetric(
        horizontal: visible ? 12 : 4,
        vertical: visible ? 6 : 2,
      ),
      decoration: BoxDecoration(
        gradient: visible
            ? LinearGradient(
                begin: Alignment.bottomRight,
                end: Alignment.topLeft,
                colors: [
                  const Color(0xFF080808).withOpacity(.96),
                  const Color(0xFF0D0505).withOpacity(.94),
                  const Color(0xFF120606).withOpacity(.90),
                ],
              )
            : null,
        color: visible ? null : Colors.transparent,
        borderRadius: BorderRadius.circular(visible ? 18 : 13),
        border: Border.all(
          color: visible
              ? const Color(0xFF2A1010).withOpacity(.42)
              : Colors.transparent,
          width: .8,
        ),
      ),
      child: child,
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
