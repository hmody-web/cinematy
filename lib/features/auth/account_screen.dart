import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/cinematy_backdrop.dart';
import '../../widgets/app_notice.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/cinematy_top_bar.dart';
import 'auth_service.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _busy = false;

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final credential = await AuthService.instance.signInWithGoogle();
      if (!mounted || credential == null) return;

      final name = credential.user?.displayName?.trim();
      AppNotice.show(
        context,
        title: 'تم تسجيل الدخول',
        message: name?.isNotEmpty == true
            ? 'أهلاً $name، حسابك جاهز في سينماتي.'
            : 'تم ربط حساب Google بنجاح.',
        type: AppNoticeType.success,
      );
    } on CinematyAuthException catch (error) {
      if (!mounted) return;
      AppNotice.show(
        context,
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
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const _SignOutSheet(),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await AuthService.instance.signOut();
      if (!mounted) return;
      AppNotice.show(
        context,
        title: 'تم تسجيل الخروج',
        message: 'يمكنك تسجيل الدخول مجدداً في أي وقت.',
        type: AppNoticeType.info,
      );
    } catch (_) {
      if (!mounted) return;
      AppNotice.show(
        context,
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
    return Scaffold(
      extendBody: true,
      appBar: CinematyTopBar(
        section: 'الحساب',
        showQuickActions: false,
        onBack: () => Navigator.pop(context),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: CinematyBackdrop()),
          StreamBuilder<User?>(
            stream: AuthService.instance.authStateChanges,
        initialData: AuthService.instance.currentUser,
        builder: (context, snapshot) {
          final user = snapshot.data;
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 360),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: user == null
                ? _SignedOutView(
                    key: const ValueKey('signed-out'),
                    busy: _busy,
                    onSignIn: _signIn,
                  )
                : _ProfileView(
                    key: ValueKey('profile-${user.uid}'),
                    user: user,
                    busy: _busy,
                    onSignOut: _signOut,
                  ),
          );
        },
          ),
        ],
      ),
    );
  }
}

class _SignedOutView extends StatelessWidget {
  const _SignedOutView({
    super.key,
    required this.busy,
    required this.onSignIn,
  });

  final bool busy;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 42),
      children: [
        _GlassCard(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            children: [
              Container(
                width: 86,
                height: 86,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(27),
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      Colors.white.withOpacity(.13),
                      AppColors.redBright.withOpacity(.15),
                    ],
                  ),
                  border: Border.all(color: Colors.white.withOpacity(.12)),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.redBright.withOpacity(.13),
                      blurRadius: 38,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const BrandLogo(size: 70, showName: false),
              ),
              const SizedBox(height: 20),
              const Text(
                'حسابك في سينماتي',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.4,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                'سجّل الدخول باستخدام Google للوصول إلى حسابك في سينماتي والاستفادة من ميزات الحساب بسهولة وأمان.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(.62),
                  fontSize: 13.2,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 24),
              _GoogleSignInButton(busy: busy, onPressed: onSignIn),
              const SizedBox(height: 13),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_rounded,
                    size: 14,
                    color: Colors.white.withOpacity(.38),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'تسجيل دخول آمن باستخدام Google',
                    style: TextStyle(
                      color: Colors.white.withOpacity(.38),
                      fontSize: 10.7,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _SectionTitle(
          title: 'ماذا يضيف الحساب؟',
          subtitle: 'هوية واحدة بدون كلمة مرور داخل سينماتي',
        ),
        const SizedBox(height: 10),
        const _FeatureCard(
          icon: Icons.verified_user_rounded,
          title: 'هوية موثوقة',
          subtitle: 'الاسم والصورة والبريد تأتي مباشرة من حساب Google الذي تختاره.',
        ),
        const SizedBox(height: 10),
        const _FeatureCard(
          icon: Icons.groups_2_rounded,
          title: 'جاهز للمشاهدة الجماعية',
          subtitle: 'حساب واحد يعرّفك داخل سينماتي ويحافظ على معلومات حسابك في مكان واحد.',
        ),
        const SizedBox(height: 10),
        const _FeatureCard(
          icon: Icons.devices_rounded,
          title: 'جلسة ثابتة',
          subtitle: 'يبقى تسجيل دخولك محفوظاً على جهازك حتى تختار تسجيل الخروج.',
        ),
      ],
    );
  }
}

