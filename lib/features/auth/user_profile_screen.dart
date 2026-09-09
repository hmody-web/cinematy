import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/cinematy_user.dart';
import '../../data/models/friend_request.dart';
import '../../data/models/media_item.dart';
import '../../data/services/cinematy_account_api.dart';
import '../../widgets/app_notice.dart';
import '../../widgets/cinematy_top_bar.dart';
import '../../widgets/media_card.dart';
import '../details/details_screen.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key, required this.handle});

  final String handle;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  CinematyUserProfile? _profile;
  List<MediaItem> _favorites = const [];
  FriendshipStatus? _friendship;
  bool _loading = true;
  bool _friendBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        CinematyAccountApi.instance.publicProfile(widget.handle),
        CinematyAccountApi.instance.userFavorites(widget.handle),
        CinematyAccountApi.instance.friendshipStatus(widget.handle),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = results[0] as CinematyUserProfile;
        _favorites = results[1] as List<MediaItem>;
        _friendship = results[2] as FriendshipStatus;
      });
    } on CinematyAccountApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendFriendRequest() async {
    if (_friendBusy) return;
    setState(() => _friendBusy = true);
    try {
      final status =
          await CinematyAccountApi.instance.sendFriendRequest(widget.handle);
      if (!mounted) return;
      setState(() => _friendship = status);
      AppNotice.show(
        context,
        title: 'تم إرسال طلب الصداقة',
        message: 'سيظهر الطلب في إشعارات المستخدم.',
        type: AppNoticeType.success,
      );
    } on CinematyAccountApiException catch (error) {
      if (!mounted) return;
      AppNotice.show(
        context,
        title: 'تعذر إرسال الطلب',
        message: error.message,
        type: AppNoticeType.error,
      );
    } finally {
      if (mounted) setState(() => _friendBusy = false);
    }
  }

  Future<void> _cancelFriendRequest() async {
    if (_friendBusy) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CancelRequestSheet(),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _friendBusy = true);
    try {
      final status =
          await CinematyAccountApi.instance.cancelFriendRequest(widget.handle);
      if (!mounted) return;
      setState(() => _friendship = status);
      AppNotice.show(
        context,
        title: 'تم إلغاء الطلب',
        message: 'يمكنك إرسال طلب صداقة جديد لاحقاً.',
        type: AppNoticeType.info,
      );
    } on CinematyAccountApiException catch (error) {
      if (!mounted) return;
      AppNotice.show(
        context,
        title: 'تعذر إلغاء الطلب',
        message: error.message,
        type: AppNoticeType.error,
      );
    } finally {
      if (mounted) setState(() => _friendBusy = false);
    }
  }

  Future<void> _acceptIncomingRequest() async {
    final requestId = _friendship?.requestId;
    if (requestId == null || _friendBusy) return;
    setState(() => _friendBusy = true);
    try {
      final status = await CinematyAccountApi.instance.respondToFriendRequest(
        requestId: requestId,
        accept: true,
      );
      if (!mounted) return;
      setState(() => _friendship = status);
      AppNotice.show(
        context,
        title: 'تم قبول طلب الصداقة',
        message: 'أصبحتما الآن أصدقاء في سينماتي.',
        type: AppNoticeType.success,
      );
    } on CinematyAccountApiException catch (error) {
      if (!mounted) return;
      AppNotice.show(
        context,
        title: 'تعذر قبول الطلب',
        message: error.message,
        type: AppNoticeType.error,
      );
    } finally {
      if (mounted) setState(() => _friendBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CinematyTopBar(
        section: 'الملف الشخصي',
        showQuickActions: false,
        onBack: () => Navigator.pop(context),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading && _profile == null
            ? const _LoadingProfile()
            : _error != null && _profile == null
                ? ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const SizedBox(height: 80),
                      const Icon(
                        Icons.person_off_rounded,
                        size: 48,
                        color: Colors.white54,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withOpacity(.6)),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: FilledButton(
                          onPressed: _load,
                          child: const Text('إعادة المحاولة'),
                        ),
                      ),
                    ],
                  )
                : _content(),
      ),
    );
  }

  Widget _content() {
    final profile = _profile!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 130),
      children: [
        _ProfileCard(profile: profile),
        if (_friendship?.isSelf != true) ...[
          const SizedBox(height: 12),
          _FriendActionCard(
            status: _friendship ?? const FriendshipStatus(state: FriendshipState.none),
            busy: _friendBusy,
            onAdd: _sendFriendRequest,
            onCancel: _cancelFriendRequest,
            onAccept: _acceptIncomingRequest,
          ),
        ],
        const SizedBox(height: 22),
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'المفضلات',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'الأعمال المحفوظة في هذا الحساب',
                    style: TextStyle(fontSize: 10.8, color: Colors.white54),
                  ),
                ],
              ),
            ),
            Text(
              '${_favorites.length}',
              style: TextStyle(
                color: Colors.white.withOpacity(.48),
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_favorites.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 18),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.03),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(.06)),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.favorite_border_rounded,
                  size: 34,
                  color: Colors.white.withOpacity(.42),
                ),
                const SizedBox(height: 8),
                Text(
                  'لا توجد مفضلات منشورة حالياً',
                  style: TextStyle(
                    color: Colors.white.withOpacity(.58),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _favorites.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 16,
              childAspectRatio: .52,
            ),
            itemBuilder: (_, i) {
              final item = _favorites[i];
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
    );
  }
}

