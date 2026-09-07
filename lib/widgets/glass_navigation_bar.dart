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
    final barHeight = isIos ? 56.0 + bottomInset : 56.0;
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
                // IMPORTANT: never wrap UiKitView in a Flutter scale/transform.
                // iOS platform views can disappear or composite incorrectly when
                // transformed by Flutter. The native Swift view handles compacting.
                ? _NativeIosTabBar(
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

class _NativeIosTabBar extends StatefulWidget {
  const _NativeIosTabBar({
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
  State<_NativeIosTabBar> createState() => _NativeIosTabBarState();
}

class _NativeIosTabBarState extends State<_NativeIosTabBar> {
  MethodChannel? _channel;
  bool _created = false;

  @override
  void didUpdateWidget(covariant _NativeIosTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_created) return;
    if (oldWidget.index != widget.index) {
      _channel?.invokeMethod<void>('setIndex', widget.index);
    }
    if (oldWidget.compact != widget.compact) {
      _channel?.invokeMethod<void>('setCompact', widget.compact);
    }
  }

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('cinematy/native_tab_bar_$id');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'tabChanged') {
        final raw = call.arguments;
        final value = raw is int ? raw : int.tryParse('$raw');
        if (value != null && value >= 0 && value <= 3) {
          widget.onChanged(value);
        }
      }
    });
    _channel = channel;
    _created = true;
    // Send state after UIKit has created the actual native view.
    channel.invokeMethod<void>('setIndex', widget.index);
    channel.invokeMethod<void>('setCompact', widget.compact);
  }

  @override
  void dispose() {
    _created = false;
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: UiKitView(
        viewType: 'cinematy/native_tab_bar',
        creationParams: <String, dynamic>{
          'index': widget.index,
          'compact': widget.compact,
        },
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
        layoutDirection: TextDirection.ltr,
      ),
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
      duration: const Duration(milliseconds: 360),
    )..addListener(() {
        if (!mounted) return;
        final t = Curves.easeOutCubic.transform(_indicatorController.value);
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

  void _animateIndicatorTo(double target, {bool quick = false}) {
    _indicatorController.stop();
    _animationFrom = _visualIndex;
    _animationTo = target.clamp(0.0, 3.0).toDouble();
    _indicatorController.duration = Duration(milliseconds: quick ? 250 : 360);
    _indicatorController.forward(from: 0);
  }

  double _logicalIndexForX(double x, double width) {
    final usable = width - (_innerPadding * 2);
    if (usable <= 0) return widget.index.toDouble();
    final itemWidth = usable / GlassNavigationBar._items.length;
    final local = (x - _innerPadding).clamp(0.0, usable).toDouble();
    // RTL: item 0 is on the far right, item 3 on the far left.
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
    setState(() => _visualIndex = next);
  }

  void _onDragEnd(DragEndDetails details) {
    final target = _visualIndex.round().clamp(0, 3).toInt();
    _dragging = false;
    _animateIndicatorTo(target.toDouble(), quick: true);
    if (target != widget.index) widget.onChanged(target);
  }

  void _select(int i) {
    HapticFeedback.selectionClick();
    _dragging = false;
    _animateIndicatorTo(i.toDouble());
    if (i != widget.index) widget.onChanged(i);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (d) => _onDragStart(d, constraints.maxWidth),
              onHorizontalDragUpdate: (d) => _onDragUpdate(d, constraints.maxWidth),
              onHorizontalDragEnd: _onDragEnd,
              child: Container(
                height: _barHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(23),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(.18),
                      blurRadius: 18,
                      offset: const Offset(0, 7),
                      spreadRadius: -5,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(23),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        // Uniform translucent tint: no fake black/white split.
                        color: Colors.white.withOpacity(.065),
                        borderRadius: BorderRadius.circular(23),
                        border: Border.all(
                          color: Colors.white.withOpacity(.16),
                          width: .85,
                        ),
                      ),
                      child: Stack(
                        children: [
                          // A restrained glass reflection along the rim only.
                          Positioned(
                            left: 18,
                            right: 18,
                            top: .8,
                            child: IgnorePointer(
                              child: Container(
                                height: .8,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(99),
                                  color: Colors.white.withOpacity(.20),
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: Padding(
                              padding: const EdgeInsets.all(_innerPadding),
                              child: LayoutBuilder(
                                builder: (context, inner) {
                                  final count = GlassNavigationBar._items.length;
                                  final itemWidth = inner.maxWidth / count;
                                  final indicatorWidth = itemWidth - 5;
                                  final left = (count - 1 - _visualIndex) * itemWidth +
                                      (itemWidth - indicatorWidth) / 2;

                                  return Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Positioned(
                                        left: left,
                                        top: 0,
                                        bottom: 0,
                                        width: indicatorWidth,
                                        child: const _LiquidSelectionPill(),
                                      ),
                                      Directionality(
                                        textDirection: TextDirection.rtl,
                                        child: Row(
                                          children: List.generate(count, (i) {
                                            final item = GlassNavigationBar._items[i];
                                            final proximity =
                                                (1.0 - (_visualIndex - i).abs())
                                                    .clamp(0.0, 1.0)
                                                    .toDouble();
                                            return Expanded(
                                              child: _GlassDockButton(
                                                icon: item.icon,
                                                label: item.label,
                                                proximity: proximity,
                                                onTap: () => _select(i),
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
                        ],
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

class _LiquidSelectionPill extends StatelessWidget {
  const _LiquidSelectionPill();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: AppColors.redBright.withOpacity(.115),
            border: Border.all(
              color: AppColors.redBright.withOpacity(.32),
              width: .8,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.redBright.withOpacity(.10),
                blurRadius: 15,
                spreadRadius: -5,
              ),
              BoxShadow(
                color: Colors.white.withOpacity(.07),
                blurRadius: 2,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                left: 12,
                right: 12,
                top: .7,
                child: Container(
                  height: .9,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: Colors.white.withOpacity(.17),
                  ),
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 1.2,
                child: Container(
                  height: 1.2,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: AppColors.redBright.withOpacity(.50),
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

class _GlassDockButton extends StatefulWidget {
  const _GlassDockButton({
    required this.icon,
    required this.label,
    required this.proximity,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final double proximity;
  final VoidCallback onTap;

  @override
  State<_GlassDockButton> createState() => _GlassDockButtonState();
}

class _GlassDockButtonState extends State<_GlassDockButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.proximity.clamp(0.0, 1.0).toDouble();
    final iconColor = Color.lerp(
      Colors.white.withOpacity(.55),
      AppColors.redBright,
      p,
    )!;
    final labelColor = Color.lerp(
      Colors.white.withOpacity(.43),
      AppColors.redBright,
      p,
    )!;

    return Semantics(
      button: true,
      selected: p > .85,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? .94 : (1 + (.025 * p)),
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 20.5 + (1.8 * p),
                color: iconColor,
              ),
              const SizedBox(height: 2.5),
              Opacity(
                opacity: .68 + (.32 * p),
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 9.5 + (.5 * p),
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
