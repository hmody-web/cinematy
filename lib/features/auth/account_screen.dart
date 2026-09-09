import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/cinematy_user.dart';
import '../../data/services/cinematy_account_api.dart';
import '../../providers.dart';
import '../../widgets/app_notice.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/cinematy_top_bar.dart';
import '../../widgets/media_card.dart';
import '../details/details_screen.dart';
import 'auth_service.dart';
import 'friend_requests_screen.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen>
    with WidgetsBindingObserver {
  bool _busy = false;
  bool _profileLoading = false;
  String? _loadedUid;
  CinematyUserProfile? _profile;
  String? _profileError;
  int _pendingFriendRequests = 0;
  Timer? _notificationsTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notificationsTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshFriendRequestCount(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshFriendRequestCount();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshFriendRequestCount();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationsTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshFriendRequestCount() async {
    if (FirebaseAuth.instance.currentUser == null) {
      if (mounted && _pendingFriendRequests != 0) {
        setState(() => _pendingFriendRequests = 0);
      }
      return;
    }
    try {
      final count =
          await CinematyAccountApi.instance.pendingFriendRequestsCount();
      if (!mounted) return;
      if (count != _pendingFriendRequests) {
        setState(() => _pendingFriendRequests = count);
      }
    } catch (_) {
      // لا نعرض تنبيهاً دورياً عند تعذر تحديث العداد.
    }
  }

  Future<void> _openFriendRequests() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const FriendRequestsScreen()),
    );
    if (!mounted) return;
    await _refreshFriendRequestCount();
  }

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final credential = await AuthService.instance.signInWithGoogle();
      if (!mounted || credential == null) return;
      await _loadProfile(credential.user, force: true);
      await ref.read(libraryProvider).syncCloudFavorites(force: true);
      if (!mounted) return;
      AppNotice.show(
        context,
        title: 'تم تسجيل الدخول',
        message: 'مرحباً بك في سينماتي.',
        type: AppNoticeType.success,
      );
    } on CinematyAuthException catch (error) {
      if (!mounted) return;
      AppNotice.show(
        context,
        title: 'تعذر تسجيل الدخول',
        message: error.message,
        type: AppNoticeType.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadProfile(User? user, {bool force = false}) async {
    if (user == null) {
      if (mounted) {
        setState(() {
          _loadedUid = null;
          _profile = null;
          _profileError = null;
          _profileLoading = false;
          _pendingFriendRequests = 0;
        });
      }
      return;
    }
    if (!force && (_profileLoading || _loadedUid == user.uid)) return;

    setState(() {
      _loadedUid = user.uid;
      _profileLoading = true;
      _profileError = null;
    });
    try {
      final profile = await CinematyAccountApi.instance.syncProfile();
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != user.uid) return;
      setState(() => _profile = profile);
      await _refreshFriendRequestCount();
    } on CinematyAccountApiException catch (error) {
      if (!mounted) return;
      setState(() => _profileError = error.message);
    } finally {
      if (mounted) setState(() => _profileLoading = false);
    }
  }

  Future<void> _showHandleEditor(User user) async {
    final current = _profile;
    if (current?.hasHandle == true && current?.canChangeHandle != true) {
      final date = current?.nextHandleChangeAt;
      AppNotice.show(
        context,
        title: 'تغيير المعرّف غير متاح حالياً',
        message: date == null
            ? 'يمكن تغيير المعرّف مرة واحدة كل 14 يوماً.'
            : 'يمكنك تغييره بعد ${_dateText(date)}.',
        type: AppNoticeType.info,
      );
      return;
    }

    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _HandleSheet(currentHandle: current?.handle),
    );
    if (result == null || !mounted) return;

    setState(() => _profileLoading = true);
    try {
      final updated = await CinematyAccountApi.instance.setHandle(result);
      if (!mounted) return;
      setState(() {
        _profile = updated;
        _profileError = null;
      });
      AppNotice.show(
        context,
        title: current?.hasHandle == true ? 'تم تغيير المعرّف' : 'تم إنشاء المعرّف',
        message: 'معرّف حسابك هو ${updated.handle}.',
        type: AppNoticeType.success,
      );
    } on CinematyAccountApiException catch (error) {
      if (!mounted) return;
      AppNotice.show(
        context,
        title: 'تعذر حفظ المعرّف',
        message: error.message,
        type: AppNoticeType.error,
      );
    } finally {
      if (mounted) setState(() => _profileLoading = false);
    }
  }

  Future<void> _showAccountDetails(User user) async {
    final action = await showModalBottomSheet<_AccountAction>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AccountDetailsSheet(user: user),
    );
    if (!mounted || action != _AccountAction.signOut) return;
    await _confirmSignOut();
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SignOutConfirmSheet(),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await AuthService.instance.signOut();
      if (!mounted) return;
      setState(() {
        _profile = null;
        _loadedUid = null;
        _pendingFriendRequests = 0;
      });
      AppNotice.show(
        context,
        title: 'تم تسجيل الخروج',
        message: 'يمكنك تسجيل الدخول في أي وقت.',
        type: AppNoticeType.info,
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
      body: StreamBuilder<User?>(
        stream: AuthService.instance.authStateChanges,
        initialData: AuthService.instance.currentUser,
        builder: (context, snapshot) {
          final user = snapshot.data;
          if (user == null) {
            return _SignedOutView(busy: _busy, onSignIn: _signIn);
          }
          if (_loadedUid != user.uid && !_profileLoading) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _loadProfile(user);
            });
          }
          return _signedIn(user);
        },
      ),
    );
  }

  Widget _signedIn(User user) {
    final library = ref.watch(libraryProvider);
    final favorites = library.favoriteItems();
    final name = _displayName(user);

    return RefreshIndicator(
      onRefresh: () async {
        await _loadProfile(user, force: true);
        await ref.read(libraryProvider).syncCloudFavorites(force: true);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 130),
        children: [
          Stack(
            children: [
              _GlassCard(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
                child: Row(
                  children: [
                    _ProfileAvatar(user: user, size: 82),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 88),
                  ],
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                child: _CircleAction(
                  icon: Icons.tune_rounded,
                  tooltip: 'بيانات الحساب',
                  onTap: () => _showAccountDetails(user),
                ),
              ),
              Positioned(
                top: 12,
                left: 56,
                child: _CircleAction(
                  icon: Icons.notifications_none_rounded,
                  tooltip: 'الإشعارات',
                  badge: _pendingFriendRequests,
                  onTap: _openFriendRequests,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _SectionTitle(
            title: 'معرّف حسابك في سينماتي',
            subtitle: 'معرّف فريد يمكن البحث عنك من خلاله',
          ),
          const SizedBox(height: 10),
          _HandleCard(
            profile: _profile,
            loading: _profileLoading,
            error: _profileError,
            onRetry: () => _loadProfile(user, force: true),
            onEdit: () => _showHandleEditor(user),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              const Expanded(
                child: _SectionTitle(
                  title: 'مفضلاتي',
                  subtitle: 'المحفوظات المرتبطة بحسابك',
                ),
              ),
              if (library.cloudSyncing)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 1.8),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (favorites.isEmpty)
            _GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
              child: Column(
                children: [
                  Icon(
                    Icons.favorite_border_rounded,
                    size: 34,
                    color: Colors.white.withOpacity(.55),
                  ),
                  const SizedBox(height: 9),
                  const Text(
                    'ما عندك مفضلات بعد',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'أي فيلم أو مسلسل تضيفه للمفضلة سيظهر هنا ويبقى مرتبطاً بحسابك.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(.48),
                      fontSize: 11.5,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: favorites.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 16,
                childAspectRatio: .52,
              ),
              itemBuilder: (_, index) {
                final item = favorites[index];
                return MediaPosterCard(
                  item: item,
                  width: double.infinity,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => DetailsScreen(item: item)),
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
  const _SignedOutView({required this.busy, required this.onSignIn});

  final bool busy;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 80),
      children: [
        _GlassCard(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
          child: Column(
            children: [
              Container(
                width: 82,
                height: 82,
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  color: Colors.white.withOpacity(.055),
                  border: Border.all(color: Colors.white.withOpacity(.08)),
                ),
                child: const BrandLogo(size: 68, showName: false),
              ),
              const SizedBox(height: 19),
              const Text(
                'حسابك في سينماتي',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                'سجّل الدخول لحفظ مفضلاتك على حسابك والعثور على مستخدمي سينماتي.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(.55),
                  height: 1.6,
                  fontSize: 12.2,
                ),
              ),
              const SizedBox(height: 23),
              FilledButton(
                onPressed: busy ? null : onSignIn,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                  ),
                ),
                child: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'G',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                          ),
                          SizedBox(width: 9),
                          Text(
                            'تسجيل الدخول باستخدام Google',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HandleCard extends StatelessWidget {
  const _HandleCard({
    required this.profile,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onEdit,
  });

  final CinematyUserProfile? profile;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    if (loading && profile == null) {
      return const _GlassCard(
        padding: EdgeInsets.all(18),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('جاري تحميل بيانات الحساب…'),
          ],
        ),
      );
    }

    if (profile == null) {
      return _GlassCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_rounded, color: Colors.white70),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                error ?? 'تعذر تحميل بيانات الحساب.',
                style: TextStyle(color: Colors.white.withOpacity(.65), fontSize: 11.5),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
          ],
        ),
      );
    }

    if (!profile!.hasHandle) {
      return _GlassCard(
        padding: const EdgeInsets.all(17),
        child: Row(
          children: [
            Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(
                color: AppColors.redBright.withOpacity(.09),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.alternate_email_rounded, color: AppColors.redBright),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'أنشئ معرّفك',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '5 إلى 20 حرفاً أو رقماً، ويكون فريداً لك.',
                    style: TextStyle(color: Colors.white.withOpacity(.48), fontSize: 10.8),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: onEdit,
              child: const Text('إنشاء'),
            ),
          ],
        ),
      );
    }

    final handle = profile!.handle!;
    return _GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                handle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .4,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'نسخ المعرّف',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: handle));
              if (!context.mounted) return;
              AppNotice.show(
                context,
                title: 'تم نسخ المعرّف',
                message: handle,
                type: AppNoticeType.success,
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 19),
          ),
          IconButton(
            tooltip: 'تغيير المعرّف',
            onPressed: onEdit,
            icon: Icon(
              Icons.edit_rounded,
              size: 19,
              color: profile!.canChangeHandle
                  ? Colors.white
                  : Colors.white.withOpacity(.32),
            ),
          ),
        ],
      ),
    );
  }
}

