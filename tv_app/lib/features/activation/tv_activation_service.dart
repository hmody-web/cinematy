import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TvActivationResult {
  const TvActivationResult({
    required this.ok,
    required this.message,
    this.name,
    this.expiresAt,
    this.status,
    this.maxDevices,
    this.fromCache = false,
  });

  final bool ok;
  final String message;
  final String? name;
  final DateTime? expiresAt;
  final String? status;
  final int? maxDevices;
  final bool fromCache;

  bool get expiredLocally =>
      expiresAt != null && !DateTime.now().isBefore(expiresAt!);

  TvActivationResult copyWith({
    bool? ok,
    String? message,
    String? name,
    DateTime? expiresAt,
    String? status,
    int? maxDevices,
    bool? fromCache,
  }) {
    return TvActivationResult(
      ok: ok ?? this.ok,
      message: message ?? this.message,
      name: name ?? this.name,
      expiresAt: expiresAt ?? this.expiresAt,
      status: status ?? this.status,
      maxDevices: maxDevices ?? this.maxDevices,
      fromCache: fromCache ?? this.fromCache,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'ok': ok,
        'message': message,
        'name': name,
        'expiresAt': expiresAt?.toUtc().toIso8601String(),
        'status': status,
        'maxDevices': maxDevices,
      };

  factory TvActivationResult.fromJson(Map<String, dynamic> json) {
    return TvActivationResult(
      ok: json['ok'] == true,
      message: (json['message'] ?? '').toString(),
      name: json['name']?.toString(),
      expiresAt: DateTime.tryParse((json['expiresAt'] ?? '').toString())?.toLocal(),
      status: json['status']?.toString(),
      maxDevices: int.tryParse((json['maxDevices'] ?? '').toString()),
      fromCache: true,
    );
  }
}

class TvActivationService {
  TvActivationService._();
  static final TvActivationService instance = TvActivationService._();

  static const _channel = MethodChannel('com.cinematy.tv/device');
  static const _tokenKey = 'cinematy_tv_activation_token_v2';
  static const _snapshotKey = 'cinematy_tv_activation_snapshot_v3';
  static const _webDeviceKey = 'cinematy_tv_web_device_id_v1';
  static const _windowsDeviceKey = 'cinematy_tv_windows_device_id_v1';
  static const _endpointParts = <String>[
    'https://scrptaty.com',
    '/pannel/',
    'tv_activation.php',
  ];

  static const _tokenMinLength = 40;

  late final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _endpointParts.join(),
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 7),
      sendTimeout: const Duration(seconds: 6),
      responseType: ResponseType.json,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      validateStatus: (code) => code != null && code >= 200 && code < 500,
    ),
  );

  Map<String, String>? _device;

  /// Live subscription snapshot used by the Library screen and activation gate.
  final ValueNotifier<TvActivationResult?> subscription =
      ValueNotifier<TvActivationResult?>(null);

  Future<Map<String, String>> _deviceInfo() async {
    if (_device != null) return _device!;

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      var id = (prefs.getString(_webDeviceKey) ?? '').trim();
      if (id.length < 16) {
        id = _randomInstallId('web', 24);
        await prefs.setString(_webDeviceKey, id);
      }
      return _device = {'id': id, 'name': 'Cinematy TV • Chrome'};
    }

    if (defaultTargetPlatform == TargetPlatform.windows) {
      final prefs = await SharedPreferences.getInstance();
      var id = (prefs.getString(_windowsDeviceKey) ?? '').trim();
      if (id.length < 16) {
        id = _randomInstallId('win', 32);
        await prefs.setString(_windowsDeviceKey, id);
      }
      return _device = {'id': id, 'name': 'Cinematy TV • Windows'};
    }

    final raw =
        await _channel.invokeMapMethod<String, dynamic>('deviceInfo') ?? const {};
    final id = (raw['id'] ?? '').toString().trim();
    final name = (raw['name'] ?? 'Android TV').toString().trim();
    if (id.length < 8) throw StateError('تعذر التعرف على الجهاز.');
    return _device = {
      'id': id,
      'name': name.isEmpty ? 'Android TV' : name,
    };
  }

  String _randomInstallId(String prefix, int byteCount) {
    final random = Random.secure();
    final bytes = List<int>.generate(byteCount, (_) => random.nextInt(256));
    return '$prefix-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }

  /// Fast local decision used at startup. A previously activated user enters
  /// immediately even when the network is unavailable; no activation UI is
  /// allowed to flash over playback just because the status endpoint timed out.
  Future<TvActivationResult> localAccess() async {
    final prefs = await SharedPreferences.getInstance();
    final token = (prefs.getString(_tokenKey) ?? '').trim();
    if (token.length < _tokenMinLength) {
      const result = TvActivationResult(
        ok: false,
        message: 'أدخل رمز التفعيل للمتابعة.',
        status: 'not_activated',
        fromCache: true,
      );
      subscription.value = result;
      return result;
    }

    final cached = _readSnapshot(prefs);
    if (cached != null) {
      if (cached.expiredLocally) {
        final result = cached.copyWith(
          ok: false,
          message: 'انتهت مدة الاشتراك.',
          status: 'expired',
          fromCache: true,
        );
        subscription.value = result;
        return result;
      }
      final result = cached.copyWith(
        ok: true,
        message: '',
        fromCache: true,
      );
      subscription.value = result;
      return result;
    }

    // Compatibility with installations activated by an older build before a
    // local subscription snapshot existed. The token itself is proof that this
    // installation was activated previously; the first successful online check
    // will immediately create the full snapshot (including expiry).
    const result = TvActivationResult(
      ok: true,
      message: '',
      status: 'cached_token',
      fromCache: true,
    );
    subscription.value = result;
    return result;
  }

  Future<TvActivationResult> activate(String code) async {
    try {
      final device = await _deviceInfo();
      final res = await _dio.post(
        '',
        data: {
          'action': 'activate',
          'code': code.trim(),
          'device_id': device['id'],
          'device_name': device['name'],
        },
      );
      final raw = res.data;
      if (raw is! Map || !raw.containsKey('ok') || raw['ok'] is! bool) {
        return const TvActivationResult(
          ok: false,
          message: 'تعذر الاتصال بخادم التفعيل. تحقق من الإنترنت وحاول مجددًا.',
        );
      }
      final data = Map<String, dynamic>.from(raw);
      final ok = data['ok'] == true;
      if (ok) {
        final token = (data['token'] ?? '').toString().trim();
        if (token.length < _tokenMinLength) {
          return const TvActivationResult(
            ok: false,
            message: 'تعذر إكمال التفعيل.',
          );
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenKey, token);
      }
      final result = _resultFrom(data, ok);
      if (ok) await _saveSnapshot(result);
      subscription.value = result;
      return result;
    } on DioException catch (e) {
      final body = e.response?.data;
      if (body is Map && body['message'] != null) {
        return TvActivationResult(
          ok: false,
          message: body['message'].toString(),
        );
      }
      return const TvActivationResult(
        ok: false,
        message: 'تعذر الاتصال بخادم التفعيل. تحقق من الإنترنت وحاول مجددًا.',
      );
    } catch (_) {
      return const TvActivationResult(
        ok: false,
        message: 'تعذر التحقق من هذا الجهاز.',
      );
    }
  }

  /// Performs an online status refresh when possible. Network failures never
  /// revoke a valid local subscription. Only an explicit server response (or a
  /// locally reached expiry) can close the app again.
  Future<TvActivationResult> validate() async {
    final prefs = await SharedPreferences.getInstance();
    final token = (prefs.getString(_tokenKey) ?? '').trim();
    if (token.length < _tokenMinLength) return localAccess();

    try {
      final device = await _deviceInfo();
      final res = await _dio.post(
        '',
        data: {
          'action': 'status',
          'token': token,
          'device_id': device['id'],
          'device_name': device['name'],
        },
      );
      final raw = res.data;
      if (raw is! Map || !raw.containsKey('ok') || raw['ok'] is! bool) {
        // HTML/WAF/hosting 403 pages and malformed responses are connectivity
        // failures, not subscription revocations. Keep the last valid local
        // entitlement so playback is never interrupted by a transient server.
        return localAccess();
      }
      final data = Map<String, dynamic>.from(raw);
      final ok = data['ok'] == true;
      final result = _resultFrom(data, ok);

      if (ok) {
        await _saveSnapshot(result);
      } else {
        // A structured {ok:false} response is an explicit server-side denial
        // (expiry, revoke, disabled account, device limit, invalid token, etc.).
        // Persist that decision by removing the old entitlement immediately.
        await prefs.remove(_tokenKey);
        await prefs.remove(_snapshotKey);
      }

      subscription.value = result;
      return result;
    } on DioException {
      return localAccess();
    } catch (_) {
      return localAccess();
    }
  }

  TvActivationResult? _readSnapshot(SharedPreferences prefs) {
    final raw = prefs.getString(_snapshotKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return TvActivationResult.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveSnapshot(TvActivationResult result) async {
    if (!result.ok) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _snapshotKey,
      jsonEncode(result.copyWith(fromCache: false).toJson()),
    );
  }

  TvActivationResult _resultFrom(Map<String, dynamic> data, bool ok) {
    final sub = data['subscription'] is Map
        ? Map<String, dynamic>.from(data['subscription'] as Map)
        : const <String, dynamic>{};
    DateTime? expiry;
    final rawExpiry = sub['expires_at']?.toString();
    if (rawExpiry != null && rawExpiry.isNotEmpty) {
      expiry = DateTime.tryParse(rawExpiry)?.toLocal();
    }
    return TvActivationResult(
      ok: ok,
      message: (data['message'] ??
              (ok ? 'تم التفعيل بنجاح.' : 'رمز التفعيل غير صحيح.'))
          .toString(),
      name: sub['name']?.toString(),
      expiresAt: expiry,
      status: (sub['status'] ?? data['status'])?.toString(),
      maxDevices: int.tryParse((sub['max_devices'] ?? '').toString()),
    );
  }

  Future<void> openTelegram() async {
    await _channel.invokeMethod('openTelegram', {'username': 'mooo5'});
  }
}
