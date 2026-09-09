import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TvIosNativeVideoController {
  MethodChannel? _channel;
  bool _playing = true;

  bool get isAttached => _channel != null;
  bool get isPlaying => _playing;

  void attach(int id) {
    _channel = MethodChannel('cinematy/tv_native_player/$id');
  }

  Future<void> open(String url) async {
    await _channel?.invokeMethod<void>('open', {'url': url});
    _playing = true;
  }

  Future<void> play() async {
    await _channel?.invokeMethod<void>('play');
    _playing = true;
  }

  Future<void> pause() async {
    await _channel?.invokeMethod<void>('pause');
    _playing = false;
  }

  Future<void> startPip() async {
    await _channel?.invokeMethod<void>('startPiP');
  }

  Future<void> stopPip() async {
    await _channel?.invokeMethod<void>('stopPiP');
  }
}

class TvIosNativeVideo extends StatelessWidget {
  const TvIosNativeVideo({
    super.key,
    required this.url,
    required this.controller,
  });

  final String url;
  final TvIosNativeVideoController controller;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) return const SizedBox.shrink();
    return UiKitView(
      viewType: 'cinematy/tv_native_player',
      creationParams: {'url': url},
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: controller.attach,
    );
  }
}
