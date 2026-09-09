import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/friend_request.dart';
import '../../data/services/cinematy_account_api.dart';
import '../../widgets/app_notice.dart';
import '../../widgets/cinematy_top_bar.dart';
import 'user_profile_screen.dart';

class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen> {
  List<FriendRequestItem> _requests = const [];
  bool _loading = true;
  final Set<int> _busy = <int>{};
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
      final items = await CinematyAccountApi.instance.incomingFriendRequests();
      if (!mounted) return;
      setState(() => _requests = items);
    } on CinematyAccountApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _respond(FriendRequestItem request, bool accept) async {
    if (_busy.contains(request.id)) return;
    setState(() => _busy.add(request.id));
    try {
      await CinematyAccountApi.instance.respondToFriendRequest(
        requestId: request.id,
        accept: accept,
      );
      if (!mounted) return;
      setState(() {
        _requests = _requests.where((e) => e.id != request.id).toList();
      });
      AppNotice.show(
        context,
        title: accept ? 'تم قبول طلب الصداقة' : 'تم رفض طلب الصداقة',
        message: accept
            ? 'أصبحتما الآن أصدقاء في سينماتي.'
            : 'تم رفض الطلب.',
        type: accept ? AppNoticeType.success : AppNoticeType.info,
      );
    } on CinematyAccountApiException catch (error) {
      if (!mounted) return;
      AppNotice.show(
        context,
        title: 'تعذر تحديث الطلب',
        message: error.message,
        type: AppNoticeType.error,
      );
    } finally {
      if (mounted) setState(() => _busy.remove(request.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CinematyTopBar(
        section: 'الإشعارات',
        showQuickActions: false,
        onBack: () => Navigator.pop(context, true),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading && _requests.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 180),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    if (_error != null && _requests.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 100),
          Icon(
            Icons.notifications_off_outlined,
            size: 46,
            color: Colors.white.withOpacity(.42),
          ),
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(.58)),
          ),
          const SizedBox(height: 14),
          Center(
            child: FilledButton(
              onPressed: _load,
              child: const Text('إعادة المحاولة'),
            ),
          ),
        ],
      );
    }

    if (_requests.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 105),
          Container(
            width: 78,
            height: 78,
            margin: const EdgeInsets.symmetric(horizontal: 100),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(.045),
              border: Border.all(color: Colors.white.withOpacity(.06)),
            ),
            child: Icon(
              Icons.notifications_none_rounded,
              size: 32,
              color: Colors.white.withOpacity(.5),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'لا توجد طلبات صداقة جديدة',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'عند وصول طلب صداقة سيظهر هنا ويمكنك قبوله أو رفضه.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(.45),
              fontSize: 11.5,
              height: 1.55,
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      itemCount: _requests.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, index) {
        final request = _requests[index];
        return _RequestCard(
          request: request,
          busy: _busy.contains(request.id),
          onAccept: () => _respond(request, true),
          onReject: () => _respond(request, false),
          onOpenProfile: () {
            final handle = request.sender.handle;
            if (handle == null || handle.isEmpty) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UserProfileScreen(handle: handle),
              ),
            );
          },
        );
      },
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.busy,
    required this.onAccept,
    required this.onReject,
    required this.onOpenProfile,
  });

  final FriendRequestItem request;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final sender = request.sender;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.035),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(.07)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onOpenProfile,
            child: Row(
              children: [
                _Avatar(url: sender.photoUrl),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sender.displayName.isEmpty
                            ? 'مستخدم سينماتي'
                            : sender.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (sender.handle?.isNotEmpty == true) ...[
                        const SizedBox(height: 3),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            sender.handle!,
                            style: TextStyle(
                              color: AppColors.redBright.withOpacity(.88),
                              fontSize: 10.8,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        'أرسل لك طلب صداقة',
                        style: TextStyle(
                          color: Colors.white.withOpacity(.46),
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_left_rounded,
                  color: Colors.white38,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onAccept,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'قبول',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    minimumSize: const Size.fromHeight(44),
                    side: BorderSide(color: Colors.white.withOpacity(.09)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'رفض',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ],
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
      width: 54,
      height: 54,
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [AppColors.redBright, Color(0xFFFF968D)],
        ),
      ),
      child: ClipOval(
        child: ColoredBox(
          color: AppColors.surfaceHigh,
          child: url.isEmpty
              ? const Icon(Icons.person_rounded, size: 24)
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.person_rounded, size: 24),
                ),
        ),
      ),
    );
  }
}
