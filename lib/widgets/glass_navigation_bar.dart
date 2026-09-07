import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';

/// البار السفلي:
/// - Android: Dock Flutter مصمم خصيصاً للتطبيق مع Safe Area أعلى من النسخة القديمة.
/// - iOS: UITabBar حقيقي من UIKit عبر PlatformView، لذلك يتبنى شكل النظام الأصلي
///   (ومن ضمنه Liquid Glass على إصدارات iOS التي توفره) بدل محاكاته داخل Flutter.
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

    // Android يرتفع قليلاً عن الحافة مع Safe Area واضحة.
    // iOS يترك المساحة للنظام والـUITabBar الحقيقي نفسه.
    final bottomGap = isIos
        ? 0.0
        : (bottomInset > 0 ? bottomInset + 8.0 : 12.0);
    final barHeight = isIos ? 56.0 + bottomInset : 72.0;
    final totalHeight = barHeight + bottomGap;

    return SizedBox(
      height: totalHeight,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // التدرج يبدأ من آخر نقطة بالشاشة بلون النظام ويصبح شفافاً
          // عند الخط العلوي للبار، حتى يندمج البار مع المحتوى بدون قطع حاد.
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
                      AppColors.background.withOpacity(.62),
                      Colors.transparent,
                    ],
                    stops: const [0.0, .30, .68, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: bottomGap),
            child: AnimatedScale(
              scale: compact ? .90 : 1.0,
              alignment: Alignment.bottomCenter,
              duration: const Duration(milliseconds: 300),
              curve: compact ? Curves.easeOutCubic : Curves.easeOutBack,
              child: isIos
                  ? _NativeIosTabBar(
                      index: index,
                      onChanged: onChanged,
                      height: barHeight,
                    )
                  : _AndroidFilmDock(
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
  });

  final int index;
  final ValueChanged<int> onChanged;
  final double height;

  @override
  State<_NativeIosTabBar> createState() => _NativeIosTabBarState();
}

class _NativeIosTabBarState extends State<_NativeIosTabBar> {
  MethodChannel? _channel;

  @override
  void didUpdateWidget(covariant _NativeIosTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _channel?.invokeMethod<void>('setIndex', widget.index);
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
    channel.invokeMethod<void>('setIndex', widget.index);
  }

  @override
  void dispose() {
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
        creationParams: <String, dynamic>{'index': widget.index},
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      ),
    );
  }
}

class _AndroidFilmDock extends StatelessWidget {
  const _AndroidFilmDock({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(31),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: CustomPaint(
            painter: const _FilmDockPainter(),
            child: Container(
              height: 72,
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xE8110A0A),
                borderRadius: BorderRadius.circular(31),
                border: Border.all(color: Colors.white.withOpacity(.095)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(.42),
                    blurRadius: 34,
                    offset: const Offset(0, 15),
                  ),
                  BoxShadow(
                    color: AppColors.redBright.withOpacity(.055),
                    blurRadius: 26,
                  ),
                ],
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Row(
                  children: List.generate(GlassNavigationBar._items.length, (i) {
                    final selected = i == index;
                    final item = GlassNavigationBar._items[i];
                    return Expanded(
                      child: _DockItem(
                        icon: item.icon,
                        label: item.label,
                        selected: selected,
                        onTap: () => onChanged(i),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
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
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: selected
                    ? AppColors.redBright.withOpacity(.085)
                    : Colors.transparent,
                border: Border.all(
                  color: selected
                      ? AppColors.redBright.withOpacity(.18)
                      : Colors.transparent,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (selected)
                    Positioned(
                      top: 4,
                      child: Container(
                        width: 28,
                        height: 2,
                        decoration: BoxDecoration(
                          color: AppColors.redBright,
                          borderRadius: BorderRadius.circular(99),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.redBright.withOpacity(.5),
                              blurRadius: 9,
                            ),
                          ],
                        ),
                      ),
                    ),
                  AnimatedPadding(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.only(top: selected ? 7 : 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: selected ? 22 : 20,
                          color: selected
                              ? AppColors.redBright
                              : Colors.white.withOpacity(.48),
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          child: selected
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    label,
                                    maxLines: 1,
                                    style: const TextStyle(
                                      color: AppColors.redBright,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w900,
                                      height: 1,
                                    ),
                                  ),
                                )
                              : const SizedBox(height: 0),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _FilmDockPainter extends CustomPainter {
  const _FilmDockPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(.025);
    const w = 8.0;
    const h = 3.0;
    for (double x = 18; x < size.width - 18; x += 22) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 5, w, h),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - 8, w, h),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
