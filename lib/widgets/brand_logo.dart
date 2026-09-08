import 'package:flutter/material.dart';

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 42, this.showName = true});

  final double size;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final logo = ClipRRect(
      borderRadius: BorderRadius.circular(size * .28),
      child: Image.asset(
        'assets/branding/logo.webp',
        width: size,
        height: size,
        fit: BoxFit.cover,
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