class _FriendActionCard extends StatelessWidget {
  const _FriendActionCard({
    required this.status,
    required this.busy,
    required this.onAdd,
    required this.onCancel,
    required this.onAccept,
  });

  final FriendshipStatus status;
  final bool busy;
  final VoidCallback onAdd;
  final VoidCallback onCancel;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    late final IconData icon;
    late final String title;
    late final String subtitle;
    late final Color background;
    late final Color foreground;
    VoidCallback? action;

    switch (status.state) {
      case FriendshipState.friends:
        icon = Icons.people_alt_rounded;
        title = 'أصدقاء';
        subtitle = 'هذا المستخدم موجود ضمن أصدقائك';
        background = Colors.white.withOpacity(.08);
        foreground = Colors.white;
        action = null;
        break;
      case FriendshipState.outgoingPending:
        icon = Icons.schedule_send_rounded;
        title = 'تم إرسال الطلب';
        subtitle = 'بانتظار قبول طلب الصداقة';
        background = Colors.white.withOpacity(.065);
        foreground = Colors.white.withOpacity(.8);
        action = null;
        break;
      case FriendshipState.incomingPending:
        icon = Icons.person_add_alt_1_rounded;
        title = 'قبول طلب الصداقة';
        subtitle = 'هذا المستخدم أرسل لك طلب صداقة';
        background = AppColors.redBright;
        foreground = Colors.white;
        action = onAccept;
        break;
      case FriendshipState.self:
        icon = Icons.person_rounded;
        title = 'هذا حسابك';
        subtitle = '';
        background = Colors.white.withOpacity(.06);
        foreground = Colors.white;
        action = null;
        break;
      case FriendshipState.none:
        icon = Icons.person_add_alt_1_rounded;
        title = 'إضافة كصديق';
        subtitle = 'أرسل طلب صداقة لهذا المستخدم';
        background = Colors.white;
        foreground = Colors.black;
        action = onAdd;
        break;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.028),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(.06)),
          ),
          child: Column(
            children: [
              Material(
                color: background,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: busy ? null : action,
                  child: SizedBox(
                    height: 50,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (busy)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Icon(icon, size: 19, color: foreground),
                        const SizedBox(width: 9),
                        Text(
                          title,
                          style: TextStyle(
                            color: foreground,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(.43),
                  fontSize: 10.6,
                ),
              ),
              if (status.isOutgoingPending) ...[
                const SizedBox(height: 4),
                TextButton(
                  onPressed: busy ? null : onCancel,
                  child: const Text(
                    'إلغاء الطلب',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CancelRequestSheet extends StatelessWidget {
  const _CancelRequestSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        decoration: BoxDecoration(
          color: const Color(0xFF151112),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withOpacity(.08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'إلغاء طلب الصداقة؟',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'لن يصل هذا الطلب للمستخدم بعد إلغائه.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(.48),
                fontSize: 11.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.redBright,
                    ),
                    child: const Text('إلغاء الطلب'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('رجوع'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile});

  final CinematyUserProfile profile;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.035),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withOpacity(.07)),
          ),
          child: Row(
            children: [
              _Avatar(url: profile.photoUrl),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName.isEmpty
                          ? 'مستخدم سينماتي'
                          : profile.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (profile.handle?.isNotEmpty == true) ...[
                      const SizedBox(height: 6),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          profile.handle!,
                          style: TextStyle(
                            color: AppColors.redBright.withOpacity(.9),
                            fontWeight: FontWeight.w900,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 76,
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [AppColors.redBright, Color(0xFFFF9A92)],
        ),
      ),
      child: ClipOval(
        child: ColoredBox(
          color: AppColors.surfaceHigh,
          child: url.isEmpty
              ? const Icon(Icons.person_rounded, size: 32)
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.person_rounded, size: 32),
                ),
        ),
      ),
    );
  }
}

class _LoadingProfile extends StatelessWidget {
  const _LoadingProfile();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        SizedBox(height: 180),
        Center(child: CircularProgressIndicator()),
      ],
    );
  }
}
