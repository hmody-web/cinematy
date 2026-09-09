import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/cinematy_user.dart';
import '../../data/models/media_item.dart';
import '../../data/services/cinematy_account_api.dart';
import '../../providers.dart';
import '../../widgets/cinematy_top_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/media_card.dart';
import '../../widgets/shimmer.dart';
import '../auth/account_screen.dart';
import '../auth/user_profile_screen.dart';
import '../details/details_screen.dart';
import '../library/library_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with AutomaticKeepAliveClientMixin {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<MediaItem> _allResults = const [];
  List<MediaItem> _results = const [];
  List<CinematyUserProfile> _users = const [];
  bool _loading = false;
  String _filter = 'الكل';
  String? _error;
  int _requestSerial = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  bool get _usersMode => _filter == 'مستخدمين';

  void _changed(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () => _search(value));
    setState(() {});
  }

  Future<void> _search(String value) async {
    final q = value.trim();
    final serial = ++_requestSerial;
    if (q.length < 2) {
      if (!mounted) return;
      setState(() {
        _allResults = const [];
        _results = const [];
        _users = const [];
        _loading = false;
        _error = null;
      });
      return;
    }

    if (_usersMode && FirebaseAuth.instance.currentUser == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _users = const [];
        _error = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_usersMode) {
        final users = await CinematyAccountApi.instance.searchUsers(q);
        if (!mounted || serial != _requestSerial) return;
        setState(() {
          _users = users;
          _loading = false;
        });
        return;
      }

      final data = await ref.read(apiProvider).searchAll(q);
      if (!mounted || serial != _requestSerial) return;
      _allResults = data;
      _applyFilter();
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _loading = false;
        _error = 'تعذر إكمال البحث. حاول مرة أخرى.';
      });
    }
  }

  void _applyFilter() {
    switch (_filter) {
      case 'أفلام':
        _results = _allResults.where((e) => !e.isSeries).toList();
        break;
      case 'مسلسلات':
        _results = _allResults.where((e) => e.isSeries).toList();
        break;
      default:
        _results = [..._allResults];
    }
  }

  void _changeFilter(String value) {
    setState(() {
      _filter = value;
      _error = null;
      if (value != 'مستخدمين') {
        _applyFilter();
      } else {
        _users = const [];
      }
    });
    if (_controller.text.trim().length >= 2) {
      _search(_controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final downloads = ref.watch(downloadProvider);
    return Scaffold(
      appBar: CinematyTopBar(
        section: 'البحث',
        downloadsCount: downloads.items.length + downloads.activeItems.length,
        onContinue: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ContinueWatchingScreen()),
        ),
        onDownloads: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DownloadsScreen()),
        ),
      ),
      body: CustomScrollView(
        key: const PageStorageKey('search-scroll'),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
              child: TextField(
                controller: _controller,
                autofocus: false,
                textInputAction: TextInputAction.search,
                onChanged: _changed,
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: _usersMode
                      ? 'ابحث بالاسم أو معرّف سينماتي…'
                      : 'ابحث عن فيلم، مسلسل أو ممثل…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _controller.clear();
                            _changed('');
                          },
                        ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 48,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                scrollDirection: Axis.horizontal,
                children: ['الكل', 'أفلام', 'مسلسلات', 'مستخدمين']
                    .map(
                      (f) => Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ChoiceChip(
                          selected: _filter == f,
                          label: Text(f),
                          selectedColor: AppColors.red.withOpacity(.35),
                          onSelected: (_) => _changeFilter(f),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          if (_usersMode)
            ..._buildUsersSlivers()
          else
            ..._buildMediaSlivers(),
        ],
      ),
    );
  }

  List<Widget> _buildUsersSlivers() {
    if (FirebaseAuth.instance.currentUser == null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_alt_rounded, size: 48, color: Colors.white.withOpacity(.22)),
                  const SizedBox(height: 14),
                  const Text(
                    'سجّل الدخول للبحث عن المستخدمين',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'يمكن البحث بالاسم أو معرّف حساب سينماتي.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withOpacity(.48), height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AccountScreen()),
                    ),
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('تسجيل الدخول'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    if (_loading) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    if (_error != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            title: 'تعذر البحث عن المستخدمين',
            message: _error!,
            onRetry: () => _search(_controller.text),
          ),
        ),
      ];
    }

    if (_controller.text.trim().length < 2) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.people_alt_rounded,
            title: 'ابحث عن مستخدمي سينماتي',
            message: 'اكتب الاسم أو معرّف الحساب للعثور على الملف الشخصي.',
          ),
        ),
      ];
    }

    if (_users.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.person_search_rounded,
            title: 'ما لقينا مستخدمين',
            message: 'تأكد من الاسم أو معرّف سينماتي وحاول مرة أخرى.',
          ),
        ),
      ];
    }

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: Text(
            '${_users.length} مستخدم',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 130),
        sliver: SliverList.separated(
          itemCount: _users.length,
          separatorBuilder: (_, __) => const SizedBox(height: 9),
          itemBuilder: (_, index) {
            final user = _users[index];
            return _UserSearchCard(
              user: user,
              onTap: () {
                final handle = user.handle;
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
        ),
      ),
    ];
  }

  List<Widget> _buildMediaSlivers() {
    if (_loading) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 4),
            child: Row(children: [SkeletonBox(width: 118, height: 14, radius: 7)]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 130),
          sliver: SliverGrid.builder(
            itemCount: 9,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 16,
              childAspectRatio: .52,
            ),
            itemBuilder: (_, __) => const SkeletonPosterCard(width: double.infinity),
          ),
        ),
      ];
    }

    if (_error != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            title: 'تعذر البحث',
            message: 'حاول مرة أخرى بعد قليل.',
            onRetry: () => _search(_controller.text),
          ),
        ),
      ];
    }

    if (_controller.text.trim().length < 2) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.search_rounded,
            title: 'شنو تحب تشوف اليوم؟',
            message: 'اكتب حرفين أو أكثر للبحث عن الأفلام والمسلسلات والممثلين.',
          ),
        ),
      ];
    }

    if (_results.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            title: 'ما لقينا نتائج',
            message: 'جرّب الاسم بالعربية أو الإنجليزية.',
          ),
        ),
      ];
    }

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
          child: Text(
            '${_results.length} نتيجة',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 130),
        sliver: SliverGrid.builder(
          itemCount: _results.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 16,
            childAspectRatio: .52,
          ),
          itemBuilder: (_, i) {
            final item = _results[i];
            return MediaPosterCard(
              item: item,
              width: double.infinity,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => DetailsScreen(item: item)),
              ),
            );
          },
        ),
      ),
    ];
  }
}

class _UserSearchCard extends StatelessWidget {
  const _UserSearchCard({required this.user, required this.onTap});

  final CinematyUserProfile user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.035),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(.06)),
          ),
          child: Row(
            children: [
              ClipOval(
                child: SizedBox(
                  width: 50,
                  height: 50,
                  child: ColoredBox(
                    color: AppColors.surfaceHigh,
                    child: user.photoUrl.isEmpty
                        ? const Icon(Icons.person_rounded)
                        : Image.network(
                            user.photoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName.isEmpty ? 'مستخدم سينماتي' : user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        user.handle ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.redBright.withOpacity(.86),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left_rounded, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}
