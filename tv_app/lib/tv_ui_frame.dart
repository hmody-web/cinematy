import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// TV design frame.
///
/// Android/TV keeps the original normalized 1440x810 design surface.
/// Windows uses the real desktop surface so the UI fills the entire screen
/// with no letterboxing / black bars around the app.
class TvUiFrame extends StatelessWidget {
  const TvUiFrame({super.key, required this.child});

  final Widget child;
  static const Size designSize = Size(1440, 810);

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : mq.size.width;
          final height = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : mq.size.height;

          final actualSize = Size(width, height);

          return SizedBox(
            width: width,
            height: height,
            child: MediaQuery(
              data: mq.copyWith(
                size: actualSize,
                padding: EdgeInsets.zero,
                viewPadding: EdgeInsets.zero,
                textScaler: TextScaler.noScaling,
              ),
              child: child,
            ),
          );
        },
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: MediaQuery(
            data: mq.copyWith(
              size: designSize,
              textScaler: TextScaler.noScaling,
            ),
            child: SizedBox.fromSize(size: designSize, child: child),
          ),
        ),
      ),
    );
  }
}
