import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tv_theme.dart';

class TvFocus extends StatefulWidget {
  const TvFocus({
    super.key,
    required this.child,
    required this.onPressed,
    this.autofocus = false,
    this.borderRadius = 14,
    this.padding = EdgeInsets.zero,
    this.focusNode,
    this.onArrowUp,
    this.onArrowDown,
    this.onArrowLeft,
    this.onArrowRight,
    this.scrollAlignmentOnFocus,
    this.onFocused,
  });

  final Widget child;
  final VoidCallback onPressed;
  final bool autofocus;
  final double borderRadius;
  final EdgeInsets padding;
  final FocusNode? focusNode;
  final VoidCallback? onArrowUp;
  final VoidCallback? onArrowDown;
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowRight;
  final double? scrollAlignmentOnFocus;
  final VoidCallback? onFocused;

  @override
  State<TvFocus> createState() => _TvFocusState();
}

class _TvFocusState extends State<TvFocus> {
  bool _focused = false;
  bool _hovered = false;

  bool get _desktopHoverActive =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows && _hovered;

  KeyEventResult _directionKeys(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp && widget.onArrowUp != null) {
      widget.onArrowUp!();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown && widget.onArrowDown != null) {
      widget.onArrowDown!();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft && widget.onArrowLeft != null) {
      widget.onArrowLeft!();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight && widget.onArrowRight != null) {
      widget.onArrowRight!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _revealOnlyIfNeeded() {
    if (!mounted) return;

    final scrollable = Scrollable.maybeOf(context);
    final targetObject = context.findRenderObject();

    if (scrollable == null || targetObject is! RenderBox) return;

    final explicitAlignment = widget.scrollAlignmentOnFocus;
    if (explicitAlignment != null) {
      scrollable.position.ensureVisible(
        targetObject,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: explicitAlignment.clamp(0.0, 1.0),
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
      return;
    }

    final viewportObject = scrollable.context.findRenderObject();
    if (viewportObject is! RenderBox) return;

    final targetTopLeft = targetObject.localToGlobal(Offset.zero);
    final targetBottomRight = targetObject.localToGlobal(
      targetObject.size.bottomRight(Offset.zero),
    );

    final viewportTopLeft = viewportObject.localToGlobal(Offset.zero);
    final viewportBottomRight = viewportObject.localToGlobal(
      viewportObject.size.bottomRight(Offset.zero),
    );

    const edgePadding = 10.0;
    final axis = scrollable.axisDirection;

    bool before;
    bool after;

    if (axis == AxisDirection.up || axis == AxisDirection.down) {
      before = targetTopLeft.dy < viewportTopLeft.dy + edgePadding;
      after = targetBottomRight.dy > viewportBottomRight.dy - edgePadding;
    } else {
      before = targetTopLeft.dx < viewportTopLeft.dx + edgePadding;
      after = targetBottomRight.dx > viewportBottomRight.dx - edgePadding;
    }

    // Normal TV behavior: visible controls NEVER move the page.
    if (!before && !after) return;

    scrollable.position.ensureVisible(
      targetObject,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      alignment: before ? 0.0 : 1.0,
      alignmentPolicy: before
          ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
          : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _focused || _desktopHoverActive;
    final focusedBorder = Border.all(
      color: Colors.white.withOpacity(.96),
      width: 3,
    );

    return Focus(
      canRequestFocus: false,
      onKeyEvent: _directionKeys,
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        },
        child: FocusableActionDetector(
          autofocus: widget.autofocus,
          focusNode: widget.focusNode,
          onShowFocusHighlight: (value) {
            if (_focused == value) return;
            setState(() => _focused = value);
            if (value) {
              widget.onFocused?.call();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _revealOnlyIfNeeded();
              });
            }
          },
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onPressed();
                return null;
              },
            ),
          },
          child: MouseRegion(
            cursor: !kIsWeb && defaultTargetPlatform == TargetPlatform.windows
                ? SystemMouseCursors.click
                : MouseCursor.defer,
            onEnter: (_) {
              if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows && !_hovered) {
                setState(() => _hovered = true);
              }
            },
            onExit: (_) {
              if (_hovered) setState(() => _hovered = false);
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onPressed,
              child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOutCubic,
              padding: widget.padding,
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                border: active ? focusedBorder : null,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                color: active ? TvColors.red.withOpacity(.065) : null,
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: Colors.white.withOpacity(.13),
                          blurRadius: 0,
                          spreadRadius: 1,
                        ),
                        BoxShadow(
                          color: TvColors.red.withOpacity(.34),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  widget.child,
                  if (active)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: IgnorePointer(
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: TvColors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}