class _HandleSheet extends StatefulWidget {
  const _HandleSheet({this.currentHandle});

  final String? currentHandle;

  @override
  State<_HandleSheet> createState() => _HandleSheetState();
}

class _HandleSheetState extends State<_HandleSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.currentHandle ?? '',
  );

  bool get _valid => RegExp(r'^[A-Za-z0-9]{5,20}$').hasMatch(_controller.text.trim());

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: _SheetSurface(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.currentHandle == null ? 'إنشاء معرّف سينماتي' : 'تغيير معرّف سينماتي',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 7),
            Text(
              'استخدم من 5 إلى 20 حرفاً إنجليزياً أو رقماً. يمكن تغيير المعرّف مرة كل 14 يوماً.',
              style: TextStyle(color: Colors.white.withOpacity(.5), fontSize: 11.5, height: 1.55),
            ),
            const SizedBox(height: 15),
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(
                controller: _controller,
                autofocus: true,
                maxLength: 20,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                ],
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'مثال: omar27',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _valid
                  ? () => Navigator.pop(context, _controller.text.trim().toLowerCase())
                  : null,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              child: const Text('حفظ المعرّف'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _AccountAction { signOut }

class _AccountDetailsSheet extends StatelessWidget {
  const _AccountDetailsSheet({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final provider = user.providerData.any((e) => e.providerId == 'google.com')
        ? 'Google'
        : 'حساب سينماتي';
    return _SheetSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'بيانات الحساب',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          _InfoRow(icon: Icons.person_rounded, title: 'الاسم', value: _displayName(user)),
          _InfoRow(
            icon: Icons.alternate_email_rounded,
            title: 'البريد الإلكتروني',
            value: user.email?.trim().isNotEmpty == true ? user.email!.trim() : 'غير متوفر',
            ltr: true,
          ),
          _InfoRow(icon: Icons.login_rounded, title: 'طريقة تسجيل الدخول', value: provider),
          _InfoRow(
            icon: Icons.calendar_month_rounded,
            title: 'تاريخ إنشاء الحساب',
            value: _dateText(user.metadata.creationTime),
          ),
          _InfoRow(
            icon: Icons.history_rounded,
            title: 'آخر تسجيل دخول',
            value: _dateText(user.metadata.lastSignInTime),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, _AccountAction.signOut),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.redBright,
              side: BorderSide(color: AppColors.redBright.withOpacity(.28)),
              minimumSize: const Size.fromHeight(49),
            ),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );
  }
}

