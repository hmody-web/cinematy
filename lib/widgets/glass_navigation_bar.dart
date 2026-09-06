import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class GlassNavigationBar extends StatelessWidget {
  const GlassNavigationBar({super.key, required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  static const _items = [
    (Icons.home_rounded, 'الرئيسية'),
    (Icons.grid_view_rounded, 'اكتشف'),
    (Icons.search_rounded, 'البحث'),
    (Icons.bookmark_rounded, 'مكتبتي'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF170505).withOpacity(.78),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withOpacity(.10)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(.32), blurRadius: 28, offset: const Offset(0, 14)),
                BoxShadow(color: AppColors.red.withOpacity(.08), blurRadius: 22, spreadRadius: 1),
              ],
            ),
            child: SizedBox(
              height: 68,
              child: Row(
                children: List.generate(_items.length, (i) {
                  final selected = i == index;
                  final (icon, label) = _items[i];
                  return Expanded(
                    flex: selected ? 2 : 1,
                    child: Semantics(
                      selected: selected,
                      label: label,
                      button: true,
                      child: InkWell(
                        onTap: () => onChanged(i),
                        borderRadius: BorderRadius.circular(24),
                        child: Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            padding: EdgeInsets.symmetric(horizontal: selected ? 14 : 10, vertical: 9),
                            decoration: BoxDecoration(
                              color: selected ? Colors.white.withOpacity(.095) : Colors.transparent,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: selected ? Colors.white.withOpacity(.08) : Colors.transparent),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(icon, size: 23, color: selected ? Colors.white : Colors.white.withOpacity(.50)),
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 240),
                                  curve: Curves.easeOut,
                                  child: selected
                                      ? Padding(
                                          padding: const EdgeInsets.only(right: 7),
                                          child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
