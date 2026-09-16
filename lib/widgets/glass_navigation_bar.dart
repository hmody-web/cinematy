import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';

/// Bottom navigation:
/// - Android: the real native LiquidGlassTabBar from QWEA0/Liquid-Glass-Android.
///   Flutter only reserves space and synchronizes state through a MethodChannel.
/// - iOS: the existing native UITabBar bridge remains untouched.
class GlassNavigationBar extends StatelessWidget {
  const GlassNavigationBar({
    super.key,
    required this.index,
    required this.onChanged,
    this.compact = false,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _WebPreviewNavigationBar(
        index: index,
        onChanged: onChanged,
      );
    }

    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final isIos = Platform.isIOS;
    final isAndroid = Platform.isAndroid;

    final bottomGap = isIos
        ? 0.0
        : (bottomInset > 0 ? bottomInset + 14.0 : 16.0);
    // LiquidGlassTabBar's icon + label layout naturally fits in ~62dp.
    final barHeight = isIos ? 49.0 + bottomInset : 62.0;
    final totalHeight = barHeight + bottomGap;

    return SizedBox(
      height: totalHeight,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // Keep the cinematic fade behind the native glass. This is NOT the
          // glass itself; it only fades the page into the system background at
          // the very bottom edge, exactly as requested for both platforms.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      AppColors.background,
                      AppColors.background.withOpacity(.94),
                      AppColors.background.withOpacity(.52),
                      Colors.transparent,
                    ],
                    stops: const [0.0, .31, .68, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: bottomGap),
            child: isIos
                ? _NativeIosTabBarBridge(
                    index: index,
                    onChanged: onChanged,
                    height: barHeight,
                    compact: compact,
                  )
                : isAndroid
                    ? _NativeAndroidLiquidGlassBridge(
                        index: index,
                        onChanged: onChanged,
                        height: barHeight,
                        compact: compact,
                        fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily ?? 'Monadi',
                      )
                    : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}


class _WebPreviewNavigationBar extends StatelessWidget {
  const _WebPreviewNavigationBar({
    required this.index,
    required this.onChanged,
  });

  final int index;
  final ValueChanged<int> onChanged;

  static const _items = <(IconData, String)>[
    (Icons.home_rounded, 'الرئيسية'),
    (Icons.explore_rounded, 'اكتشف'),
    (Icons.search_rounded, 'البحث'),
    (Icons.live_tv_rounded, 'التلفاز'),
    (Icons.video_library_rounded, 'مكتبتي'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 12, 12),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xF2111111),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withOpacity(.08)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x70000000),
                blurRadius: 34,
                offset: Offset(-10, 0),
              ),
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 18),
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppColors.redBright.withOpacity(.14),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.redBright.withOpacity(.48),
                  ),
                ),
                child: const Icon(
                  Icons.movie_filter_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'سينماتي',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 18),
              Divider(
                height: 1,
                indent: 18,
                endIndent: 18,
                color: Colors.white.withOpacity(.07),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(_items.length, (i) {
                      final item = _items[i];
                      return _WebPreviewNavItem(
                        icon: item.$1,
                        label: item.$2,
                        selected: index == i,
                        onTap: () => onChanged(i),
                      );
                    }),
                  ),
                ),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.035),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.keyboard_alt_outlined,
                      color: Colors.white38,
                      size: 15,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'وضع التلفاز',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WebPreviewNavItem extends StatefulWidget {
  const _WebPreviewNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_WebPreviewNavItem> createState() => _WebPreviewNavItemState();
}

