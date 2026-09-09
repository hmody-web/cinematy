import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/cinematy_user.dart';
import '../../data/models/media_item.dart';
import '../../data/services/cinematy_account_api.dart';
import '../../widgets/network_image.dart';
import 'watch_party_models.dart';
import 'watch_party_service.dart';

enum _LauncherStep { home, friend, waitingFriend, groups, createGroup }

class WatchPartyLauncherSheet extends StatefulWidget {
  const WatchPartyLauncherSheet({super.key, required this.media});

  final MediaItem media;

  static Future<WatchPartySession?> show(
    BuildContext context, {
    required MediaItem media,
  }) {
    return showModalBottomSheet<WatchPartySession>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => WatchPartyLauncherSheet(media: media),
    );
  }

  @override
  State<WatchPartyLauncherSheet> createState() =>
      _WatchPartyLauncherSheetState();
}

class _WatchPartyLauncherSheetState extends State<WatchPartyLauncherSheet> {
  _LauncherStep _step = _LauncherStep.home;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<CinematyUserProfile> _friends = const [];
  List<WatchPartyGroup> _groups = const [];
  final Set<String> _selectedUids = <String>{};
  final TextEditingController _groupNameController = TextEditingController();

  WatchPartySession? _waitingSession;
  CinematyUserProfile? _waitingFriend;
  StreamSubscription<WatchPartyInvite?>? _waitingInviteSub;
  String _waitingStatus = 'pending';
  bool _openingAcceptedParty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _waitingInviteSub?.cancel();
    final waitingSession = _waitingSession;
    if (waitingSession != null && !_openingAcceptedParty) {
      unawaited(
        WatchPartyService.instance
            .cancelPendingSession(waitingSession)
            .catchError((_) {}),
      );
    }
    _groupNameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        CinematyAccountApi.instance.friends(),
        WatchPartyService.instance.groups(),
      ]);
      if (!mounted) return;
      setState(() {
        _friends = results[0] as List<CinematyUserProfile>;
        _groups = results[1] as List<WatchPartyGroup>;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is WatchPartyException
            ? error.message
            : 'تعذر تحميل الأصدقاء والمجموعات حالياً.';
      });
    }
  }

  Future<void> _startWithFriend(CinematyUserProfile friend) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = await WatchPartyService.instance.createDirectSession(
        media: widget.media,
        friend: friend,
      );
      if (!mounted) return;
      await _beginWaitingForFriend(session, friend);
    } on WatchPartyException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('تعذر إنشاء جلسة المشاهدة. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _beginWaitingForFriend(
    WatchPartySession session,
    CinematyUserProfile friend,
  ) async {
    await _waitingInviteSub?.cancel();
    _openingAcceptedParty = false;
    if (!mounted) return;
    setState(() {
      _waitingSession = session;
      _waitingFriend = friend;
      _waitingStatus = 'pending';
      _step = _LauncherStep.waitingFriend;
    });

    _waitingInviteSub = WatchPartyService.instance
        .watchInvite(sessionId: session.id, toUid: friend.uid)
        .listen(
      (invite) async {
        if (!mounted || _waitingSession?.id != session.id || invite == null) {
          return;
        }

        if (invite.status == 'accepted') {
          if (_openingAcceptedParty) return;
          _openingAcceptedParty = true;
          setState(() => _waitingStatus = 'accepted');
          await Future<void>.delayed(const Duration(milliseconds: 700));
          if (!mounted || _waitingSession?.id != session.id) return;
          await _waitingInviteSub?.cancel();
          _waitingInviteSub = null;
          if (mounted) Navigator.pop(context, session);
          return;
        }

        if (invite.status == 'declined' ||
            invite.status == 'expired' ||
            invite.status == 'ended' ||
            invite.status == 'cancelled') {
          setState(() => _waitingStatus = invite.status);
        }
      },
      onError: (_) {
        if (!mounted || _waitingSession?.id != session.id) return;
        setState(() => _waitingStatus = 'error');
      },
    );
  }

  Future<void> _cancelWaiting({bool returnToFriends = true}) async {
    final session = _waitingSession;
    if (session == null || _busy) return;
    setState(() => _busy = true);
    await _waitingInviteSub?.cancel();
    _waitingInviteSub = null;
    try {
      await WatchPartyService.instance.cancelPendingSession(session);
    } catch (error) {
      if (mounted && error is WatchPartyException) {
        _showError(error.message);
      }
    } finally {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _waitingSession = null;
        _waitingFriend = null;
        _waitingStatus = 'pending';
        _openingAcceptedParty = false;
        if (returnToFriends) _step = _LauncherStep.friend;
      });
    }
  }

  Future<void> _startWithGroup(WatchPartyGroup group) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = await WatchPartyService.instance.createGroupSession(
        media: widget.media,
        group: group,
      );
      if (!mounted) return;
      Navigator.pop(context, session);
    } on WatchPartyException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('تعذر بدء المشاهدة مع هذه المجموعة.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createGroupAndStart() async {
    if (_busy) return;
    final selected = _friends
        .where((friend) => _selectedUids.contains(friend.uid))
        .toList();
    if (selected.isEmpty) {
      _showError('اختر صديقاً واحداً على الأقل.');
      return;
    }
    setState(() => _busy = true);
    try {
      final group = await WatchPartyService.instance.createGroup(
        name: _groupNameController.text,
        friends: selected,
      );
      final session = await WatchPartyService.instance.createGroupSession(
        media: widget.media,
        group: group,
      );
      if (!mounted) return;
      Navigator.pop(context, session);
    } on WatchPartyException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('تعذر إنشاء المجموعة حالياً.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _back() {
    if (_step == _LauncherStep.waitingFriend) {
      unawaited(_cancelWaiting());
      return;
    }
    if (_step == _LauncherStep.home) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _step = _step == _LauncherStep.createGroup
          ? _LauncherStep.groups
          : _LauncherStep.home;
      _selectedUids.clear();
      _groupNameController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * .84;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        height: height,
        margin: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: const Color(0xFA110D0D),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withOpacity(.07)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 38,
              offset: Offset(0, 18),
            ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              children: [
                _header(),
                Expanded(child: _body()),
              ],
            ),
            if (_busy)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(.56),
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(strokeWidth: 2.4),
                        SizedBox(height: 12),
                        Text(
                          'جاري تجهيز الروم…',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final title = switch (_step) {
      _LauncherStep.home => 'مشاهدة جماعية',
      _LauncherStep.friend => 'مشاهدة مع صديق',
      _LauncherStep.waitingFriend => 'بانتظار الموافقة',
      _LauncherStep.groups => 'مشاهدة مع مجموعة',
      _LauncherStep.createGroup => 'مجموعة جديدة',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Column(
        children: [
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.18),
              borderRadius: BorderRadius.circular(100),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: _back,
                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      widget.media.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(.45),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 44,
                height: 58,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white.withOpacity(.05),
                ),
                child: CinematyNetworkImage(
                  url: widget.media.posterUrl,
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.2));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.wifi_tethering_error_rounded,
                size: 42,
                color: Colors.white.withOpacity(.45),
              ),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              FilledButton(onPressed: _load, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
    }
    return switch (_step) {
      _LauncherStep.home => _home(),
      _LauncherStep.friend => _friendList(),
      _LauncherStep.waitingFriend => _waitingFriendBody(),
      _LauncherStep.groups => _groupList(),
      _LauncherStep.createGroup => _createGroup(),
    };
  }

  Widget _home() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(
            'اختر طريقة المشاهدة',
            style: TextStyle(
              color: Colors.white.withOpacity(.55),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          _ModeCard(
            icon: Icons.person_add_alt_1_rounded,
            title: 'دعوة صديق',
            subtitle: 'اختر صديقاً واحداً وأرسل له دعوة مباشرة لهذا العمل.',
            accent: AppColors.redBright,
            onTap: () => setState(() => _step = _LauncherStep.friend),
          ),
          const SizedBox(height: 12),
          _ModeCard(
            icon: Icons.groups_2_rounded,
            title: 'مشاهدة مع مجموعة',
            subtitle:
                'استخدم مجموعة محفوظة أو أنشئ مجموعة جديدة تبقى داخل مكتبتي.',
            accent: const Color(0xFF8B74FF),
            onTap: () => setState(() => _step = _LauncherStep.groups),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.025),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(.055)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.sync_rounded,
                  size: 21,
                  color: Colors.white.withOpacity(.65),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'التشغيل، الإيقاف، التقديم، الرجوع وتغيير الحلقة تتم مزامنتها فورياً. الصلاحيات تبدأ للجميع ويمكن للمضيف تعديلها من داخل الروم.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(.52),
                      fontSize: 11.5,
                      height: 1.55,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _friendList() {
    if (_friends.isEmpty) {
      return _emptyFriends();
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      itemCount: _friends.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        final friend = _friends[index];
        return _FriendChoiceTile(
          user: friend,
          trailing: const Icon(Icons.send_rounded, size: 20),
          onTap: () => _startWithFriend(friend),
        );
      },
    );
  }

  Widget _waitingFriendBody() {
    final friend = _waitingFriend;
    final session = _waitingSession;
    if (friend == null || session == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.2));
    }

    final name = friend.displayName.trim().isNotEmpty
        ? friend.displayName.trim()
        : 'صديقك';
    final accepted = _waitingStatus == 'accepted';
    final declined = _waitingStatus == 'declined';
    final expired = _waitingStatus == 'expired' || _waitingStatus == 'ended';
    final failed = _waitingStatus == 'error';

    final title = accepted
        ? 'وافق $name على الدعوة'
        : declined
            ? 'رفض $name الدعوة'
            : expired
                ? 'انتهت الدعوة'
                : failed
                    ? 'تعذر متابعة حالة الدعوة'
                    : 'بانتظار موافقة $name للدخول';

    final subtitle = accepted
        ? 'جاري إدخالكما إلى المشاهدة الجماعية…'
        : declined
            ? 'لن تبدأ المشاهدة. تقدر ترجع وتدعو صديقاً آخر.'
            : expired
                ? 'هذه الجلسة لم تعد متاحة. ارجع وأرسل دعوة جديدة.'
                : failed
                    ? 'تحقق من اتصالك وحاول مرة أخرى.'
                    : 'لن يبدأ الفيلم عندك قبل أن يقبل الطرف الآخر الدعوة.';

    final statusColor = accepted
        ? const Color(0xFF45D483)
        : (declined || expired || failed)
            ? AppColors.redBright
            : const Color(0xFF8B74FF);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        const SizedBox(height: 8),
        Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 104,
                height: 104,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: statusColor.withOpacity(.45), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withOpacity(.14),
                      blurRadius: 28,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: CircleAvatar(
                  backgroundColor: Colors.white.withOpacity(.06),
                  backgroundImage: friend.photoUrl.isNotEmpty
                      ? NetworkImage(friend.photoUrl)
                      : null,
                  child: friend.photoUrl.isEmpty
                      ? const Icon(Icons.person_rounded, size: 44)
                      : null,
                ),
              ),
              Positioned(
                left: -2,
                bottom: 2,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor,
                    border: Border.all(color: const Color(0xFF110D0D), width: 3),
                  ),
                  child: Icon(
                    accepted
                        ? Icons.check_rounded
                        : (declined || expired || failed)
                            ? Icons.close_rounded
                            : Icons.hourglass_top_rounded,
                    size: 17,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(.5),
            fontSize: 12,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.028),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(.06)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 64,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  color: Colors.white.withOpacity(.05),
                ),
                child: CinematyNetworkImage(
                  url: widget.media.posterUrl,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.media.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'دعوة مشاهدة جماعية خاصة بكما',
                      style: TextStyle(
                        color: Colors.white.withOpacity(.42),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (!accepted && !declined && !expired && !failed)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (accepted)
          Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(.1),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: statusColor.withOpacity(.2)),
            ),
            child: const Text(
              'تمت الموافقة — جاري بدء المشاهدة…',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          )
        else if (declined || expired)
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: () => unawaited(_cancelWaiting()),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text(
                'الرجوع إلى الأصدقاء',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          )
        else if (failed)
          Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: () => unawaited(_beginWaitingForFriend(session, friend)),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text(
                    'إعادة الاتصال',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(height: 9),
              TextButton(
                onPressed: () => unawaited(_cancelWaiting()),
                child: const Text('إلغاء الدعوة'),
              ),
            ],
          )
        else
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () => unawaited(_cancelWaiting()),
              icon: const Icon(Icons.close_rounded),
              label: const Text(
                'إلغاء الدعوة',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
      ],
    );
  }

  Widget _groupList() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        InkWell(
          onTap: () => setState(() => _step = _LauncherStep.createGroup),
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: AppColors.redBright.withOpacity(.09),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.redBright.withOpacity(.22)),
            ),
            child: const Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Color(0x22FF473D),
                  child: Icon(Icons.add_rounded, color: AppColors.redBright),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إنشاء مجموعة جديدة',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'سمّ المجموعة واختر الأصدقاء، وستبقى محفوظة في مكتبتي.',
                        style: TextStyle(fontSize: 10.8, color: Color(0x99FFFFFF)),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_back_ios_new_rounded, size: 16),
              ],
            ),
          ),
        ),
        if (_groups.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'مجموعاتك',
            style: TextStyle(
              color: Colors.white.withOpacity(.55),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          ..._groups.map(
            (group) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _GroupChoiceTile(
                group: group,
                onTap: () => _startWithGroup(group),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _createGroup() {
    if (_friends.isEmpty) return _emptyFriends();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: TextField(
            controller: _groupNameController,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'اسم المجموعة',
              hintText: 'مثلاً: ليلة الجمعة',
              prefixIcon: Icon(Icons.group_work_rounded),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              const Text(
                'اختر الأصدقاء',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
              ),
              const Spacer(),
              Text(
                '${_selectedUids.length} محدد',
                style: TextStyle(
                  color: Colors.white.withOpacity(.45),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _friends.length,
            itemBuilder: (_, index) {
              final friend = _friends[index];
              final selected = _selectedUids.contains(friend.uid);
              return Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: _FriendChoiceTile(
                  user: friend,
                  selected: selected,
                  trailing: Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: selected
                        ? AppColors.redBright
                        : Colors.white.withOpacity(.28),
                  ),
                  onTap: () => setState(() {
                    if (selected) {
                      _selectedUids.remove(friend.uid);
                    } else {
                      _selectedUids.add(friend.uid);
                    }
                  }),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: _selectedUids.isEmpty ? null : _createGroupAndStart,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text(
                'إنشاء المجموعة وبدء المشاهدة',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyFriends() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.people_outline_rounded,
                size: 46,
                color: Colors.white.withOpacity(.4),
              ),
              const SizedBox(height: 12),
              const Text(
                'ما عندك أصدقاء بعد',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              const SizedBox(height: 5),
              Text(
                'أضف أصدقاء من قسم الحساب أولاً، وبعدها تقدر تدعوهم للمشاهدة.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(.46),
                  fontSize: 11.5,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      );
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.035),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(.07)),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: accent.withOpacity(.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: accent, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(.48),
                        fontSize: 11.3,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
            ],
          ),
        ),
      );
}

class _FriendChoiceTile extends StatelessWidget {
  const _FriendChoiceTile({
    required this.user,
    required this.trailing,
    required this.onTap,
    this.selected = false,
  });

  final CinematyUserProfile user;
  final Widget trailing;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.redBright.withOpacity(.075)
                : Colors.white.withOpacity(.028),
            borderRadius: BorderRadius.circular(19),
            border: Border.all(
              color: selected
                  ? AppColors.redBright.withOpacity(.2)
                  : Colors.white.withOpacity(.055),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 23,
                backgroundColor: Colors.white.withOpacity(.06),
                backgroundImage:
                    user.photoUrl.isNotEmpty ? NetworkImage(user.photoUrl) : null,
                child:
                    user.photoUrl.isEmpty ? const Icon(Icons.person_rounded) : null,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName.isNotEmpty
                          ? user.displayName
                          : 'مستخدم سينماتي',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    if (user.handle?.isNotEmpty == true)
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          user.handle!,
                          textAlign: TextAlign.left,
                          style: TextStyle(
                            color: Colors.white.withOpacity(.42),
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              trailing,
            ],
          ),
        ),
      );
}

class _GroupChoiceTile extends StatelessWidget {
  const _GroupChoiceTile({required this.group, required this.onTap});

  final WatchPartyGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.03),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(.055)),
          ),
          child: Row(
            children: [
              _AvatarStack(members: group.members),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${group.members.length} أعضاء',
                      style: TextStyle(
                        color: Colors.white.withOpacity(.43),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.play_circle_fill_rounded, size: 28),
            ],
          ),
        ),
      );
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.members});
  final List<WatchPartyMember> members;

  @override
  Widget build(BuildContext context) {
    final visible = members.take(3).toList();
    return SizedBox(
      width: 62,
      height: 40,
      child: Stack(
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              right: i * 17.0,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceHigh,
                  border: Border.all(color: const Color(0xFF110D0D), width: 2),
                  image: visible[i].photoUrl.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(visible[i].photoUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: visible[i].photoUrl.isEmpty
                    ? const Icon(Icons.person_rounded, size: 18)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}
