import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// الخلفية السينمائية الموحدة لسينماتي:
/// داكنة مع توهج أحمر ناعم من الجانبين.
class CinematyBackdrop extends StatelessWidget {
  const CinematyBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF0B0606),
                Color(0xFF070505),
              ],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                top: -135,
                right: -115,
                child: _GlowOrb(size: 380, opacity: .24),
              ),
              Positioned(
                top: 300,
                left: -150,
                child: _GlowOrb(size: 340, opacity: .14),
              ),
              Positioned(
                bottom: -190,
                right: -150,
                child: _GlowOrb(size: 420, opacity: .085),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.size,
    required this.opacity,
  });

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            stops: const [0, .42, 1],
            colors: [
              AppColors.redBright.withOpacity(opacity),
              AppColors.red.withOpacity(opacity * .36),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}
