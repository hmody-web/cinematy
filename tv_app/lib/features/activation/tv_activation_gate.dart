import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../tv_ui_frame.dart';
import '../../tv_shell.dart';
import 'tv_activation_service.dart';

class TvActivationGate extends StatefulWidget {
  const TvActivationGate({super.key});

  @override
  State<TvActivationGate> createState() => _TvActivationGateState();
}

class _TvActivationGateState extends State<TvActivationGate>
    with WidgetsBindingObserver {
  bool _checking = true;
  bool _unlocked = false;
  String _message = '';
  Timer? _periodic;
  Timer? _expiryTimer;
  bool _rechecking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    final local = await TvActivationService.instance.localAccess();
    if (!mounted) return;

    if (local.ok) {
      _unlock(local);
      // Refresh server state in the background. A network outage cannot close
      // the app, while an explicit revoke/disable/expiry still can.
      unawaited(_silentRecheck());
      return;
    }

    // A locally expired subscription may have been extended from the panel.
    // Give the server one chance to refresh it before showing the activation UI.
    if (local.status == 'expired') {
      final refreshed = await TvActivationService.instance.validate();
      if (!mounted) return;
      if (refreshed.ok) {
        _unlock(refreshed);
        return;
      }
      setState(() {
        _checking = false;
        _unlocked = false;
        _message = refreshed.message;
      });
      return;
    }

    setState(() {
      _checking = false;
      _unlocked = false;
      _message = local.message;
    });
  }

  void _unlock(TvActivationResult result) {
    if (!mounted) return;
    setState(() {
      _checking = false;
      _unlocked = true;
      _message = '';
    });
    _armLiveValidation(result);
  }

  void _armLiveValidation(TvActivationResult result) {
    _periodic ??= Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_silentRecheck()),
    );
    _armExpiry(result.expiresAt);
  }

  void _armExpiry(DateTime? expiry) {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    if (expiry == null) return;

    final remaining = expiry.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      scheduleMicrotask(_silentRecheck);
      return;
    }
    _expiryTimer = Timer(
      remaining + const Duration(milliseconds: 100),
      () => unawaited(_silentRecheck()),
    );
  }

  Future<void> _silentRecheck() async {
    if (_rechecking) return;
    _rechecking = true;
    final result = await TvActivationService.instance.validate();
    _rechecking = false;
    if (!mounted) return;

    if (result.ok) {
      if (!_unlocked) {
        _unlock(result);
      } else {
        _armExpiry(result.expiresAt);
      }
      return;
    }

    // validate() already falls back to the local snapshot on connection
    // failures. Reaching this branch therefore means a real expiry/revoke/
    // disable/device denial and is the only time playback is interrupted.
    _periodic?.cancel();
    _periodic = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    setState(() {
      _checking = false;
      _unlocked = false;
      _message = result.message;
    });
  }

  void _activated() {
    final snapshot = TvActivationService.instance.subscription.value;
    _unlock(
      snapshot ??
          const TvActivationResult(
            ok: true,
            message: '',
          ),
    );
    unawaited(_silentRecheck());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _unlocked) {
      unawaited(_silentRecheck());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _periodic?.cancel();
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return const TvUiFrame(child: TvShell());

    // Never create/focus the code TextField while an existing subscription is
    // merely being checked. This prevents a keyboard from appearing behind a
    // movie, match or channel on slower/offline devices.
    if (_checking) {
      return const TvUiFrame(child: _ActivationCheckingView());
    }

    return TvUiFrame(
      child: TvActivationScreen(
        initialMessage: _message,
        onActivated: _activated,
      ),
    );
  }
}

class _ActivationCheckingView extends StatelessWidget {
  const _ActivationCheckingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF080A0D),
      body: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}

class TvActivationScreen extends StatefulWidget {
  const TvActivationScreen({super.key, required this.onActivated, this.initialMessage = ''});
  final VoidCallback onActivated;
  final String initialMessage;

  @override
  State<TvActivationScreen> createState() => _TvActivationScreenState();
}

