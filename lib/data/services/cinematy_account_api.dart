import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/config/app_config.dart';
import '../models/cinematy_user.dart';
import '../models/friend_request.dart';
import '../models/media_item.dart';

class CinematyAccountApiException implements Exception {
  const CinematyAccountApiException(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() => message;
}

class CinematyAccountApi {
  CinematyAccountApi._()
      : _dio = Dio(
          BaseOptions(
            baseUrl: AppConfig.accountApiBaseUrl,
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 15),
            sendTimeout: const Duration(seconds: 15),
            headers: const {'Accept': 'application/json'},
          ),
        );

  static final CinematyAccountApi instance = CinematyAccountApi._();

  final Dio _dio;

  Future<Map<String, String>> _authHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const CinematyAccountApiException(
        'سجّل الدخول أولاً للمتابعة.',
        code: 'auth-required',
        statusCode: 401,
      );
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const CinematyAccountApiException(
        'تعذر التحقق من جلسة الحساب. سجّل الدخول مرة أخرى.',
        code: 'token-missing',
        statusCode: 401,
      );
    }
    return {'Authorization': 'Bearer $token'};
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? query,
  }) async {
    try {
      final route = path.startsWith('/') ? path.substring(1) : path;
      final queryParameters = <String, dynamic>{
        'route': route,
        ...?query,
      };

      final response = await _dio.request<dynamic>(
        'index.php',
        data: data,
        queryParameters: queryParameters,
        options: Options(method: method, headers: await _authHeaders()),
      );
      final payload = response.data;
      if (payload is Map<String, dynamic>) return payload;
      if (payload is Map) return Map<String, dynamic>.from(payload);
      return const {};
    } on DioException catch (error) {
      final payload = error.response?.data;
      if (payload is Map) {
        final map = Map<String, dynamic>.from(payload);
        final code = map['code']?.toString();
        final rawMessage = map['message']?.toString() ?? '';
        final message = switch (code) {
          'auth-required' || 'invalid-token' || 'token-missing' =>
            'انتهت جلسة الحساب. سجّل الدخول مرة أخرى.',
          'server-not-configured' ||
          'database-unavailable' ||
          'auth-service-unavailable' =>
            'خدمة الحساب غير متاحة حالياً. حاول مرة أخرى لاحقاً.',
          _ => rawMessage.trim().isNotEmpty
              ? rawMessage.trim()
              : 'تعذر الاتصال بخدمة الحساب.',
        };
        throw CinematyAccountApiException(
          message,
          code: code,
          statusCode: error.response?.statusCode,
        );
      }
      throw CinematyAccountApiException(
        'تعذر الاتصال بخدمة الحساب. حاول مرة أخرى.',
        code: 'network-error',
        statusCode: error.response?.statusCode,
      );
    }
  }

  Future<CinematyUserProfile> syncProfile() async {
    final payload = await _request('POST', '/profile/sync');
    return CinematyUserProfile.fromJson(
      Map<String, dynamic>.from(payload['user'] as Map? ?? const {}),
    );
  }

  Future<CinematyUserProfile> me() async {
    final payload = await _request('GET', '/profile/me');
    return CinematyUserProfile.fromJson(
      Map<String, dynamic>.from(payload['user'] as Map? ?? const {}),
    );
  }

  Future<CinematyUserProfile> setHandle(String handle) async {
    final payload = await _request(
      'POST',
      '/profile/handle',
      data: {'handle': handle.trim()},
    );
    return CinematyUserProfile.fromJson(
      Map<String, dynamic>.from(payload['user'] as Map? ?? const {}),
    );
  }

  Future<List<CinematyUserProfile>> searchUsers(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final payload = await _request('GET', '/users/search', query: {'q': q});
    final rows = payload['users'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((e) => CinematyUserProfile.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<CinematyUserProfile> publicProfile(String handle) async {
    final payload = await _request('GET', '/users/${Uri.encodeComponent(handle)}');
    return CinematyUserProfile.fromJson(
      Map<String, dynamic>.from(payload['user'] as Map? ?? const {}),
    );
  }

  Future<List<MediaItem>> myFavorites() async {
    final payload = await _request('GET', '/favorites');
    return _mediaList(payload['favorites']);
  }

  Future<List<MediaItem>> userFavorites(String handle) async {
    final payload = await _request(
      'GET',
      '/users/${Uri.encodeComponent(handle)}/favorites',
    );
    return _mediaList(payload['favorites']);
  }

  Future<void> addFavorite(MediaItem item) async {
    await _request(
      'POST',
      '/favorites',
      data: {
        'content_id': item.id,
        'content_type': item.isSeries ? 'series' : 'movie',
        'title': item.title,
        'poster_url': item.posterUrl,
        'backdrop_url': item.backdropUrl,
        'year': item.year,
        'rating': item.rating,
        'snapshot': item.toJson(),
      },
    );
  }

  Future<void> removeFavorite(MediaItem item) async {
    await _request(
      'POST',
      '/favorites/remove',
      data: {
        'content_id': item.id,
        'content_type': item.isSeries ? 'series' : 'movie',
      },
    );
  }


  Future<FriendshipStatus> friendshipStatus(String handle) async {
    final payload = await _request(
      'GET',
      '/friends/status',
      query: {'handle': handle.trim()},
    );
    return FriendshipStatus.fromJson(
      Map<String, dynamic>.from(payload['friendship'] as Map? ?? const {}),
    );
  }

  Future<FriendshipStatus> sendFriendRequest(String handle) async {
    final payload = await _request(
      'POST',
      '/friends/request',
      data: {'handle': handle.trim()},
    );
    return FriendshipStatus.fromJson(
      Map<String, dynamic>.from(payload['friendship'] as Map? ?? const {}),
    );
  }

  Future<FriendshipStatus> cancelFriendRequest(String handle) async {
    final payload = await _request(
      'POST',
      '/friends/cancel',
      data: {'handle': handle.trim()},
    );
    return FriendshipStatus.fromJson(
      Map<String, dynamic>.from(payload['friendship'] as Map? ?? const {}),
    );
  }

  Future<List<FriendRequestItem>> incomingFriendRequests() async {
    final payload = await _request('GET', '/friends/requests');
    final rows = payload['requests'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((e) => FriendRequestItem.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.id > 0)
        .toList();
  }

  Future<int> pendingFriendRequestsCount() async {
    final payload = await _request('GET', '/friends/requests/count');
    return int.tryParse(payload['count']?.toString() ?? '') ?? 0;
  }

  Future<FriendshipStatus> respondToFriendRequest({
    required int requestId,
    required bool accept,
  }) async {
    final payload = await _request(
      'POST',
      '/friends/respond',
      data: {
        'request_id': requestId,
        'action': accept ? 'accept' : 'reject',
      },
    );
    return FriendshipStatus.fromJson(
      Map<String, dynamic>.from(payload['friendship'] as Map? ?? const {}),
    );
  }

  Future<List<CinematyUserProfile>> friends() async {
    final payload = await _request('GET', '/friends');
    final rows = payload['friends'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((e) => CinematyUserProfile.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  List<MediaItem> _mediaList(dynamic rows) {
    if (rows is! List) return const [];
    final result = <MediaItem>[];
    for (final row in rows.whereType<Map>()) {
      final map = Map<String, dynamic>.from(row);
      final snapshot = map['snapshot'];
      if (snapshot is Map) {
        result.add(MediaItem.fromJson(Map<String, dynamic>.from(snapshot)));
        continue;
      }
      result.add(
        MediaItem(
          id: map['content_id']?.toString() ?? '',
          title: map['title']?.toString() ?? '',
          posterUrl: map['poster_url']?.toString() ?? '',
          backdropUrl: map['backdrop_url']?.toString() ?? '',
          year: int.tryParse(map['year']?.toString() ?? '') ?? 0,
          rating: double.tryParse(map['rating']?.toString() ?? '') ?? 0,
          isSeries: map['content_type']?.toString() == 'series',
        ),
      );
    }
    return result.where((e) => e.id.isNotEmpty).toList();
  }
}
