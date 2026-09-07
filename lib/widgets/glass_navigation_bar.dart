import 'dart:io';

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
    if (!Platform.isIOS) return;
    _hostAttached = true;
    _index = index.clamp(0, 3).toInt();
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
    if (!Platform.isIOS) return;
    _index = index.clamp(0, 3).toInt();
    _compact = compact;
    _onChanged = onChanged;
    _installHandler();
    _sync();
  }

  static void detach(ValueChanged<int> onChanged) {
    if (!Platform.isIOS) return;
    if (identical(_onChanged, onChanged)) _onChanged = null;
    _hostAttached = false;
    _sync();
  }

  static void setRouteVisible(bool visible) {
    if (!Platform.isIOS) return;
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
      if (value == null || value < 0 || value > 3) return;
      _onChanged?.call(value);
    });
  }

  static Future<void> _sync({bool retryUntilNativeReady = false}) async {
    if (!Platform.isIOS) return;
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
    if (!Platform.isAndroid) return;
    _hostAttached = true;
    _index = index.clamp(0, 3).toInt();
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
    if (!Platform.isAndroid) return;
    _index = index.clamp(0, 3).toInt();
    _compact = compact;
    _fontFamily = fontFamily;
    _onChanged = onChanged;
    _installHandler();
    _sync();
  }

  static void detach(ValueChanged<int> onChanged) {
    if (!Platform.isAndroid) return;
    if (identical(_onChanged, onChanged)) _onChanged = null;
    _hostAttached = false;
    _sync();
  }

  static void setRouteVisible(bool visible) {
    if (!Platform.isAndroid) return;
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
      if (value == null || value < 0 || value > 3) return;
      _onChanged?.call(value);
    });
  }

  static Future<void> _sync({bool retryUntilNativeReady = false}) async {
    if (!Platform.isAndroid) return;
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
