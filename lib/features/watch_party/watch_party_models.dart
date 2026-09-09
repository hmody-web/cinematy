import 'package:cloud_firestore/cloud_firestore.dart';

import '../../data/models/cinematy_user.dart';
import '../../data/models/media_item.dart';

DateTime? _watchPartyDate(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate().toLocal();
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true).toLocal();
  }
  return DateTime.tryParse(value.toString())?.toLocal();
}

dynamic _watchPartySafeValue(dynamic value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is Map) {
    final output = <String, dynamic>{};
    for (final entry in value.entries) {
      final key = entry.key
          .toString()
          .replaceAll(RegExp(r'[.#$\[\]/]'), '_');
      if (key.isEmpty) continue;
      output[key] = _watchPartySafeValue(entry.value);
    }
    return output;
  }
  if (value is Iterable) {
    return value.map(_watchPartySafeValue).toList();
  }
  return value.toString();
}

Map<String, dynamic> watchPartyMediaToJson(MediaItem media) => {
      'id': media.id,
      'title': media.title,
      'description': media.description,
      'posterUrl': media.posterUrl,
      'backdropUrl': media.backdropUrl,
      'year': media.year,
      'rating': media.rating,
      'views': media.views,
      'isSeries': media.isSeries,
      if (media.season != null) 'season': media.season,
      if (media.episode != null) 'episode': media.episode,
      // Realtime Database rejects special key characters, so normalize any
      // source metadata before it is shared with the room.
      'raw': _watchPartySafeValue(media.raw),
    };

MediaItem watchPartyMediaFromJson(Map<String, dynamic> json) {
  final raw = json['raw'];
  return MediaItem(
    id: json['id']?.toString() ?? '',
    title: json['title']?.toString() ?? 'بدون عنوان',
    description: json['description']?.toString() ?? '',
    posterUrl: json['posterUrl']?.toString() ?? '',
    backdropUrl: json['backdropUrl']?.toString() ?? '',
    year: int.tryParse(json['year']?.toString() ?? '') ?? 0,
    rating: double.tryParse(json['rating']?.toString() ?? '') ?? 0,
    views: int.tryParse(json['views']?.toString() ?? '') ?? 0,
    isSeries: json['isSeries'] == true || json['isSeries']?.toString() == '1',
    season: int.tryParse(json['season']?.toString() ?? ''),
    episode: int.tryParse(json['episode']?.toString() ?? ''),
    raw: raw is Map ? Map<String, dynamic>.from(raw) : const {},
  );
}

class WatchPartyMember {
  const WatchPartyMember({
    required this.uid,
    required this.displayName,
    required this.photoUrl,
    this.handle,
  });

  final String uid;
  final String displayName;
  final String photoUrl;
  final String? handle;

  factory WatchPartyMember.fromProfile(CinematyUserProfile profile) =>
      WatchPartyMember(
        uid: profile.uid,
        displayName: profile.displayName,
        photoUrl: profile.photoUrl,
        handle: profile.handle,
      );

  factory WatchPartyMember.fromJson(Map<String, dynamic> json) {
    final rawHandle = json['handle']?.toString().trim() ?? '';
    return WatchPartyMember(
      uid: json['uid']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      photoUrl: json['photoUrl']?.toString() ?? '',
      handle: rawHandle.isEmpty ? null : rawHandle,
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'displayName': displayName,
        'photoUrl': photoUrl,
        if (handle?.isNotEmpty == true) 'handle': handle,
      };
}

class WatchPartyPermissions {
  const WatchPartyPermissions({
    this.everyoneCanPlayPause = true,
    this.everyoneCanSeek = true,
    this.everyoneCanChangeEpisode = true,
    this.everyoneCanChangeSpeed = true,
  });

  final bool everyoneCanPlayPause;
  final bool everyoneCanSeek;
  final bool everyoneCanChangeEpisode;
  final bool everyoneCanChangeSpeed;

