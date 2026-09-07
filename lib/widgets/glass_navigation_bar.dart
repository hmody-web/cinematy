import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';

/// Bottom navigation:
/// - Android: compact cinematic glass dock with a full-height selected capsule.
/// - iOS: native UITabBar through UIKit/Swift so the system owns its appearance.
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

  static const _items = <({IconData icon, String label})>[
    (icon: Icons.home_rounded, label: 'الرئيسية'),
    (icon: Icons.explore_rounded, label: 'اكتشف'),
    (icon: Icons.search_rounded, label: 'البحث'),
    (icon: Icons.video_library_rounded, label: 'مكتبتي'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final isIos = Platform.isIOS;

    // Android: lower total height than before while still keeping a comfortable
    // safe distance from gesture/navigation areas.
    final bottomGap = isIos
        ? 0.0
        : (bottomInset > 0 ? bottomInset + 6.0 : 10.0);
    final barHeight = isIos ? 49.0 + bottomInset : 56.0;
    final totalHeight = barHeight + bottomGap;

    return SizedBox(
      height: totalHeight,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      AppColors.background,
                      AppColors.background.withOpacity(.95),
                      AppColors.background.withOpacity(.58),
                      Colors.transparent,
                    ],
                    stops: const [0.0, .34, .72, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: bottomGap),
            child: isIos
                // iOS only reserves layout here; the real UITabBar is mounted
                // by AppDelegate above Flutter and cannot disappear in compositing.
                ? _NativeIosTabBarBridge(
                    index: index,
                    onChanged: onChanged,
                    height: barHeight,
                    compact: compact,
                  )
                : AnimatedScale(
                    scale: compact ? .90 : 1.0,
                    alignment: Alignment.bottomCenter,
                    duration: const Duration(milliseconds: 280),
                    curve: compact ? Curves.easeOutCubic : Curves.easeOutBack,
                    child: _AndroidGlassDock(
                      index: index,
                      onChanged: onChanged,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// iOS uses a UIKit UITabBar that is mounted directly above Flutter's root
/// view by AppDelegate. Flutter only keeps its reserved bottom space here and
/// synchronizes selection / compact state through one MethodChannel.
///
/// This deliberately avoids UiKitView. A platform view inside Scaffold's
/// bottomNavigationBar can be composited out on some iOS/Flutter combinations;
/// mounting the real UITabBar in the native view hierarchy removes that failure
/// mode and keeps the system-owned appearance (including Liquid Glass where the
/// installed iOS version provides it).
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
    if (identical(_onChanged, onChanged)) {
      _onChanged = null;
    }
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
      final callback = _onChanged;
      if (callback != null) callback(value);
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
        // AppDelegate may still be finishing the native view installation.
      } on PlatformException {
        // Retry below when requested; otherwise leave Flutter fully usable.
      }

      if (!retryUntilNativeReady || attempt == attempts - 1) return;
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }
}

/// Keeps the native UIKit bar hidden while a Flutter route (details, player,
/// modal sheet, etc.) is above the root CinematyShell, then restores it on pop.
class NativeIosTabBarRouteObserver extends NavigatorObserver {
  void _syncFor(Route<dynamic>? route) {
    NativeIosTabBarController.setRouteVisible(route?.isFirst ?? false);
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
    // The actual UITabBar lives in UIKit. This box only reserves exactly the
    // same vertical area inside Flutter so content and the native bar align.
    return IgnorePointer(
      child: SizedBox(height: widget.height, width: double.infinity),
    );
  }
}

class _AndroidGlassDock extends StatefulWidget {
  const _AndroidGlassDock({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  State<_AndroidGlassDock> createState() => _AndroidGlassDockState();
}

class _AndroidGlassDockState extends State<_AndroidGlassDock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _indicatorController;

  double _visualIndex = 0;
  double _animationFrom = 0;
  double _animationTo = 0;
  bool _dragging = false;
  bool _touching = false;
  int _lastHapticIndex = -1;

  static const double _barHeight = 56;
  static const double _innerPadding = 5;

  @override
  void initState() {
    super.initState();
    _visualIndex = widget.index.toDouble();
    _animationFrom = _visualIndex;
    _animationTo = _visualIndex;
    _indicatorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..addListener(() {
        if (!mounted) return;
        final t = Curves.easeInOutCubic.transform(_indicatorController.value);
        setState(() {
          _visualIndex = lerpDouble(_animationFrom, _animationTo, t) ??
              _animationTo;
        });
      });
  }

  @override
  void didUpdateWidget(covariant _AndroidGlassDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && oldWidget.index != widget.index) {
      _animateIndicatorTo(widget.index.toDouble());
    }
  }

  @override
  void dispose() {
    _indicatorController.dispose();
    super.dispose();
  }

  void _setTouching(bool value) {
    if (_touching == value || !mounted) return;
    setState(() => _touching = value);
  }

  void _animateIndicatorTo(double target, {bool quick = false}) {
    _indicatorController.stop();
    _animationFrom = _visualIndex;
    _animationTo = target.clamp(0.0, 3.0).toDouble();
    _indicatorController.duration =
        Duration(milliseconds: quick ? 270 : 420);
    _indicatorController.forward(from: 0);
  }

  double _logicalIndexForX(double x, double width) {
    final usable = width - (_innerPadding * 2);
    if (usable <= 0) return widget.index.toDouble();
    final itemWidth = usable / GlassNavigationBar._items.length;
    final local = (x - _innerPadding).clamp(0.0, usable).toDouble();

    // RTL: الرئيسية في أقصى اليمين، مكتبتي في أقصى اليسار.
    final logical = ((usable - local) / itemWidth) - .5;
    return logical.clamp(0.0, 3.0).toDouble();
  }

  void _onDragStart(DragStartDetails details, double width) {
    _indicatorController.stop();
    _dragging = true;
    _lastHapticIndex = _visualIndex.round();
    final next = _logicalIndexForX(details.localPosition.dx, width);
    setState(() => _visualIndex = next);
  }

  void _onDragUpdate(DragUpdateDetails details, double width) {
    final next = _logicalIndexForX(details.localPosition.dx, width);
    final nearest = next.round().clamp(0, 3).toInt();
    if (nearest != _lastHapticIndex) {
      _lastHapticIndex = nearest;
      HapticFeedback.selectionClick();
    }
    // لا يوجد AnimatedWidget هنا عمداً؛ المؤشر يتبع الإصبع frame-by-frame
    // بلا تأخير أو مطاردة متأخرة خلف حركة المستخدم.
    setState(() => _visualIndex = next);
  }

  void _onDragEnd() {
    final target = _visualIndex.round().clamp(0, 3).toInt();
    _dragging = false;
    _animateIndicatorTo(target.toDouble(), quick: true);
    if (target != widget.index) widget.onChanged(target);
  }

  void _onDragCancel() {
    _dragging = false;
    _animateIndicatorTo(widget.index.toDouble(), quick: true);
  }

  void _selectFromX(double x, double width) {
    final target = _logicalIndexForX(x, width).round().clamp(0, 3).toInt();
    HapticFeedback.selectionClick();
    _dragging = false;
    _animateIndicatorTo(target.toDouble());
    if (target != widget.index) widget.onChanged(target);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => _setTouching(true),
              onPointerUp: (_) => _setTouching(false),
              onPointerCancel: (_) => _setTouching(false),
              child: AnimatedScale(
                // 0.5% بالضبط: استجابة محسوسة من دون أن يقفز البار بصرياً.
                scale: _touching ? 1.005 : 1.0,
                alignment: Alignment.bottomCenter,
                duration: Duration(milliseconds: _touching ? 85 : 230),
                curve: _touching ? Curves.easeOutCubic : Curves.easeOutBack,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) =>
                      _selectFromX(d.localPosition.dx, constraints.maxWidth),
                  onHorizontalDragStart: (d) =>
                      _onDragStart(d, constraints.maxWidth),
                  onHorizontalDragUpdate: (d) =>
                      _onDragUpdate(d, constraints.maxWidth),
                  onHorizontalDragEnd: (_) => _onDragEnd(),
                  onHorizontalDragCancel: _onDragCancel,
                  child: Container(
                    height: _barHeight,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(23),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(.20),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                          spreadRadius: -7,
                        ),
                        BoxShadow(
                          color: AppColors.redBright.withOpacity(.025),
                          blurRadius: 22,
                          spreadRadius: -10,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(23),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            // طبقة موحدة بالكامل. لا يوجد شريط أبيض بالأعلى
                            // ولا تدرج وهمي داخل سطح الزجاج نفسه.
                            color: Colors.black.withOpacity(.16),
                            borderRadius: BorderRadius.circular(23),
                            border: Border.all(
                              color: Colors.white.withOpacity(.10),
                              width: .75,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(_innerPadding),
                            child: LayoutBuilder(
                              builder: (context, inner) {
                                final count = GlassNavigationBar._items.length;
                                final itemWidth = inner.maxWidth / count;

                                // عندما تكون البقعة فوق مركز قسم تكون كبيرة وتحوي
                                // الأيقونة والاسم. أثناء انتقالها بين قسمين تنكمش
                                // مثل قطرة ماء ثم تتمدد من جديد عند الوصول.
                                final nearest = _visualIndex.roundToDouble();
                                final distance =
                                    (_visualIndex - nearest).abs().clamp(0.0, .5);
                                final travel = Curves.easeInOutCubic.transform(
                                  (distance / .5).clamp(0.0, 1.0).toDouble(),
                                );

                                final fullWidth = itemWidth - 6;
                                final blobWidth = lerpDouble(
                                      fullWidth,
                                      fullWidth * .58,
                                      travel,
                                    ) ??
                                    fullWidth;
                                final blobHeight = lerpDouble(
                                      inner.maxHeight - 1,
                                      (inner.maxHeight - 1) * .70,
                                      travel,
                                    ) ??
                                    inner.maxHeight - 1;

                                final centerX =
                                    (count - 1 - _visualIndex) * itemWidth +
                                        itemWidth / 2;
                                final left = centerX - blobWidth / 2;
                                final top = (inner.maxHeight - blobHeight) / 2;

                                return Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Positioned(
                                      left: left,
                                      top: top,
                                      width: blobWidth,
                                      height: blobHeight,
                                      child: _LiquidSelectionBlob(
                                        travel: travel,
                                        dragging: _dragging,
                                      ),
                                    ),
                                    Directionality(
                                      textDirection: TextDirection.rtl,
                                      child: Row(
                                        children: List.generate(count, (i) {
                                          final item =
                                              GlassNavigationBar._items[i];
                                          final proximity =
                                              (1.0 - (_visualIndex - i).abs())
                                                  .clamp(0.0, 1.0)
                                                  .toDouble();
                                          return Expanded(
                                            child: _GlassDockButton(
                                              icon: item.icon,
                                              label: item.label,
                                              proximity: proximity,
                                              selected:
                                                  !_dragging && widget.index == i,
                                              semanticTap: () {
                                                HapticFeedback.selectionClick();
                                                _animateIndicatorTo(i.toDouble());
                                                if (i != widget.index) {
                                                  widget.onChanged(i);
                                                }
                                              },
                                            ),
                                          );
                                        }),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LiquidSelectionBlob extends StatelessWidget {
  const _LiquidSelectionBlob({
    required this.travel,
    required this.dragging,
  });

  final double travel;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    final t = travel.clamp(0.0, 1.0).toDouble();
    final radius = lerpDouble(18, 999, t) ?? 18;

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: lerpDouble(18, 24, t) ?? 18,
            sigmaY: lerpDouble(18, 24, t) ?? 18,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: RadialGradient(
                center: const Alignment(0, -.08),
                radius: 1.25,
                colors: [
                  AppColors.redBright.withOpacity(
                    dragging ? .22 - (.06 * t) : .20 - (.05 * t),
                  ),
                  AppColors.red.withOpacity(.10 - (.025 * t)),
                  AppColors.red.withOpacity(.055),
                ],
                stops: const [0.0, .58, 1.0],
              ),
              border: Border.all(
                color: AppColors.redBright.withOpacity(.30 - (.07 * t)),
                width: .8,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.redBright.withOpacity(.13 - (.04 * t)),
                  blurRadius: 17,
                  spreadRadius: -5,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassDockButton extends StatelessWidget {
  const _GlassDockButton({
    required this.icon,
    required this.label,
    required this.proximity,
    required this.selected,
    required this.semanticTap,
  });

  final IconData icon;
  final String label;
  final double proximity;
  final bool selected;
  final VoidCallback semanticTap;

  @override
  Widget build(BuildContext context) {
    final p = proximity.clamp(0.0, 1.0).toDouble();
    final iconColor = Color.lerp(
      Colors.white.withOpacity(.55),
      AppColors.redBright,
      p,
    )!;
    final labelColor = Color.lerp(
      Colors.white.withOpacity(.42),
      AppColors.redBright,
      p,
    )!;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: semanticTap,
      child: IgnorePointer(
        child: Transform.scale(
          scale: 1 + (.022 * p),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20.5 + (1.9 * p),
                color: iconColor,
              ),
              const SizedBox(height: 2.5),
              Opacity(
                opacity: .67 + (.33 * p),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 9.4 + (.6 * p),
                    fontWeight: p > .55 ? FontWeight.w800 : FontWeight.w600,
                    height: 1,
                    letterSpacing: -.12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
