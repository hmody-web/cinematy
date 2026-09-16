import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class ActivationResult {
  const ActivationResult({
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

  ActivationResult copyWith({
    bool? ok,
    String? message,
    String? name,
    DateTime? expiresAt,
    String? status,
    int? maxDevices,
    bool? fromCache,
  }) {
    return ActivationResult(
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

  factory ActivationResult.fromJson(Map<String, dynamic> json) {
    return ActivationResult(
      ok: json['ok'] == true,
      message: (json['message'] ?? '').toString(),
      name: json['name']?.toString(),
      expiresAt:
          DateTime.tryParse((json['expiresAt'] ?? '').toString())?.toLocal(),
      status: json['status']?.toString(),
      maxDevices: int.tryParse((json['maxDevices'] ?? '').toString()),
      fromCache: true,
    );
  }
}

class ActivationService {
  ActivationService._();
  static final ActivationService instance = ActivationService._();

  static const _tokenKey = 'cinematy_activation_token_v1';
  static const _snapshotKey = 'cinematy_activation_snapshot_v1';
  static const _deviceKey = 'cinematy_activation_device_id_v1';
  static const _tokenMinLength = 40;
  static const _endpoint = 'https://scrptaty.com/pannel/tv_activation.php';

  late final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _endpoint,
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

  final ValueNotifier<ActivationResult?> subscription =
      ValueNotifier<ActivationResult?>(null);

  Map<String, String>? _device;

  Future<Map<String, String>> _deviceInfo() async {
    if (_device != null) return _device!;
    final prefs = await SharedPreferences.getInstance();
    var id = (prefs.getString(_deviceKey) ?? '').trim();
    if (id.length < 16) {
      final random = Random.secure();
      final bytes = List<int>.generate(32, (_) => random.nextInt(256));
      id = 'app-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
      await prefs.setString(_deviceKey, id);
    }

    final platform = kIsWeb
        ? 'Chrome'
        : switch (defaultTargetPlatform) {
            TargetPlatform.android => 'Android',
            TargetPlatform.iOS => 'iPhone / iPad',
            TargetPlatform.windows => 'Windows',
            TargetPlatform.macOS => 'macOS',
            TargetPlatform.linux => 'Linux',
            TargetPlatform.fuchsia => 'Device',
          };
    return _device = <String, String>{
      'id': id,
      'name': 'Cinematy • $platform',
    };
  }

  Future<ActivationResult> localAccess() async {
    final prefs = await SharedPreferences.getInstance();
    final token = (prefs.getString(_tokenKey) ?? '').trim();
    if (token.length < _tokenMinLength) {
      const result = ActivationResult(
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

    // Existing installations from an older build may already have a token but
    // no cached subscription payload. Let them enter offline and populate the
    // expiry snapshot on the next successful server refresh.
    const result = ActivationResult(
      ok: true,
      message: '',
      status: 'cached_token',
      fromCache: true,
    );
    subscription.value = result;
    return result;
  }

  Future<ActivationResult> activate(String code) async {
    try {
      final device = await _deviceInfo();
      final response = await _dio.post(
        '',
        data: <String, dynamic>{
          'action': 'activate',
          'code': code.trim(),
          'device_id': device['id'],
          'device_name': device['name'],
        },
      );
      final raw = response.data;
      if (raw is! Map || !raw.containsKey('ok') || raw['ok'] is! bool) {
        return const ActivationResult(
          ok: false,
          message: 'تعذر الاتصال بخادم التفعيل. تحقق من الإنترنت وحاول مجددًا.',
        );
      }
      final data = Map<String, dynamic>.from(raw);
      final ok = data['ok'] == true;
      if (ok) {
        final token = (data['token'] ?? '').toString().trim();
        if (token.length < _tokenMinLength) {
          return const ActivationResult(
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
    } on DioException catch (error) {
      final body = error.response?.data;
      if (body is Map && body['message'] != null) {
        return ActivationResult(
          ok: false,
          message: body['message'].toString(),
        );
      }
      return const ActivationResult(
        ok: false,
        message: 'تعذر الاتصال بخادم التفعيل. تحقق من الإنترنت وحاول مجددًا.',
      );
    } catch (_) {
      return const ActivationResult(
        ok: false,
        message: 'تعذر التحقق من هذا الجهاز.',
      );
    }
  }

  Future<ActivationResult> validate() async {
    final prefs = await SharedPreferences.getInstance();
    final token = (prefs.getString(_tokenKey) ?? '').trim();
    if (token.length < _tokenMinLength) return localAccess();

    try {
      final device = await _deviceInfo();
      final response = await _dio.post(
        '',
        data: <String, dynamic>{
          'action': 'status',
          'token': token,
          'device_id': device['id'],
          'device_name': device['name'],
        },
      );
      final raw = response.data;
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

  ActivationResult? _readSnapshot(SharedPreferences prefs) {
    final raw = prefs.getString(_snapshotKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return ActivationResult.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveSnapshot(ActivationResult result) async {
    if (!result.ok) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _snapshotKey,
      jsonEncode(result.copyWith(fromCache: false).toJson()),
    );
  }

  ActivationResult _resultFrom(Map<String, dynamic> data, bool ok) {
    final sub = data['subscription'] is Map
        ? Map<String, dynamic>.from(data['subscription'] as Map)
        : const <String, dynamic>{};
    DateTime? expiry;
    final rawExpiry = sub['expires_at']?.toString();
    if (rawExpiry != null && rawExpiry.isNotEmpty) {
      expiry = DateTime.tryParse(rawExpiry)?.toLocal();
    }
    return ActivationResult(
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
    await launchUrl(
      Uri.parse('https://t.me/mooo5'),
      mode: LaunchMode.externalApplication,
    );
  }
}