class _WebPreviewNavItemState extends State<_WebPreviewNavItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _focused;

    return AnimatedScale(
      scale: _focused ? 1.08 : 1.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            focusColor: Colors.transparent,
            hoverColor: Colors.white.withOpacity(.035),
            onFocusChange: (value) {
              if (_focused == value) return;
              setState(() => _focused = value);
            },
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
              decoration: BoxDecoration(
                gradient: active
                    ? LinearGradient(
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                        colors: [
                          AppColors.redBright.withOpacity(
                            widget.selected ? .30 : .18,
                          ),
                          AppColors.redBright.withOpacity(.045),
                        ],
                      )
                    : null,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _focused
                      ? Colors.white.withOpacity(.95)
                      : widget.selected
                          ? AppColors.redBright.withOpacity(.62)
                          : Colors.transparent,
                  width: _focused ? 2.2 : 1.0,
                ),
                boxShadow: _focused
                    ? [
                        BoxShadow(
                          color: AppColors.redBright.withOpacity(.20),
                          blurRadius: 20,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.icon,
                    size: _focused ? 28 : 25,
                    color: active ? Colors.white : Colors.white54,
                  ),
                  const SizedBox(height: 7),
                  Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: active ? Colors.white : Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// iOS uses a UIKit UITabBar mounted by the native iOS host.
/// No iOS native file is changed by the Android Liquid Glass integration.
class NativeIosTabBarController {
  NativeIosTabBarController._();

  static const MethodChannel _channel = MethodChannel('cinematy/native_tab_bar');

  static ValueChanged<int>? _onChanged;
  static bool _handlerInstalled = false;
  static bool _hostAttached = false;
  static bool _routeVisible = true;
  static int _index = 0;
  static bool _compact = false;
  static int _syncSerial = 0;

  static void attach({
    required int index,
    required bool compact,
    required ValueChanged<int> onChanged,
  }) {
    if (kIsWeb || !Platform.isIOS) return;
    _hostAttached = true;
    _index = index.clamp(0, 4).toInt();
    _compact = compact;
    _onChanged = onChanged;
    _installHandler();
    _sync(retryUntilNativeReady: true);
  }

  static void update({
    required int index,
    required bool compact,
    required ValueChanged<int> onChanged,
  }) {
    if (kIsWeb || !Platform.isIOS) return;
    _index = index.clamp(0, 4).toInt();
    _compact = compact;
    _onChanged = onChanged;
    _installHandler();
    _sync();
  }

  static void detach(ValueChanged<int> onChanged) {
    if (kIsWeb || !Platform.isIOS) return;
    if (identical(_onChanged, onChanged)) _onChanged = null;
    _hostAttached = false;
    _sync();
  }

  static void setRouteVisible(bool visible) {
    if (kIsWeb || !Platform.isIOS) return;
    if (_routeVisible == visible) return;
    _routeVisible = visible;
    _sync(retryUntilNativeReady: visible && _hostAttached);
  }

  static void _installHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'tabChanged') return;
      final raw = call.arguments;
      final value = raw is int ? raw : int.tryParse('$raw');
      if (value == null || value < 0 || value > 4) return;
      _onChanged?.call(value);
    });
  }

  static Future<void> _sync({bool retryUntilNativeReady = false}) async {
    if (kIsWeb || !Platform.isIOS) return;
    final serial = ++_syncSerial;
    final attempts = retryUntilNativeReady ? 24 : 1;

    for (var attempt = 0; attempt < attempts; attempt++) {
      if (serial != _syncSerial) return;
      try {
        final ready = await _channel.invokeMethod<bool>('ping') ?? false;
        if (ready) {
          if (serial != _syncSerial) return;
          await _channel.invokeMethod<void>('setIndex', _index);
          await _channel.invokeMethod<void>('setCompact', _compact);
          await _channel.invokeMethod<void>(
            'setVisible',
            _hostAttached && _routeVisible,
          );
          return;
        }
      } on MissingPluginException {
        // Native host may still be installing the bar.
      } on PlatformException {
        // Retry when requested.
      }

      if (!retryUntilNativeReady || attempt == attempts - 1) return;
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }
}

/// Android counterpart backed by QWEA0/Liquid-Glass-Android's
/// LiquidGlassTabBar. The native view exists above Flutter in MainActivity;
/// this controller only synchronizes tab selection, compact state and route
/// visibility. The liquid droplet's drag physics remain 100% native.
class NativeAndroidLiquidGlassController {
  NativeAndroidLiquidGlassController._();

  static const MethodChannel _channel =
      MethodChannel('cinematy/native_android_liquid_tab_bar');

  static ValueChanged<int>? _onChanged;
  static bool _handlerInstalled = false;
  static bool _hostAttached = false;
  static bool _routeVisible = true;
  static int _index = 0;
  static bool _compact = false;
  static String _fontFamily = 'Monadi';
  static int _syncSerial = 0;

  static void attach({
    required int index,
    required bool compact,
    required String fontFamily,
    required ValueChanged<int> onChanged,
  }) {
    if (kIsWeb || !Platform.isAndroid) return;
    _hostAttached = true;
    _index = index.clamp(0, 4).toInt();
    _compact = compact;
    _fontFamily = fontFamily;
    _onChanged = onChanged;
    _installHandler();
    _sync(retryUntilNativeReady: true);
  }

  static void update({
    required int index,
    required bool compact,
    required String fontFamily,
    required ValueChanged<int> onChanged,
  }) {
    if (kIsWeb || !Platform.isAndroid) return;
    _index = index.clamp(0, 4).toInt();
    _compact = compact;
    _fontFamily = fontFamily;
    _onChanged = onChanged;
    _installHandler();
    _sync();
  }

  static void detach(ValueChanged<int> onChanged) {
    if (kIsWeb || !Platform.isAndroid) return;
    if (identical(_onChanged, onChanged)) _onChanged = null;
    _hostAttached = false;
    _sync();
  }