class _SignOutConfirmSheet extends StatelessWidget {
  const _SignOutConfirmSheet();

  @override
  Widget build(BuildContext context) {
    return _SheetSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.redBright.withOpacity(.1),
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Icon(Icons.logout_rounded, color: AppColors.redBright),
          ),
          const SizedBox(height: 13),
          const Text(
            'تسجيل الخروج؟',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'ستبقى مفضلات حسابك محفوظة ويمكن استعادتها عند تسجيل الدخول مرة أخرى.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(.52), fontSize: 11.5, height: 1.5),
          ),
          const SizedBox(height: 17),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('إلغاء'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.redBright),
                  child: const Text('تسجيل الخروج'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.value,
    this.ltr = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(.055))),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white70),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title, style: TextStyle(color: Colors.white.withOpacity(.55), fontSize: 11.5)),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Directionality(
              textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.8, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.user, required this.size});

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
        gradient: const LinearGradient(colors: [AppColors.redBright, Color(0xFFFF9B93)]),
        boxShadow: [
          BoxShadow(color: AppColors.redBright.withOpacity(.08), blurRadius: 24),
        ],
      ),
      child: ClipOval(
        child: ColoredBox(
          color: AppColors.surfaceHigh,
          child: photo?.isNotEmpty == true
              ? Image.network(
                  photo!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, size: 34),
                )
              : const Icon(Icons.person_rounded, size: 34),
        ),
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: Colors.white.withOpacity(.06),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 38,
                height: 38,
                child: Icon(icon, size: 18),
              ),
            ),
          ),
          if (badge > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.redBright,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: const Color(0xFF151112), width: 2),
                ),
                child: Text(
                  badge > 99 ? '99+' : '$badge',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: TextStyle(color: Colors.white.withOpacity(.43), fontSize: 10.8),
        ),
      ],
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.035),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withOpacity(.07)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _SheetSurface extends StatelessWidget {
  const _SheetSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
            decoration: BoxDecoration(
              color: const Color(0xF5151111),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              border: Border(top: BorderSide(color: Colors.white.withOpacity(.08))),
            ),
            child: child,
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

String _dateText(DateTime? value) {
  if (value == null) return 'غير متوفر';
  final local = value.toLocal();
  return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
}
