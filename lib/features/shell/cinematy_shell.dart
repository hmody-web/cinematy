import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../widgets/glass_navigation_bar.dart';
import '../discover/discover_screen.dart';
import '../home/home_screen.dart';
import '../library/library_screen.dart';
import '../search/search_screen.dart';
import '../tv/tv_screen.dart';

class CinematyShell extends StatefulWidget {
  const CinematyShell({super.key});

  @override
  State<CinematyShell> createState() => _CinematyShellState();
}

class _CinematyShellState extends State<CinematyShell> {
  int _index = 0;
  bool _compactNavigation = false;

  final _screens = const [
    HomeScreen(),
    DiscoverScreen(),
    SearchScreen(),
    TvScreen(),
    LibraryScreen(),
  ];

  bool _onUserScroll(UserScrollNotification notification) {
    // ScrollDirection.reverse = المستخدم يسحب للأعلى ويتجه لأسفل الصفحة.
    // ScrollDirection.forward = المستخدم يسحب للأسفل ويرجع لأعلى الصفحة.
    final shouldCompact = switch (notification.direction) {
      ScrollDirection.reverse => true,
      ScrollDirection.forward => false,
      ScrollDirection.idle => _compactNavigation,
    };

    if (shouldCompact != _compactNavigation && mounted) {
      setState(() => _compactNavigation = shouldCompact);
    }
    return false;
  }

  void _changeTab(int value) {
    if (value == _index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _index = value;
      // عند تغيير القسم نعيد البار لحجمه الطبيعي حتى لا يبدأ القسم الجديد
      // بحالة مصغرة من القسم السابق.
      _compactNavigation = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = NotificationListener<UserScrollNotification>(
      onNotification: _onUserScroll,
      child: IndexedStack(index: _index, children: _screens),
    );

    // Keep the existing native mobile/tablet layout completely untouched.
    if (!kIsWeb) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: content,
        bottomNavigationBar: GlassNavigationBar(
          index: _index,
          compact: _compactNavigation,
          onChanged: _changeTab,
        ),
      );
    }

    // Chrome is our lightweight TV preview. TV navigation is intentionally
    // isolated here: a full-height rail on the RIGHT, while phone/tablet
    // continue using their native bottom bars exactly as before.
    final tvPreview = Scaffold(
      backgroundColor: Colors.transparent,
      body: Row(
        textDirection: TextDirection.rtl,
        children: [
          SizedBox(
            width: 132,
            child: GlassNavigationBar(
              index: _index,
              compact: false,
              onChanged: _changeTab,
            ),
          ),
          Expanded(child: content),
        ],
      ),
    );

    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: tvPreview,
    );
  }
}
