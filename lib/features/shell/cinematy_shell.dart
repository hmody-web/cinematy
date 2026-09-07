import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../widgets/glass_navigation_bar.dart';
import '../discover/discover_screen.dart';
import '../home/home_screen.dart';
import '../library/library_screen.dart';
import '../search/search_screen.dart';

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
    return Scaffold(
      extendBody: true,
      body: NotificationListener<UserScrollNotification>(
        onNotification: _onUserScroll,
        child: IndexedStack(index: _index, children: _screens),
      ),
      bottomNavigationBar: GlassNavigationBar(
        index: _index,
        compact: _compactNavigation,
        onChanged: _changeTab,
      ),
    );
  }
}