  static void setRouteVisible(bool visible) {
    if (kIsWeb || !Platform.isAndroid) return;
    if (_routeVisible == visible) return;
    _routeVisible = visible;
    _sync(retryUntilNativeReady: visible && _hostAttached);
  }

  static void _installHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'tabChanged') return;
      final raw = call.arguments;
      final value = raw is int ? raw : int.tryParse('$raw');
      if (value == null || value < 0 || value > 4) return;
      _onChanged?.call(value);
    });
  }

  static Future<void> _sync({bool retryUntilNativeReady = false}) async {
    if (kIsWeb || !Platform.isAndroid) return;
    final serial = ++_syncSerial;
    final attempts = retryUntilNativeReady ? 30 : 1;

    for (var attempt = 0; attempt < attempts; attempt++) {
      if (serial != _syncSerial) return;
      try {
        final ready = await _channel.invokeMethod<bool>('ping') ?? false;
        if (ready) {
          if (serial != _syncSerial) return;
          await _channel.invokeMethod<void>('setIndex', _index);
          await _channel.invokeMethod<void>('setCompact', _compact);
          await _channel.invokeMethod<void>('setFontFamily', _fontFamily);
          await _channel.invokeMethod<void>(
            'setVisible',
            _hostAttached && _routeVisible,
          );
          return;
        }
      } on MissingPluginException {
        // MainActivity may still be attaching the native LiquidGlassTabBar.
      } on PlatformException {
        // Retry when requested.
      }

      if (!retryUntilNativeReady || attempt == attempts - 1) return;
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
  }
}

/// Existing observer name is kept so app.dart does not need to change. It now
/// hides/restores both native system bars when a Flutter route covers the shell.
class NativeIosTabBarRouteObserver extends NavigatorObserver {
  void _syncFor(Route<dynamic>? route) {
    final visible = route?.isFirst ?? false;
    NativeIosTabBarController.setRouteVisible(visible);
    NativeAndroidLiquidGlassController.setRouteVisible(visible);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _syncFor(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _syncFor(previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _syncFor(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _syncFor(newRoute);
  }
}

final nativeIosTabBarRouteObserver = NativeIosTabBarRouteObserver();

class _NativeIosTabBarBridge extends StatefulWidget {
  const _NativeIosTabBarBridge({
    required this.index,
    required this.onChanged,
    required this.height,
    required this.compact,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final double height;
  final bool compact;

  @override
  State<_NativeIosTabBarBridge> createState() => _NativeIosTabBarBridgeState();
}

class _NativeIosTabBarBridgeState extends State<_NativeIosTabBarBridge> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      NativeIosTabBarController.attach(
        index: widget.index,
        compact: widget.compact,
        onChanged: widget.onChanged,
      );
    });
  }

  @override
  void didUpdateWidget(covariant _NativeIosTabBarBridge oldWidget) {
    super.didUpdateWidget(oldWidget);
    NativeIosTabBarController.update(
      index: widget.index,
      compact: widget.compact,
      onChanged: widget.onChanged,
    );
  }

  @override
  void dispose() {
    NativeIosTabBarController.detach(widget.onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(height: widget.height, width: double.infinity),
    );
  }
}

class _NativeAndroidLiquidGlassBridge extends StatefulWidget {
  const _NativeAndroidLiquidGlassBridge({
    required this.index,
    required this.onChanged,
    required this.height,
    required this.compact,
    required this.fontFamily,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final double height;
  final bool compact;
  final String fontFamily;

  @override
  State<_NativeAndroidLiquidGlassBridge> createState() =>
      _NativeAndroidLiquidGlassBridgeState();
}

class _NativeAndroidLiquidGlassBridgeState
    extends State<_NativeAndroidLiquidGlassBridge> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      NativeAndroidLiquidGlassController.attach(
        index: widget.index,
        compact: widget.compact,
        fontFamily: widget.fontFamily,
        onChanged: widget.onChanged,
      );
    });
  }

  @override
  void didUpdateWidget(covariant _NativeAndroidLiquidGlassBridge oldWidget) {
    super.didUpdateWidget(oldWidget);
    NativeAndroidLiquidGlassController.update(
      index: widget.index,
      compact: widget.compact,
      fontFamily: widget.fontFamily,
      onChanged: widget.onChanged,
    );
  }

  @override
  void dispose() {
    NativeAndroidLiquidGlassController.detach(widget.onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // MainActivity draws the real native tab bar over Flutter. This box only
    // reserves the exact vertical footprint inside Scaffold.
    return IgnorePointer(
      child: SizedBox(height: widget.height, width: double.infinity),
    );
  }
}
