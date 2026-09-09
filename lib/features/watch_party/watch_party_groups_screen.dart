import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/cinematy_user.dart';
import '../../data/services/cinematy_account_api.dart';
import '../../widgets/cinematy_top_bar.dart';
import 'watch_party_models.dart';
import 'watch_party_service.dart';

class WatchPartyGroupsScreen extends StatelessWidget {
  const WatchPartyGroupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final signedIn = FirebaseAuth.instance.currentUser != null;
    return Scaffold(
      appBar: CinematyTopBar(
        section: 'مجموعات المشاهدة',
        showQuickActions: false,
        onBack: () => Navigator.pop(context),
      ),
      floatingActionButton: signedIn
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(context),
              icon: const Icon(Icons.group_add_rounded),
              label: const Text(
                'مجموعة جديدة',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            )
          : null,
      body: !signedIn
          ? const _SignedOutGroups()
          : StreamBuilder<List<WatchPartyGroup>>(
              stream: WatchPartyService.instance.watchGroups(),
              builder: (context, snapshot) {
                if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(strokeWidth: 2.2));
                }
                if (snapshot.hasError) {
                  return const _GroupsError();
                }
                final groups = snapshot.data ?? const <WatchPartyGroup>[];
                if (groups.isEmpty) {
                  return const _EmptyGroups();
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 120),
                  itemCount: groups.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, index) => _GroupCard(
                    group: groups[index],
                    onTap: () => _showGroup(context, groups[index]),
                  ),
                );
              },
            ),
    );
  }

  static Future<void> _openEditor(
    BuildContext context, {
    WatchPartyGroup? group,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _GroupEditorSheet(group: group),
    );
  }

  static Future<void> _showGroup(
    BuildContext context,
    WatchPartyGroup group,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => _GroupDetailsSheet(group: group),
    );
    if (!context.mounted || action == null) return;
    if (action == 'edit') {
      await _openEditor(context, group: group);
      return;
    }
    if (action == 'delete') {
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _DeleteGroupSheet(group: group),
      );
      if (confirmed != true || !context.mounted) return;
      try {
        await WatchPartyService.instance.deleteGroup(group);
      } on WatchPartyException catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    }
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.onTap});

  final WatchPartyGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(.06)),
        ),
        child: Row(
          children: [
            _MemberAvatarStack(members: group.members),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${group.members.length} أعضاء • جاهزة للمشاهدة من أي فيلم أو مسلسل',
                    style: TextStyle(
                      color: Colors.white.withOpacity(.45),
                      fontSize: 10.8,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_back_ios_new_rounded, size: 17),
          ],
        ),
      ),
    );
  }
}

class _GroupDetailsSheet extends StatelessWidget {
  const _GroupDetailsSheet({required this.group});
  final WatchPartyGroup group;