class _ProfileView extends StatelessWidget {
  const _ProfileView({
    super.key,
    required this.user,
    required this.busy,
    required this.onSignOut,
  });

  final User user;
  final bool busy;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final name = _displayName(user);
    final email = user.email?.trim();
    final provider = user.providerData.isNotEmpty
        ? _providerLabel(user.providerData.first.providerId)
        : 'سينماتي';

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 42),
      children: [
        _GlassCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _ProfileAvatar(user: user, size: 78),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.25,
                          ),
                        ),
                        if (email?.isNotEmpty == true) ...[
                          const SizedBox(height: 4),
                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: Text(
                              email!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: Colors.white.withOpacity(.55),
                                fontSize: 11.6,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            _MiniBadge(
                              icon: user.emailVerified
                                  ? Icons.verified_rounded
                                  : Icons.info_outline_rounded,
                              label: user.emailVerified ? 'بريد موثّق' : 'غير موثّق',
                              accent: user.emailVerified
                                  ? AppColors.success
                                  : Colors.white70,
                            ),
                            _MiniBadge(
                              icon: Icons.g_mobiledata_rounded,
                              label: provider,
                              accent: Colors.white,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 17),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(.07),
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: AppColors.success.withOpacity(.14)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.success,
                      size: 19,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'أنت مسجّل الدخول وحسابك متصل بسينماتي بنجاح.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(.78),
                          fontSize: 11.7,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const _SectionTitle(
          title: 'معرّف حسابك في سينماتي',
          subtitle: 'يمكنك نسخه واستخدامه عند الحاجة',
        ),
        const SizedBox(height: 10),
        _UidCard(uid: user.uid),
        const SizedBox(height: 18),
        const _SectionTitle(
          title: 'الملف الشخصي',
          subtitle: 'معلومات حسابك في سينماتي',
        ),
        const SizedBox(height: 10),
        _DetailsCard(
          children: [
            _DetailRow(
              icon: Icons.person_rounded,
              title: 'الاسم',
              value: name,
            ),
            _DetailRow(
              icon: Icons.alternate_email_rounded,
              title: 'البريد الإلكتروني',
              value: email?.isNotEmpty == true ? email! : 'غير متوفر',
              ltrValue: true,
            ),
            _DetailRow(
              icon: Icons.login_rounded,
              title: 'طريقة الدخول',
              value: provider,
            ),
            _DetailRow(
              icon: Icons.calendar_month_rounded,
              title: 'تاريخ إنشاء الحساب',
              value: _dateText(user.metadata.creationTime),
            ),
            _DetailRow(
              icon: Icons.history_rounded,
              title: 'آخر تسجيل دخول',
              value: _dateText(user.metadata.lastSignInTime),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _GlassCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.redBright.withOpacity(.09),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.movie_filter_rounded,
                  color: AppColors.redBright,
                  size: 23,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'جاهز للميزات الاجتماعية',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'استخدم حسابك كهوية موحدة داخل سينماتي للوصول إلى ميزات الحساب بسهولة.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(.53),
                        fontSize: 11.2,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 54,
          child: OutlinedButton.icon(
            onPressed: busy ? null : onSignOut,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: AppColors.redBright.withOpacity(.30)),
              backgroundColor: AppColors.redBright.withOpacity(.055),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout_rounded, size: 20),
            label: Text(
              busy ? 'جاري التنفيذ...' : 'تسجيل الخروج',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF171717),
          disabledBackgroundColor: Colors.white.withOpacity(.75),
          disabledForegroundColor: const Color(0xFF171717),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: busy
              ? const Row(
                  key: ValueKey('loading'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Color(0xFF222222),
                      ),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'جاري تسجيل الدخول...',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                )
              : const Row(
                  key: ValueKey('ready'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _GoogleMark(size: 22),
                    SizedBox(width: 12),
                    Text(
                      'المتابعة باستخدام Google',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark({this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleMarkPainter()),
    );
  }
}

class _GoogleMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * .19;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, -.12, 1.64, false, paint);
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(rect, 1.52, 1.30, false, paint);
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, 2.82, .92, false, paint);
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, 3.74, 1.38, false, paint);

    final blue = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(
      Offset(size.width * .55, size.height * .51),
      Offset(size.width * .93, size.height * .51),
      blue,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.user, this.size = 72});

  final User user;
  final double size;

  @override
  Widget build(BuildContext context) {
    final photo = user.photoURL?.trim();
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [AppColors.redBright, Color(0xFFFF8A80)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.redBright.withOpacity(.18),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipOval(
        child: ColoredBox(
          color: AppColors.surfaceHigh,
          child: photo?.isNotEmpty == true
              ? Image.network(
                  photo!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _AvatarFallback(user: user),
                )
              : _AvatarFallback(user: user),
        ),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final name = _displayName(user);
    final trimmed = name.trim();
    final letter = trimmed.isNotEmpty ? trimmed.substring(0, 1) : 'س';
    return Center(
      child: Text(
        letter,
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _UidCard extends StatelessWidget {
  const _UidCard({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.055),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.fingerprint_rounded, size: 22),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                uid,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(.70),
                  fontSize: 11.2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .15,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'نسخ المعرّف',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: uid));
              if (!context.mounted) return;
              AppNotice.show(
                context,
                title: 'تم النسخ',
                message: 'تم نسخ معرّف حسابك في سينماتي.',
                type: AppNoticeType.success,
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 19),
          ),
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              Divider(
                height: 1,
                indent: 62,
                color: Colors.white.withOpacity(.055),
              ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.title,
    required this.value,
    this.ltrValue = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool ltrValue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.05),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, size: 19, color: Colors.white.withOpacity(.78)),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white.withOpacity(.42),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Directionality(
                  textDirection: ltrValue ? TextDirection.ltr : TextDirection.rtl,
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.start,
                    style: const TextStyle(fontSize: 12.6, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.icon, required this.label, required this.accent});

  final IconData icon;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withOpacity(.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(.13)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent.withOpacity(.9)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(.72),
              fontSize: 9.8,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.055),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white.withOpacity(.05)),
            ),
            child: Icon(icon, size: 22, color: Colors.white.withOpacity(.82)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 13.7, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(.50),
                    fontSize: 10.8,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(.37),
                    fontSize: 10.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            Colors.white.withOpacity(.060),
            Colors.white.withOpacity(.025),
          ],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withOpacity(.075)),
      ),
      child: child,
    );
  }
}


