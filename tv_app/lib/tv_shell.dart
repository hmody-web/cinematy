import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/tv_discover_screen.dart';
import 'screens/tv_home_screen.dart';
import 'screens/tv_library_screen.dart';
import 'screens/tv_live_screen.dart';
import 'screens/tv_search_screen.dart';
import 'tv_focus.dart';
import 'tv_app_exit.dart';
import 'tv_theme.dart';
import 'tv_platform_ui.dart';

class TvShell extends StatefulWidget {
  const TvShell({super.key});

  @override
  State<TvShell> createState() => _TvShellState();
}

class _TvShellState extends State<TvShell> {
  int _index = 0;
  DateTime? _lastBackPress;

  static const _items = <(IconData, String)>[
    (Icons.home_rounded, 'الرئيسية'),
    (Icons.explore_rounded, 'اكتشف'),
    (Icons.search_rounded, 'البحث'),
    (Icons.live_tv_rounded, 'التلفاز'),
    (Icons.video_library_rounded, 'مكتبتي'),
  ];

  Widget _screen() => switch (_index) {
        0 => const TvHomeScreen(),
        1 => const TvDiscoverScreen(),
        2 => const TvSearchScreen(),
        3 => const TvLiveScreen(),
        _ => const TvLibraryScreen(),
      };

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        final now = DateTime.now();
        final last = _lastBackPress;

        if (last == null ||
            now.difference(last) > const Duration(seconds: 2)) {
          _lastBackPress = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              duration: Duration(seconds: 2),
              content: Text(
                'اضغط رجوع مرة ثانية للخروج من سينماتي',
                textAlign: TextAlign.center,
              ),
            ),
          );
          return false;
        }

        SystemNavigator.pop();
        return false;
      },
      child: Scaffold(
      body: Row(
        textDirection: TextDirection.rtl,
        children: [
          SizedBox(
            width: tvIsWindowsDesktop ? 128 : 112,
            child: ColoredBox(
              color: TvColors.surface,
              child: SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: 14),
                    Image.asset(
                      'assets/branding/logo.webp',
                      width: tvIsWindowsDesktop ? 56 : 48,
                      height: tvIsWindowsDesktop ? 56 : 48,
                    ),
                    const SizedBox(height: 7),
                    const Text('سينماتي', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    const Divider(color: Colors.white12, indent: 18, endIndent: 18),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ...List.generate(_items.length, (index) {
                            final item = _items[index];
                            final selected = _index == index;
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: TvFocus(
                                autofocus: false,
                                onPressed: () {
                                  if (_index != index) setState(() => _index = index);
                                },
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: selected ? TvColors.red.withOpacity(.18) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        item.$1,
                                        size: tvIsWindowsDesktop ? 36 : 31,
                                        color: selected ? Colors.white : Colors.white54,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(item.$2, style: TextStyle(fontSize: tvIsWindowsDesktop ? 13 : 12, fontWeight: FontWeight.w800, color: selected ? Colors.white : Colors.white54)),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                          if (tvIsWindowsDesktop)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: TvFocus(
                                autofocus: false,
                                onPressed: closeCinematyApp,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: TvColors.red.withOpacity(.08),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: TvColors.red.withOpacity(.22)),
                                  ),
                                  child: const Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.power_settings_new_rounded,
                                        size: 36,
                                        color: Color(0xFFFF5A67),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'الخروج',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFFFF7A84),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text('TV Lite', style: TextStyle(fontSize: 11, color: Colors.white24)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey(_index),
              child: _screen(),
            ),
          ),
        ],
      ),
    ),
    );
  }
}
