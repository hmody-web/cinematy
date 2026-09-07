import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// تحميل بصري هادئ بدلاً من مؤشرات الدوران. يتحرك الوميض أفقياً
/// من اليمين إلى اليسار ثم يعود حتى يصل المحتوى الحقيقي.
class CinematyShimmer extends StatefulWidget {
  const CinematyShimmer({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1350),
  });

  final Widget child;
  final Duration duration;

  @override
  State<CinematyShimmer> createState() => _CinematyShimmerState();
}

class _CinematyShimmerState extends State<CinematyShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment(1.8 - (t * 3.6), 0),
            end: Alignment(.8 - (t * 3.6), 0),
            colors: const [
              Color(0xFF171111),
              Color(0xFF382626),
              Color(0xFF171111),
            ],
            stops: const [.18, .50, .82],
          ).createShader(rect),
          child: child,
        );
      },
    );
  }
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.radius = 18,
  });

  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) => CinematyShimmer(
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withOpacity(.035)),
          ),
        ),
      );
}

class SkeletonPosterCard extends StatelessWidget {
  const SkeletonPosterCard({super.key, this.width = 142});
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: .68,
              child: SkeletonBox(width: width, radius: 18),
            ),
            const SizedBox(height: 9),
            SkeletonBox(width: width * .78, height: 13, radius: 7),
            const SizedBox(height: 7),
            SkeletonBox(width: width * .46, height: 10, radius: 6),
          ],
        ),
      );
}

class SkeletonGrid extends StatelessWidget {
  const SkeletonGrid({super.key, this.count = 9});
  final int count;

  @override
  Widget build(BuildContext context) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 130),
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: count,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 16,
          childAspectRatio: .52,
        ),
        itemBuilder: (_, __) => const SkeletonPosterCard(width: double.infinity),
      );
}
