import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class GlassNavigationBar extends StatelessWidget {
  const GlassNavigationBar({
    super.key,
    required this.index,
    required this.onChanged,
  });

  final int index;
  final ValueChanged<int> onChanged;

  static const _items = <({IconData icon, String label})>[
    (icon: Icons.home_rounded, label: 'الرئيسية'),
    (icon: Icons.explore_rounded, label: 'اكتشف'),
    (icon: Icons.search_rounded, label: 'البحث'),
    (icon: Icons.video_library_rounded, label: 'مكتبتي'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Padding(
      // إنزال البار بصرياً قليلاً مع احترام الـ safe area في أجهزة الآيفون.
      padding: EdgeInsets.fromLTRB(14, 0, 14, bottomInset > 0 ? 3 : 8),
      child: Transform.translate(
        offset: const Offset(0, 5),
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
                    children: List.generate(_items.length, (i) {
                      final selected = i == index;
                      final item = _items[i];
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
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeOutBack,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: selected ? Colors.white.withOpacity(.075) : Colors.transparent,
                border: Border.all(
                  color: selected ? Colors.white.withOpacity(.095) : Colors.transparent,
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
                              color: AppColors.redBright.withOpacity(.55),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                      ),
                    ),
                  AnimatedPadding(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.only(top: selected ? 7 : 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          width: selected ? 34 : 32,
                          height: selected ? 34 : 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: selected
                                ? LinearGradient(
                                    begin: Alignment.topRight,
                                    end: Alignment.bottomLeft,
                                    colors: [
                                      Colors.white.withOpacity(.14),
                                      AppColors.redBright.withOpacity(.11),
                                    ],
                                  )
                                : null,
                            border: Border.all(
                              color: selected
                                  ? Colors.white.withOpacity(.10)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Icon(
                            icon,
                            size: selected ? 21 : 20,
                            color: selected
                                ? Colors.white
                                : Colors.white.withOpacity(.46),
                          ),
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          child: selected
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    label,
                                    maxLines: 1,
                                    style: const TextStyle(
                                      fontSize: 9.3,
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

/// ثقوب فيلم خافتة جداً داخل الدوك تعطي هوية سينمائية بدون ازدحام بصري.
class _FilmDockPainter extends CustomPainter {
  const _FilmDockPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(.025);
    const w = 8.0;
    const h = 3.0;
    for (double x = 18; x < size.width - 18; x += 22) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, 5, w, h), const Radius.circular(2)),
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
