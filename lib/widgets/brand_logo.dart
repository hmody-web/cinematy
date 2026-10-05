import 'package:flutter/material.dart';

class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.size = 42,
    this.showName = true,
    this.logoBadge,
  });

  final double size;
  final bool showName;
  final Widget? logoBadge;

  @override
  Widget build(BuildContext context) {
    final logoImage = ClipRRect(
      borderRadius: BorderRadius.circular(size * .28),
      child: Image.asset(
        'assets/branding/logo.webp',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );

    final logo = logoBadge == null
        ? logoImage
        : SizedBox(
            width: size,
            height: size,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: logoImage),
                Positioned(
                  left: -size * .10,
                  bottom: -size * .10,
                  child: logoBadge!,
                ),
              ],
            ),
          );

    if (!showName) return logo;

    return LayoutBuilder(
      builder: (context, constraints) {
        // In compact cards the available width may be only ~68 px.
        // Hide the wordmark there instead of overflowing the Row.
        final canShowName =
            !constraints.hasBoundedWidth || constraints.maxWidth >= size + 82;

        if (!canShowName) return logo;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            logo,
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'سينماتي',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
          ],
        );
      },
    );
  }
}
