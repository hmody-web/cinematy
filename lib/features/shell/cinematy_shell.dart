import 'package:flutter/material.dart';

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

  final _screens = const [
    HomeScreen(),
    DiscoverScreen(),
    SearchScreen(),
    LibraryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: GlassNavigationBar(index: _index, onChanged: (value) => setState(() => _index = value)),
    );
  }
}
