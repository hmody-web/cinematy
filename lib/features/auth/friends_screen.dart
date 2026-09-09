import 'package:flutter/material.dart';

import '../../data/models/cinematy_user.dart';
import '../../data/services/cinematy_account_api.dart';
import 'user_profile_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  bool _loading = true;
  List<CinematyUserProfile> _friends = const [];
  List<CinematyUserProfile> _sent = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait<dynamic>([
        CinematyAccountApi.instance.friends(),
        CinematyAccountApi.instance.outgoingFriendRequests(),
      ]);
      if (!mounted) return;
      setState(() {
        _friends = results[0] as List<CinematyUserProfile>;
        _sent = results[1] as List<CinematyUserProfile>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الأصدقاء')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
                children: [
                  const _SectionTitle('الأصدقاء'),
                  const SizedBox(height: 8),
                  if (_friends.isEmpty)
                    const _EmptyMessage('لا توجد صداقات حتى الآن.')
                  else
                    ..._friends.map((user) => _UserTile(
                          user: user,
                          status: 'أصدقاء',
                          onTap: () => _open(user),
                        )),
                  const SizedBox(height: 22),
                  const _SectionTitle('الطلبات المرسلة'),
                  const SizedBox(height: 8),
                  if (_sent.isEmpty)
                    const _EmptyMessage('لا توجد طلبات معلّقة.')
                  else
                    ..._sent.map((user) => _UserTile(
                          user: user,
                          status: 'تم الإرسال',
                          onTap: () => _open(user),
                        )),
                ],
              ),
            ),
    );
  }

  void _open(CinematyUserProfile user) {
    final handle = user.handle;
    if (handle == null || handle.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UserProfileScreen(handle: handle)),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
      );
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(
          message,
          style: TextStyle(color: Colors.white.withOpacity(.48), fontSize: 12),
        ),
      );
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.user,
    required this.status,
    required this.onTap,
  });

  final CinematyUserProfile user;
  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundImage:
            user.photoUrl.isNotEmpty ? NetworkImage(user.photoUrl) : null,
        child: user.photoUrl.isEmpty ? const Icon(Icons.person_rounded) : null,
      ),
      title: Text(
        user.displayName.isEmpty ? 'مستخدم سينماتي' : user.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: user.handle?.isNotEmpty == true
          ? Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                user.handle!,
                textAlign: TextAlign.left,
                style: TextStyle(color: Colors.white.withOpacity(.5)),
              ),
            )
          : null,
      trailing: Text(
        status,
        style: TextStyle(
          color: Colors.white.withOpacity(.58),
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