class _SignOutSheet extends StatelessWidget {
  const _SignOutSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              decoration: BoxDecoration(
                color: const Color(0xF2191515),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withOpacity(.09)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.15),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Icon(Icons.logout_rounded, size: 34, color: AppColors.redBright),
                  const SizedBox(height: 10),
                  const Text(
                    'تسجيل الخروج؟',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'سيبقى التطبيق ومحتواك المحلي كما هو، ويمكنك تسجيل الدخول بالحساب نفسه لاحقاً.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(.52),
                      fontSize: 11.7,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(17),
                            ),
                            side: BorderSide(color: Colors.white.withOpacity(.10)),
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
                            minimumSize: const Size.fromHeight(50),
                            backgroundColor: AppColors.redBright,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(17),
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
      ),
    );
  }
}

String _displayName(User user) {
  final name = user.displayName?.trim();
  if (name?.isNotEmpty == true) return name!;

  final email = user.email?.trim();
  if (email?.isNotEmpty == true) return email!.split('@').first;
  return 'مستخدم سينماتي';
}

String _providerLabel(String providerId) {
  return switch (providerId) {
    'google.com' => 'Google',
    'apple.com' => 'Apple',
    'password' => 'البريد الإلكتروني',
    _ => 'سينماتي',
  };
}

String _dateText(DateTime? date) {
  if (date == null) return 'غير متوفر';

  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}/${two(date.month)}/${two(date.day)} • ${two(date.hour)}:${two(date.minute)}';
}