  @override
  Widget build(BuildContext context) {
    final isOwner = WatchPartyService.instance.currentUid == group.ownerUid;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        decoration: BoxDecoration(
          color: const Color(0xFA120E0E),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withOpacity(.07)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.18),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _MemberAvatarStack(members: group.members),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${group.members.length} أعضاء',
                          style: TextStyle(
                            color: Colors.white.withOpacity(.46),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'الأعضاء',
                style: TextStyle(
                  color: Colors.white.withOpacity(.55),
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: group.members.length,
                  itemBuilder: (_, index) {
                    final member = group.members[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundImage: member.photoUrl.isNotEmpty
                            ? NetworkImage(member.photoUrl)
                            : null,
                        child: member.photoUrl.isEmpty
                            ? const Icon(Icons.person_rounded)
                            : null,
                      ),
                      title: Text(
                        member.displayName.isNotEmpty
                            ? member.displayName
                            : 'مستخدم سينماتي',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      trailing: member.uid == group.ownerUid
                          ? const Text(
                              'المالك',
                              style: TextStyle(
                                color: AppColors.redBright,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                              ),
                            )
                          : null,
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'لبدء المشاهدة، افتح أي فيلم أو مسلسل واضغط «مشاهدة جماعية» ثم اختر هذه المجموعة.',
                style: TextStyle(
                  color: Colors.white.withOpacity(.46),
                  fontSize: 11.3,
                  height: 1.5,
                ),
              ),
              if (isOwner) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(context, 'edit'),
                        icon: const Icon(Icons.edit_rounded),
                        label: const Text(
                          'تعديل المجموعة',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'حذف المجموعة',
                      onPressed: () => Navigator.pop(context, 'delete'),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupEditorSheet extends StatefulWidget {
  const _GroupEditorSheet({this.group});
  final WatchPartyGroup? group;

  @override
  State<_GroupEditorSheet> createState() => _GroupEditorSheetState();
}

class _GroupEditorSheetState extends State<_GroupEditorSheet> {
  late final TextEditingController _nameController;
  bool _loading = true;
  bool _busy = false;
  List<CinematyUserProfile> _friends = const [];
  final Set<String> _selected = <String>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.group?.name ?? '');
    final existing = widget.group;
    if (existing != null) {
      _selected.addAll(
        existing.members
            .where((e) => e.uid != existing.ownerUid)
            .map((e) => e.uid),
      );
    }
    _loadFriends();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    try {
      final friends = await CinematyAccountApi.instance.friends();
      if (!mounted) return;
      setState(() {
        _friends = friends;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل قائمة الأصدقاء.';
      });
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final selectedFriends = _friends.where((e) => _selected.contains(e.uid)).toList();
    setState(() => _busy = true);
    try {
      if (widget.group == null) {
        await WatchPartyService.instance.createGroup(
          name: _nameController.text,
          friends: selectedFriends,
        );
      } else {
        await WatchPartyService.instance.updateGroup(
          group: widget.group!,
          name: _nameController.text,
          friends: selectedFriends,
        );
      }
      if (!mounted) return;
      Navigator.pop(context);
    } on WatchPartyException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('تعذر حفظ المجموعة حالياً.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * .82;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        height: height,
        margin: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFA120E0E),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withOpacity(.07)),
        ),
        child: Column(
          children: [
            Padding(
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
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.group == null
                              ? 'إنشاء مجموعة مشاهدة'
                              : 'تعديل المجموعة',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
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
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'اسم المجموعة',
                  prefixIcon: Icon(Icons.group_work_rounded),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  const Text(
                    'الأصدقاء',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const Spacer(),
                  Text(
                    '${_selected.length} محدد',
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
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2.2))
                  : _error != null
                      ? Center(child: Text(_error!))
                      : _friends.isEmpty
                          ? const Center(child: Text('ما عندك أصدقاء لإضافتهم بعد.'))
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              itemCount: _friends.length,
                              itemBuilder: (_, index) {
                                final friend = _friends[index];
                                final selected = _selected.contains(friend.uid);
                                return CheckboxListTile(
                                  value: selected,
                                  onChanged: (_) => setState(() {
                                    if (selected) {
                                      _selected.remove(friend.uid);
                                    } else {
                                      _selected.add(friend.uid);
                                    }
                                  }),
                                  secondary: CircleAvatar(
                                    backgroundImage: friend.photoUrl.isNotEmpty
                                        ? NetworkImage(friend.photoUrl)
                                        : null,
                                    child: friend.photoUrl.isEmpty
                                        ? const Icon(Icons.person_rounded)
                                        : null,
                                  ),
                                  title: Text(
                                    friend.displayName.isNotEmpty
                                        ? friend.displayName
                                        : 'مستخدم سينماتي',
                                    style: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                  subtitle: friend.handle?.isNotEmpty == true
                                      ? Text(friend.handle!)
                                      : null,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                );
                              },
                            ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: _busy
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(
                    widget.group == null ? 'حفظ المجموعة' : 'حفظ التعديلات',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteGroupSheet extends StatelessWidget {
  const _DeleteGroupSheet({required this.group});
  final WatchPartyGroup group;

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFA120E0E),
            borderRadius: BorderRadius.circular(28),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.delete_outline_rounded, size: 38),
                const SizedBox(height: 10),
                Text(
                  'حذف «${group.name}»؟',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  'سيتم حذف المجموعة فقط، ولن يؤثر هذا على أصدقائك.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(.48), fontSize: 11.5),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('حذف'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('إلغاء'),
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

class _MemberAvatarStack extends StatelessWidget {
  const _MemberAvatarStack({required this.members});
  final List<WatchPartyMember> members;

  @override
  Widget build(BuildContext context) {
    final visible = members.take(3).toList();
    return SizedBox(
      width: 68,
      height: 46,
      child: Stack(
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              right: i * 18.0,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceHigh,
                  border: Border.all(color: AppColors.surface, width: 2),
                  image: visible[i].photoUrl.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(visible[i].photoUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: visible[i].photoUrl.isEmpty
                    ? const Icon(Icons.person_rounded, size: 19)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyGroups extends StatelessWidget {
  const _EmptyGroups();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.groups_2_outlined, size: 52, color: Color(0x88FFFFFF)),
              SizedBox(height: 14),
              Text(
                'ما عندك مجموعات مشاهدة بعد',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 6),
              Text(
                'أنشئ مجموعة من هنا أو من زر المشاهدة الجماعية داخل صفحة أي فيلم أو مسلسل.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: Color(0x88FFFFFF), height: 1.5),
              ),
            ],
          ),
        ),
      );
}

class _SignedOutGroups extends StatelessWidget {
  const _SignedOutGroups();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'سجّل الدخول أولاً حتى تظهر مجموعات المشاهدة المرتبطة بحسابك.',
            textAlign: TextAlign.center,
          ),
        ),
      );
}

class _GroupsError extends StatelessWidget {
  const _GroupsError();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'تعذر تحميل مجموعات المشاهدة حالياً.',
            textAlign: TextAlign.center,
          ),
        ),
      );
}
