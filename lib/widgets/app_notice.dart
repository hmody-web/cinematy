import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

enum AppNoticeType { info, success, error, download }

class AppNotice {
  AppNotice._();

  static void show(
    BuildContext context, {
    required String title,
    String message = '',
    AppNoticeType type = AppNoticeType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _NoticeEntry(
        title: title,
        message: message,
        type: type,
        duration: duration,
        onClose: () {
          if (entry.mounted) entry.remove();
        },
      ),
    );
    overlay.insert(entry);
  }
}

class _NoticeEntry extends StatefulWidget {
  const _NoticeEntry({
    required this.title,
    required this.message,
    required this.type,
    required this.duration,
    required this.onClose,
  });

  final String title;
  final String message;
  final AppNoticeType type;
  final Duration duration;
  final VoidCallback onClose;

  @override
  State<_NoticeEntry> createState() => _NoticeEntryState();
}

class _NoticeEntryState extends State<_NoticeEntry> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  Timer? _timer;
  Offset _drag = Offset.zero;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween(begin: const Offset(.18, -.18), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();
    _timer = Timer(widget.duration, _close);
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    try {
      await _controller.reverse();
    } finally {
      widget.onClose();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  IconData get _icon => switch (widget.type) {
        AppNoticeType.success => Icons.check_circle_rounded,
        AppNoticeType.error => Icons.error_rounded,
        AppNoticeType.download => Icons.download_for_offline_rounded,
        AppNoticeType.info => Icons.info_rounded,
      };

  Color get _accent => switch (widget.type) {
        AppNoticeType.success => AppColors.success,
        AppNoticeType.error => AppColors.redBright,
        AppNoticeType.download => const Color(0xFF7ACBFF),
        AppNoticeType.info => Colors.white,
      };

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + 12;
    return Positioned(
      top: top,
      right: 14,
      child: SafeArea(
        bottom: false,
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _fade,
            child: Transform.translate(
              offset: _drag,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) {
                  final dx = d.delta.dx > 0 ? d.delta.dx : 0.0;
                  final dy = d.delta.dy < 0 ? d.delta.dy : 0.0;
                  setState(() => _drag += Offset(dx, dy));
                  if (_drag.dx > 70 || _drag.dy < -55) _close();
                },
                onPanEnd: (_) {
                  if (!_closing) setState(() => _drag = Offset.zero);
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                    child: Container(
                      width: 310,
                      constraints: const BoxConstraints(minHeight: 66),
                      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
                      decoration: BoxDecoration(
                        color: const Color(0xE9151111),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(.11)),
                        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 28, offset: Offset(0, 10))],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(color: _accent.withOpacity(.13), borderRadius: BorderRadius.circular(13)),
                            child: Icon(_icon, color: _accent, size: 21),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: Colors.white)),
                                if (widget.message.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(widget.message, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, height: 1.35, color: Colors.white.withOpacity(.58))),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(onPressed: _close, visualDensity: VisualDensity.compact, icon: const Icon(Icons.close_rounded, size: 17)),
                        ],
                      ),
                    ),
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