class _TvActivationScreenState extends State<TvActivationScreen> with TickerProviderStateMixin {
  final _controller = TextEditingController();
  late final FocusNode _focus;
  late final FocusNode _purchaseFocus;
  Timer? _debounce;
  bool _verifying = false;
  bool _success = false;
  String _message = '';
  late final AnimationController _shake;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _message = widget.initialMessage;
    _focus = FocusNode(onKeyEvent: (node, event) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _purchaseFocus.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    });
    _purchaseFocus = FocusNode(onKeyEvent: (node, event) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _focus.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    });
    _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 850));
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void didUpdateWidget(covariant TvActivationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialMessage != oldWidget.initialMessage && widget.initialMessage.isNotEmpty) setState(() => _message = widget.initialMessage);
  }

  void _changed(String value) {
    _message = '';
    _debounce?.cancel();
    if (value.length == 6) {
      _debounce = Timer(const Duration(milliseconds: 260), _verify);
    }
    setState(() {});
  }

  Future<void> _verify() async {
    if (_verifying || _controller.text.length != 6) return;
    setState(() { _verifying = true; _message = ''; });
    final result = await TvActivationService.instance.activate(_controller.text);
    if (!mounted) return;
    if (result.ok) {
      HapticFeedback.mediumImpact();
      setState(() { _verifying = false; _success = true; _message = result.message; });
      // Enter immediately after a very short success cue; no app restart is needed.
      _pulse.forward(from: 0);
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (!mounted) return;
      widget.onActivated();
    } else {
      HapticFeedback.vibrate();
      setState(() { _verifying = false; _success = false; _message = result.message; });
      await _shake.forward(from: 0);
      if (!mounted) return;
      _controller.clear();
      _focus.requestFocus();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    _purchaseFocus.dispose();
    _shake.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFE72B3F);
    final chars = _controller.text.characters.toList();
    return Scaffold(
      backgroundColor: const Color(0xFF080A0D),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _ActivationBackdrop(),
          Center(
            child: SizedBox(
              width: 920,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: const [BoxShadow(color: Color(0x55E72B3F), blurRadius: 42, spreadRadius: 2)],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset('assets/branding/app_icon.jpg', fit: BoxFit.cover),
                  ),
                  const SizedBox(height: 28),
                  const Text('تفعيل سينماتي TV', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: Colors.white)),
                  const SizedBox(height: 10),
                  Text('أدخل رمز التفعيل المكوّن من 6 خانات للمتابعة', textAlign: TextAlign.center, style: TextStyle(fontSize: 19, color: Colors.white.withValues(alpha: .66), fontWeight: FontWeight.w600)),
                  const SizedBox(height: 42),
                  AnimatedBuilder(
                    animation: Listenable.merge([_shake, _pulse]),
                    builder: (context, child) {
                      final shakeX = _shake.isAnimating ? (1 - _shake.value) * 11 * ((_shake.value * 8).floor().isEven ? 1 : -1) : 0.0;
                      final scale = _success ? 1 + (.035 * (1 - (_pulse.value - .5).abs() * 2).clamp(0, 1)) : 1.0;
                      return Transform.translate(offset: Offset(shakeX, 0), child: Transform.scale(scale: scale, child: child));
                    },
                    child: GestureDetector(
                      onTap: () => _focus.requestFocus(),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            textDirection: TextDirection.ltr,
                            children: List.generate(6, (i) {
                              final filled = i < chars.length;
                              final active = i == chars.length && !_verifying;
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                margin: const EdgeInsets.symmetric(horizontal: 8),
                                width: 92,
                                height: 108,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: _success ? const Color(0x182ED27A) : (active ? const Color(0x18E72B3F) : const Color(0xB013161B)),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: _success ? const Color(0xFF2ED27A) : (active ? red : Colors.white.withValues(alpha: filled ? .22 : .10)), width: active || _success ? 2 : 1),
                                  boxShadow: active ? const [BoxShadow(color: Color(0x28E72B3F), blurRadius: 28)] : null,
                                ),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 170),
                                  transitionBuilder: (child, animation) => ScaleTransition(scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack), child: FadeTransition(opacity: animation, child: child)),
                                  child: Text(filled ? chars[i] : '', key: ValueKey('$i-${filled ? chars[i] : ''}'), style: const TextStyle(fontSize: 40, height: 1, fontWeight: FontWeight.w900, color: Colors.white, fontFamily: 'Monadi')),
                                ),
                              );
                            }),
                          ),
                          Opacity(
                            opacity: .01,
                            child: SizedBox(
                              width: 620,
                              height: 108,
                              child: TextField(
                                controller: _controller,
                                focusNode: _focus,
                                autofocus: true,
                                enabled: !_verifying && !_success,
                                maxLength: 6,
                                textDirection: TextDirection.ltr,
                                keyboardType: TextInputType.visiblePassword,
                                textCapitalization: TextCapitalization.none,
                                autocorrect: false,
                                enableSuggestions: false,
                                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')), LengthLimitingTextInputFormatter(6)],
                                onChanged: _changed,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    height: 52,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _verifying
                          ? const Row(key: ValueKey('loading'), mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: red)), SizedBox(width: 12), Text('جاري التحقق…', style: TextStyle(fontSize: 17, color: Colors.white70, fontWeight: FontWeight.w700))])
                          : _message.isEmpty
                              ? const SizedBox(key: ValueKey('empty'))
                              : Container(key: ValueKey(_message), padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12), decoration: BoxDecoration(color: (_success ? const Color(0xFF2ED27A) : red).withValues(alpha: .10), borderRadius: BorderRadius.circular(16), border: Border.all(color: (_success ? const Color(0xFF2ED27A) : red).withValues(alpha: .35))), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(_success ? Icons.check_circle_rounded : Icons.info_rounded, color: _success ? const Color(0xFF51DE90) : const Color(0xFFFF6677)), const SizedBox(width: 10), Text(_message, style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w700))])),
                    ),
                  ),
                  const SizedBox(height: 34),
                  AnimatedBuilder(
                    animation: _purchaseFocus,
                    builder: (context, _) {
                      final focused = _purchaseFocus.hasFocus;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: focused ? red : Colors.transparent, width: 2)),
                        child: TextButton.icon(
                          autofocus: false,
                          focusNode: _purchaseFocus,
                          onPressed: () => TvActivationService.instance.openTelegram(),
                          icon: const Icon(Icons.send_rounded, size: 20),
                          label: const Text('لشراء رمز تفعيل، اضغط هنا'),
                          style: TextButton.styleFrom(foregroundColor: Colors.white.withValues(alpha: .82), textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivationBackdrop extends StatelessWidget {
  const _ActivationBackdrop();
  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(child: DecoratedBox(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF14090C), Color(0xFF090B0E), Color(0xFF07090C)])))),
      Positioned(right: -160, top: -180, child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90), child: Container(width: 520, height: 520, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x42E72B3F))))),
      Positioned(left: -120, bottom: -230, child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 100, sigmaY: 100), child: Container(width: 520, height: 520, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x181A5CFF))))),
      Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _GridPainter()))),
    ]);
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withValues(alpha: .025)..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 64) canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    for (double y = 0; y < size.height; y += 64) canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
