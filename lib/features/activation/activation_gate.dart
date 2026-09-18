import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import 'activation_service.dart';

class CinematyActivationGate extends StatefulWidget {
  const CinematyActivationGate({super.key, required this.child});

  final Widget child;

  @override
  State<CinematyActivationGate> createState() => _CinematyActivationGateState();
}

class _CinematyActivationGateState extends State<CinematyActivationGate>
    with WidgetsBindingObserver {
  bool _checking = true;
  bool _unlocked = false;
  bool _rechecking = false;
  String _message = '';
  Timer? _periodic;
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    final local = await ActivationService.instance.localAccess();
    if (!mounted) return;

    if (local.ok) {
      _unlock(local);
      unawaited(_silentRecheck());
      return;
    }

    if (local.status == 'expired') {
      final refreshed = await ActivationService.instance.validate();
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

  void _unlock(ActivationResult result) {
    if (!mounted) return;
    setState(() {
      _checking = false;
      _unlocked = true;
      _message = '';
    });
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
    final result = await ActivationService.instance.validate();
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
    final snapshot = ActivationService.instance.subscription.value;
    _unlock(
      snapshot ?? const ActivationResult(ok: true, message: ''),
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
    if (_unlocked) return widget.child;
    if (_checking) return const _ActivationCheckingView();
    return _ActivationScreen(
      initialMessage: _message,
      onActivated: _activated,
    );
  }
}

class _ActivationCheckingView extends StatelessWidget {
  const _ActivationCheckingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
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

class _ActivationScreen extends StatefulWidget {
  const _ActivationScreen({
    required this.onActivated,
    this.initialMessage = '',
  });

  final VoidCallback onActivated;
  final String initialMessage;

  @override
  State<_ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<_ActivationScreen>
    with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _codeFocus = FocusNode();
  Timer? _debounce;
  bool _verifying = false;
  bool _success = false;
  late String _message;
  late final AnimationController _shake;

  @override
  void initState() {
    super.initState();
    _message = widget.initialMessage;
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _codeFocus.requestFocus();
    });
  }

  void _changed(String value) {
    _debounce?.cancel();
    setState(() {
      if (_message.isNotEmpty) _message = '';
    });
    if (value.length == 6) {
      _debounce = Timer(const Duration(milliseconds: 220), _verify);
    }
  }

  Future<void> _verify() async {
    if (_verifying || _controller.text.length != 6) return;
    setState(() {
      _verifying = true;
      _message = '';
    });
    final result = await ActivationService.instance.activate(_controller.text);
    if (!mounted) return;

    if (result.ok) {
      HapticFeedback.mediumImpact();
      setState(() {
        _verifying = false;
        _success = true;
        _message = result.message;
      });
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (mounted) widget.onActivated();
      return;
    }

    HapticFeedback.vibrate();
    setState(() {
      _verifying = false;
      _success = false;
      _message = result.message;
    });
    await _shake.forward(from: 0);
    if (!mounted) return;
    _controller.clear();
    _codeFocus.requestFocus();
    setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _codeFocus.dispose();
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final desktop = size.width >= 800;
    final maxWidth = desktop ? 640.0 : 430.0;
    final boxSize = ((size.width - 72) / 6).clamp(42.0, desktop ? 78.0 : 58.0);
    final chars = _controller.text.characters.toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _ActivationBackdrop(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: desktop ? 88 : 74,
                        height: desktop ? 88 : 74,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(desktop ? 25 : 21),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.redBright.withOpacity(.28),
                              blurRadius: 34,
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/branding/app_icon.jpg',
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'تفعيل سينماتي',
                        style: TextStyle(
                          fontSize: desktop ? 34 : 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        'أدخل رمز التفعيل المكوّن من 6 خانات. بعد التفعيل لن تظهر هذه الشاشة مجددًا إلا عند انتهاء الاشتراك أو إيقافه.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(.60),
                          fontSize: desktop ? 16 : 14,
                          height: 1.55,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 30),
                      AnimatedBuilder(
                        animation: _shake,
                        builder: (context, child) {
                          final x = _shake.isAnimating
                              ? (1 - _shake.value) *
                                  8 *
                                  ((_shake.value * 8).floor().isEven ? 1 : -1)
                              : 0.0;
                          return Transform.translate(
                            offset: Offset(x, 0),
                            child: child,
                          );
                        },
                        child: GestureDetector(
                          onTap: _codeFocus.requestFocus,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                textDirection: TextDirection.ltr,
                                children: List.generate(6, (index) {
                                  final filled = index < chars.length;
                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    width: boxSize,
                                    height: boxSize * 1.12,
                                    margin: EdgeInsets.symmetric(
                                      horizontal: desktop ? 6 : 3.5,
                                    ),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: _success
                                          ? const Color(0x182ED27A)
                                          : Colors.white.withOpacity(.045),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: _success
                                            ? const Color(0xFF2ED27A)
                                            : filled
                                                ? AppColors.redBright
                                                : Colors.white.withOpacity(.12),
                                        width: filled ? 1.7 : 1,
                                      ),
                                    ),
                                    child: Text(
                                      filled ? chars[index] : '',
                                      style: TextStyle(
                                        fontSize: boxSize * .42,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  );
                                }),
                              ),
                              Opacity(
                                opacity: .01,
                                child: SizedBox(
                                  width: maxWidth,
                                  height: boxSize * 1.2,
                                  child: TextField(
                                    controller: _controller,
                                    focusNode: _codeFocus,
                                    enabled: !_verifying && !_success,
                                    maxLength: 6,
                                    textDirection: TextDirection.ltr,
                                    keyboardType: TextInputType.visiblePassword,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                        RegExp(r'[A-Za-z0-9]'),
                                      ),
                                      LengthLimitingTextInputFormatter(6),
                                    ],
                                    onChanged: _changed,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: _verifying
                            ? const SizedBox(
                                key: ValueKey('loading'),
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2.5),
                              )
                            : _message.isEmpty
                                ? const SizedBox(key: ValueKey('empty'), height: 24)
                                : Container(
                                    key: ValueKey(_message),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 15,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: (_success
                                              ? const Color(0xFF2ED27A)
                                              : AppColors.redBright)
                                          .withOpacity(.10),
                                      borderRadius: BorderRadius.circular(13),
                                      border: Border.all(
                                        color: (_success
                                                ? const Color(0xFF2ED27A)
                                                : AppColors.redBright)
                                            .withOpacity(.30),
                                      ),
                                    ),
                                    child: Text(
                                      _message,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                      ),
                      const SizedBox(height: 18),
                      TextButton.icon(
                        onPressed: ActivationService.instance.openTelegram,
                        icon: const Icon(Icons.send_rounded, size: 19),
                        label: const Text('لشراء رمز تفعيل، اضغط هنا'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white.withOpacity(.82),
                          textStyle: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
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
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  Color(0xFF14090C),
                  AppColors.background,
                  Color(0xFF07090C),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: -120,
          top: -150,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 82, sigmaY: 82),
            child: Container(
              width: 390,
              height: 390,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.redBright.withOpacity(.18),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
