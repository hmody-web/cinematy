import 'package:flutter/material.dart';

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 42, this.showName = true});
  final double size;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(size * .28),
          child: Image.asset('assets/branding/logo.webp', width: size, height: size, fit: BoxFit.cover),
        ),
        if (showName) ...[
          const SizedBox(width: 10),
          Text('سينماتي', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        ],
      ],
    );
  }
}
