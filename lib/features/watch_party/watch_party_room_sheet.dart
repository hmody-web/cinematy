import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'watch_party_models.dart';
import 'watch_party_service.dart';

class WatchPartyRoomSheet extends StatefulWidget {
  const WatchPartyRoomSheet({super.key, required this.sessionId});

  final String sessionId;

  static Future<bool> show(
    BuildContext context, {
    required String sessionId,
  }) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => WatchPartyRoomSheet(sessionId: sessionId),
    );
    return result == 'leave';
  }

  @override
  State<WatchPartyRoomSheet> createState() => _WatchPartyRoomSheetState();
}

class _WatchPartyRoomSheetState extends State<WatchPartyRoomSheet> {
  bool _saving = false;

  Future<void> _update(
    WatchPartySession session,
    WatchPartyPermissions permissions,
  ) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await WatchPartyService.instance.updatePermissions(
        session: session,
        permissions: permissions,
      );
    } on WatchPartyException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * .88;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        height: height,
        margin: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFA110D0D),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withOpacity(.07)),
        ),
        child: StreamBuilder<WatchPartySession?>(
          stream: WatchPartyService.instance.watchSession(widget.sessionId),
          builder: (context, sessionSnapshot) {
            final session = sessionSnapshot.data;
            if (session == null) {
              return const Center(
                child: CircularProgressIndicator(strokeWidth: 2.2),
              );
            }
            final isHost =
                WatchPartyService.instance.currentUid == session.hostUid;
            return StreamBuilder<List<WatchPartyPresence>>(
              stream:
                  WatchPartyService.instance.watchPresence(widget.sessionId),
              builder: (context, presenceSnapshot) {
                final presence = presenceSnapshot.data ?? const [];
                final presenceByUid = {
                  for (final item in presence) item.uid: item,
                };
                return Column(
                  children: [
                    _header(session, isHost),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                        children: [
                          _roomStatus(session, presenceByUid),
                          const SizedBox(height: 18),
                          _sectionTitle('الأعضاء'),
                          const SizedBox(height: 8),
                          ...session.members.map(
                            (member) => _MemberPresenceTile(
                              member: member,
                              presence: presenceByUid[member.uid],
                              isHost: member.uid == session.hostUid,
                            ),
                          ),
                          const SizedBox(height: 20),
                          _sectionTitle(
                            'صلاحيات التحكم',
                            subtitle: isHost
                                ? 'الصلاحيات مفعلة للجميع افتراضياً ويمكنك تغييرها فوراً.'
                                : 'المضيف هو المسؤول عن تغيير صلاحيات الروم.',
                          ),
                          const SizedBox(height: 8),
                          _permissionsCard(session, isHost),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 50),
                              side: BorderSide(
                                color: Colors.white.withOpacity(.12),
                              ),
                            ),
                            onPressed: () => Navigator.pop(context, 'leave'),
                            icon: const Icon(Icons.logout_rounded),
                            label: Text(
                              isHost ? 'إنهاء المشاهدة والخروج' : 'مغادرة المشاهدة',
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _header(WatchPartySession session, bool isHost) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
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
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.redBright.withOpacity(.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.groups_2_rounded,
                    color: AppColors.redBright,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.groupName?.trim().isNotEmpty == true
                            ? session.groupName!
                            : 'روم المشاهدة',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        isHost ? 'أنت المضيف' : 'مزامنة الشريط والتحكم',
                        style: TextStyle(
                          color: Colors.white.withOpacity(.45),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _roomStatus(
    WatchPartySession session,
    Map<String, WatchPartyPresence> presence,
  ) {
    final active = session.members
        .where((member) => presence[member.uid]?.active == true)
        .length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(.06)),
      ),
      child: Row(
        children: [
          const Icon(Icons.sync_rounded, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$active من ${session.members.length} متصلين الآن • تتم مزامنة أوامر الشريط فقط، وكل فيديو يعمل بشكل مستقل.',
              style: TextStyle(
                color: Colors.white.withOpacity(.62),
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, {String? subtitle}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withOpacity(.42),
                fontSize: 10.8,
                height: 1.4,
              ),
            ),
          ],
        ],
      );

  Widget _permissionsCard(WatchPartySession session, bool isHost) {
    final p = session.permissions;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.03),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(.06)),
      ),
      child: Column(
        children: [
          _PermissionSwitch(
            icon: Icons.play_circle_outline_rounded,
            title: 'تشغيل وإيقاف',
            subtitle: 'يسمح للأعضاء بتشغيل الفيديو أو إيقافه للجميع.',
            value: p.everyoneCanPlayPause,
            enabled: isHost && !_saving,
            onChanged: (value) => _update(
              session,
              p.copyWith(everyoneCanPlayPause: value),
            ),
          ),
          _divider(),
          _PermissionSwitch(
            icon: Icons.fast_forward_rounded,
            title: 'التقديم والرجوع',
            subtitle: 'يشمل +10، -10 وسحب شريط التقدم.',
            value: p.everyoneCanSeek,
            enabled: isHost && !_saving,
            onChanged: (value) =>
                _update(session, p.copyWith(everyoneCanSeek: value)),
          ),
          _divider(),
          _PermissionSwitch(
            icon: Icons.video_library_rounded,
            title: 'تغيير الحلقة',
            subtitle: 'يسمح بالانتقال إلى حلقة أخرى وتغييرها للجميع.',
            value: p.everyoneCanChangeEpisode,
            enabled: isHost && !_saving,
            onChanged: (value) => _update(
              session,
              p.copyWith(everyoneCanChangeEpisode: value),
            ),
          ),
          _divider(),
          _PermissionSwitch(
            icon: Icons.speed_rounded,
            title: 'سرعة التشغيل',
            subtitle: 'تغيير السرعة يصبح متزامناً على كل أعضاء الروم.',
            value: p.everyoneCanChangeSpeed,
            enabled: isHost && !_saving,
            onChanged: (value) => _update(
              session,
              p.copyWith(everyoneCanChangeSpeed: value),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Divider(
        height: 1,
        indent: 58,
        color: Colors.white.withOpacity(.055),
      );
}

class _PermissionSwitch extends StatelessWidget {
  const _PermissionSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
        value: value,
        onChanged: enabled ? onChanged : null,
        secondary: Icon(icon, size: 22),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Colors.white.withOpacity(.4),
            fontSize: 10.5,
            height: 1.4,
          ),
        ),
      );
}

class _MemberPresenceTile extends StatelessWidget {
  const _MemberPresenceTile({
    required this.member,
    required this.presence,
    required this.isHost,
  });

  final WatchPartyMember member;
  final WatchPartyPresence? presence;
  final bool isHost;

  @override
  Widget build(BuildContext context) {
    final active = presence?.active == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.025),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundImage: member.photoUrl.isNotEmpty
                    ? NetworkImage(member.photoUrl)
                    : null,
                child: member.photoUrl.isEmpty
                    ? const Icon(Icons.person_rounded)
                    : null,
              ),
              Positioned(
                left: 0,
                bottom: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? AppColors.success : Colors.white38,
                    border: Border.all(color: const Color(0xFF110D0D), width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.displayName.isNotEmpty
                      ? member.displayName
                      : 'مستخدم سينماتي',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  active ? 'متصل الآن' : 'غير متصل',
                  style: TextStyle(
                    color: Colors.white.withOpacity(.42),
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          if (isHost)
            const Text(
              'المضيف',
              style: TextStyle(
                color: AppColors.redBright,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
              ),
            ),
        ],
      ),
    );
  }
}