  factory WatchPartyPermissions.fromJson(Map<String, dynamic> json) =>
      WatchPartyPermissions(
        everyoneCanPlayPause: json['everyoneCanPlayPause'] != false,
        everyoneCanSeek: json['everyoneCanSeek'] != false,
        everyoneCanChangeEpisode: json['everyoneCanChangeEpisode'] != false,
        everyoneCanChangeSpeed: json['everyoneCanChangeSpeed'] != false,
      );

  Map<String, dynamic> toJson() => {
        'everyoneCanPlayPause': everyoneCanPlayPause,
        'everyoneCanSeek': everyoneCanSeek,
        'everyoneCanChangeEpisode': everyoneCanChangeEpisode,
        'everyoneCanChangeSpeed': everyoneCanChangeSpeed,
      };

  WatchPartyPermissions copyWith({
    bool? everyoneCanPlayPause,
    bool? everyoneCanSeek,
    bool? everyoneCanChangeEpisode,
    bool? everyoneCanChangeSpeed,
  }) =>
      WatchPartyPermissions(
        everyoneCanPlayPause:
            everyoneCanPlayPause ?? this.everyoneCanPlayPause,
        everyoneCanSeek: everyoneCanSeek ?? this.everyoneCanSeek,
        everyoneCanChangeEpisode:
            everyoneCanChangeEpisode ?? this.everyoneCanChangeEpisode,
        everyoneCanChangeSpeed:
            everyoneCanChangeSpeed ?? this.everyoneCanChangeSpeed,
      );
}

class WatchPartyGroup {
  const WatchPartyGroup({
    required this.id,
    required this.name,
    required this.ownerUid,
    required this.members,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String ownerUid;
  final List<WatchPartyMember> members;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  List<String> get memberUids => members.map((e) => e.uid).toList();

  factory WatchPartyGroup.fromJson(String id, Map<String, dynamic> json) {
    final rawMembers = json['memberProfiles'];
    final members = rawMembers is List
        ? rawMembers
            .whereType<Map>()
            .map((e) => WatchPartyMember.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.uid.isNotEmpty)
            .toList()
        : <WatchPartyMember>[];
    return WatchPartyGroup(
      id: id,
      name: json['name']?.toString() ?? 'مجموعة مشاهدة',
      ownerUid: json['ownerUid']?.toString() ?? '',
      members: members,
      createdAt: _watchPartyDate(json['createdAt']),
      updatedAt: _watchPartyDate(json['updatedAt']),
    );
  }
}

class WatchPartySession {
  const WatchPartySession({
    required this.id,
    required this.hostUid,
    required this.media,
    required this.members,
    required this.permissions,
    this.groupId,
    this.groupName,
    this.status = 'active',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String hostUid;
  final MediaItem media;
  final List<WatchPartyMember> members;
  final WatchPartyPermissions permissions;
  final String? groupId;
  final String? groupName;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get ended => status == 'ended';
  List<String> get memberUids => members.map((e) => e.uid).toList();

  WatchPartyMember? memberByUid(String uid) {
    for (final member in members) {
      if (member.uid == uid) return member;
    }
    return null;
  }

  factory WatchPartySession.fromJson(String id, Map<String, dynamic> json) {
    final rawMedia = json['media'];
    final rawMembers = json['memberProfiles'];
    final rawPermissions = json['permissions'];
    return WatchPartySession(
      id: id,
      hostUid: json['hostUid']?.toString() ?? '',
      media: watchPartyMediaFromJson(
        rawMedia is Map ? Map<String, dynamic>.from(rawMedia) : const {},
      ),
      members: rawMembers is List
          ? rawMembers
              .whereType<Map>()
              .map(
                (e) => WatchPartyMember.fromJson(Map<String, dynamic>.from(e)),
              )
              .where((e) => e.uid.isNotEmpty)
              .toList()
          : const [],
      permissions: WatchPartyPermissions.fromJson(
        rawPermissions is Map
            ? Map<String, dynamic>.from(rawPermissions)
            : const {},
      ),
      groupId: json['groupId']?.toString(),
      groupName: json['groupName']?.toString(),
      status: json['status']?.toString() ?? 'active',
      createdAt: _watchPartyDate(json['createdAt']),
      updatedAt: _watchPartyDate(json['updatedAt']),
    );
  }
}

class WatchPartyInvite {
  const WatchPartyInvite({
    required this.id,
    required this.sessionId,
    required this.from,
    required this.toUid,
    required this.media,
    required this.status,
    this.groupName,
    this.createdAt,
    this.expiresAt,
  });

  final String id;
  final String sessionId;
  final WatchPartyMember from;
  final String toUid;
  final MediaItem media;
  final String status;
  final String? groupName;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  bool get pending => status == 'pending';
  bool get expired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!.toLocal());

  factory WatchPartyInvite.fromJson(String id, Map<String, dynamic> json) {
    final rawFrom = json['from'];
    final rawMedia = json['media'];
    return WatchPartyInvite(
      id: id,
      sessionId: json['sessionId']?.toString() ?? '',
      from: WatchPartyMember.fromJson(
        rawFrom is Map ? Map<String, dynamic>.from(rawFrom) : const {},
      ),
      toUid: json['toUid']?.toString() ?? '',
      media: watchPartyMediaFromJson(
        rawMedia is Map ? Map<String, dynamic>.from(rawMedia) : const {},
      ),
      status: json['status']?.toString() ?? 'pending',
      groupName: json['groupName']?.toString(),
      createdAt: _watchPartyDate(json['createdAt']),
      expiresAt: _watchPartyDate(json['expiresAt']),
    );
  }
}

class WatchPartyPlaybackState {
  const WatchPartyPlaybackState({
    required this.action,
    required this.sourceUid,
    required this.positionMs,
    required this.playing,
    required this.playbackRate,
    required this.updatedAtMs,
    this.media,
    this.eventId = '',
  });

  final String action;
  final String sourceUid;
  final int positionMs;
  final bool playing;
  final double playbackRate;
  final int updatedAtMs;
  final MediaItem? media;
  final String eventId;

  factory WatchPartyPlaybackState.fromJson(Map<String, dynamic> json) {
    final rawMedia = json['media'];
    return WatchPartyPlaybackState(
      action: json['action']?.toString() ?? 'sync',
      sourceUid: json['sourceUid']?.toString() ?? '',
      positionMs: int.tryParse(json['positionMs']?.toString() ?? '') ?? 0,
      playing: json['playing'] == true || json['playing']?.toString() == '1',
      playbackRate:
          double.tryParse(json['playbackRate']?.toString() ?? '') ?? 1.0,
      updatedAtMs: int.tryParse(json['updatedAt']?.toString() ?? '') ?? 0,
      media: rawMedia is Map
          ? watchPartyMediaFromJson(Map<String, dynamic>.from(rawMedia))
          : null,
      eventId: json['eventId']?.toString() ?? '',
    );
  }
}

class WatchPartyPresence {
  const WatchPartyPresence({
    required this.uid,
    required this.displayName,
    required this.state,
    required this.buffering,
    required this.updatedAtMs,
  });

  final String uid;
  final String displayName;
  final String state;
  final bool buffering;
  final int updatedAtMs;

  bool get active => state == 'active';

  factory WatchPartyPresence.fromJson(String uid, Map<String, dynamic> json) =>
      WatchPartyPresence(
        uid: uid,
        displayName: json['displayName']?.toString() ?? 'صديقك',
        state: json['state']?.toString() ?? 'active',
        buffering:
            json['buffering'] == true || json['buffering']?.toString() == '1',
        updatedAtMs: int.tryParse(json['updatedAt']?.toString() ?? '') ?? 0,
      );
}
