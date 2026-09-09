import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/app_config.dart';
import '../../data/models/cinematy_user.dart';
import '../../data/models/media_item.dart';
import '../../data/services/cinematy_account_api.dart';
import 'watch_party_models.dart';

class WatchPartyException implements Exception {
  const WatchPartyException(this.message);
  final String message;

  @override
  String toString() => message;
}

class WatchPartyService {
  WatchPartyService._()
      : _firestore = FirebaseFirestore.instance,
        _database = FirebaseDatabase.instanceFor(
          app: Firebase.app(),
          databaseURL: AppConfig.realtimeDatabaseUrl,
        );

  static final WatchPartyService instance = WatchPartyService._();

  static const _groupsCollection = 'watch_party_groups';
  static const _sessionsCollection = 'watch_party_sessions';
  static const _invitesCollection = 'watch_party_invites';

  final FirebaseFirestore _firestore;
  final FirebaseDatabase _database;

  User get _requiredUser {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const WatchPartyException('سجّل الدخول أولاً لاستخدام المشاهدة الجماعية.');
    }
    return user;
  }

  String get currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  DatabaseReference _liveRoot(String sessionId) =>
      _database.ref('watch_party_sessions/$sessionId');

  Future<WatchPartyMember> currentMember() async {
    final user = _requiredUser;
    try {
      final profile = await CinematyAccountApi.instance.me();
      if (profile.uid.isNotEmpty) return WatchPartyMember.fromProfile(profile);
    } catch (_) {
      // Firebase profile is a safe fallback when the account endpoint is busy.
    }
    return WatchPartyMember(
      uid: user.uid,
      displayName: (user.displayName ?? '').trim().isNotEmpty
          ? user.displayName!.trim()
          : 'مستخدم سينماتي',
      photoUrl: user.photoURL ?? '',
    );
  }

  Stream<List<WatchPartyGroup>> watchGroups() {
    return FirebaseAuth.instance.authStateChanges().asyncExpand((user) {
      if (user == null) return Stream.value(const <WatchPartyGroup>[]);
      return _firestore
          .collection(_groupsCollection)
          .where('memberUids', arrayContains: user.uid)
          .snapshots()
          .map((snapshot) {
        final groups = snapshot.docs
            .map((doc) => WatchPartyGroup.fromJson(doc.id, doc.data()))
            .toList();
        groups.sort((a, b) {
          final ad = a.updatedAt ?? a.createdAt ?? DateTime(2000);
          final bd = b.updatedAt ?? b.createdAt ?? DateTime(2000);
          return bd.compareTo(ad);
        });
        return groups;
      });
    });
  }

  Future<List<WatchPartyGroup>> groups() async {
    final uid = _requiredUser.uid;
    final snapshot = await _firestore
        .collection(_groupsCollection)
        .where('memberUids', arrayContains: uid)
        .get();
    final groups = snapshot.docs
        .map((doc) => WatchPartyGroup.fromJson(doc.id, doc.data()))
        .toList();
    groups.sort((a, b) {
      final ad = a.updatedAt ?? a.createdAt ?? DateTime(2000);
      final bd = b.updatedAt ?? b.createdAt ?? DateTime(2000);
      return bd.compareTo(ad);
    });
    return groups;
  }

  Future<WatchPartyGroup> createGroup({
    required String name,
    required List<CinematyUserProfile> friends,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.length < 2) {
      throw const WatchPartyException('اكتب اسماً واضحاً للمجموعة.');
    }
    if (friends.isEmpty) {
      throw const WatchPartyException('اختر صديقاً واحداً على الأقل.');
    }

    final me = await currentMember();
    final memberMap = <String, WatchPartyMember>{me.uid: me};
    for (final friend in friends) {
      if (friend.uid.isEmpty || friend.uid == me.uid) continue;
      memberMap[friend.uid] = WatchPartyMember.fromProfile(friend);
    }
    if (memberMap.length < 2) {
      throw const WatchPartyException('اختر صديقاً واحداً على الأقل.');
    }

    final ref = _firestore.collection(_groupsCollection).doc();
    final members = memberMap.values.toList();
    await ref.set({
      'name': trimmedName,
      'ownerUid': me.uid,
      'memberUids': members.map((e) => e.uid).toList(),
      'memberProfiles': members.map((e) => e.toJson()).toList(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final snap = await ref.get();
    return WatchPartyGroup.fromJson(ref.id, snap.data() ?? const {});
  }

  Future<WatchPartyGroup> updateGroup({
    required WatchPartyGroup group,
    required String name,
    required List<CinematyUserProfile> friends,
  }) async {
    final uid = _requiredUser.uid;
    if (group.ownerUid != uid) {
      throw const WatchPartyException('مالك المجموعة فقط يمكنه تعديلها.');
    }
    final trimmedName = name.trim();
    if (trimmedName.length < 2) {
      throw const WatchPartyException('اكتب اسماً واضحاً للمجموعة.');
    }
    final me = await currentMember();
    final memberMap = <String, WatchPartyMember>{me.uid: me};
    for (final friend in friends) {
      if (friend.uid.isEmpty || friend.uid == me.uid) continue;
      memberMap[friend.uid] = WatchPartyMember.fromProfile(friend);
    }
    if (memberMap.length < 2) {
      throw const WatchPartyException('يجب أن تبقى المجموعة مع صديق واحد على الأقل.');
    }
    final members = memberMap.values.toList();
    final ref = _firestore.collection(_groupsCollection).doc(group.id);
    await ref.update({
      'name': trimmedName,
      'memberUids': members.map((e) => e.uid).toList(),
      'memberProfiles': members.map((e) => e.toJson()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final snap = await ref.get();
    return WatchPartyGroup.fromJson(ref.id, snap.data() ?? const {});
  }

  Future<void> deleteGroup(WatchPartyGroup group) async {
    final uid = _requiredUser.uid;
    if (group.ownerUid != uid) {
      throw const WatchPartyException('مالك المجموعة فقط يمكنه حذفها.');
    }
    await _firestore.collection(_groupsCollection).doc(group.id).delete();
  }

  Future<WatchPartySession> createDirectSession({
    required MediaItem media,
    required CinematyUserProfile friend,
  }) async {
    if (friend.uid.isEmpty) {
      throw const WatchPartyException('تعذر تحديد حساب الصديق.');
    }
    final me = await currentMember();
    return _createSession(
      media: media,
      members: [me, WatchPartyMember.fromProfile(friend)],
    );
  }

  Future<WatchPartySession> createGroupSession({
    required MediaItem media,
    required WatchPartyGroup group,
  }) async {
    final uid = _requiredUser.uid;
    if (!group.memberUids.contains(uid)) {
      throw const WatchPartyException('أنت لست عضواً في هذه المجموعة.');
    }
    return _createSession(
      media: media,
      members: group.members,
      groupId: group.id,
      groupName: group.name,
    );
  }

  Future<WatchPartySession> _createSession({
    required MediaItem media,
    required List<WatchPartyMember> members,
    String? groupId,
    String? groupName,
  }) async {
    final me = await currentMember();
    final unique = <String, WatchPartyMember>{};
    for (final member in members) {
      if (member.uid.isNotEmpty) unique[member.uid] = member;
    }
    unique[me.uid] = me;
    if (unique.length < 2) {
      throw const WatchPartyException('المشاهدة الجماعية تحتاج شخصين على الأقل.');
    }

    final sessionRef = _firestore.collection(_sessionsCollection).doc();
    final permissions = const WatchPartyPermissions();
    final memberList = unique.values.toList();
    final mediaJson = watchPartyMediaToJson(media);

    final batch = _firestore.batch();
    final inviteRefs = <DocumentReference<Map<String, dynamic>>>[];
    batch.set(sessionRef, {
      'hostUid': me.uid,
      'groupId': groupId,
      'groupName': groupName,
      'memberUids': memberList.map((e) => e.uid).toList(),
      'memberProfiles': memberList.map((e) => e.toJson()).toList(),
      'media': mediaJson,
      'permissions': permissions.toJson(),
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final expiresAt = Timestamp.fromDate(
      DateTime.now().toUtc().add(const Duration(hours: 2)),
    );
    for (final member in memberList) {
      if (member.uid == me.uid) continue;
      final inviteRef = _firestore
          .collection(_invitesCollection)
          .doc('${sessionRef.id}_${member.uid}');
      inviteRefs.add(inviteRef);
      batch.set(inviteRef, {
        'sessionId': sessionRef.id,
        'fromUid': me.uid,
        'from': me.toJson(),
        'toUid': member.uid,
        'media': mediaJson,
        'groupId': groupId,
        'groupName': groupName,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'expiresAt': expiresAt,
      });
    }
    await batch.commit();

    final liveMembers = <String, bool>{
      for (final member in memberList) member.uid: true,
    };
    try {
      await _liveRoot(sessionRef.id).set({
        'hostUid': me.uid,
        'members': liveMembers,
        'permissions': permissions.toJson(),
        'ended': false,
        'state': {
          'eventId': _eventId(me.uid),
          'action': 'sync',
          'sourceUid': me.uid,
          'positionMs': 0,
          'playing': false,
          'playbackRate': 1.0,
          'media': mediaJson,
          'updatedAt': ServerValue.timestamp,
        },
      });
    } catch (_) {
      // Do not leave a visible invitation behind if the realtime room could
      // not be created (for example because Firebase rules were not deployed).
      try {
        final cleanup = _firestore.batch();
        cleanup.delete(sessionRef);
        for (final inviteRef in inviteRefs) {
          cleanup.delete(inviteRef);
        }
        await cleanup.commit();
      } catch (_) {}
      rethrow;
    }

    final sessionSnap = await sessionRef.get();
    return WatchPartySession.fromJson(
      sessionRef.id,
      sessionSnap.data() ?? const {},
    );
  }

  Stream<List<WatchPartyInvite>> pendingInvitesStream() {
    return FirebaseAuth.instance.authStateChanges().asyncExpand((user) {
      if (user == null) return Stream.value(const <WatchPartyInvite>[]);
      return _firestore
          .collection(_invitesCollection)
          .where('toUid', isEqualTo: user.uid)
          .snapshots()
          .map((snapshot) {
        final invites = snapshot.docs
            .map((doc) => WatchPartyInvite.fromJson(doc.id, doc.data()))
            .where((invite) => invite.pending && !invite.expired)
            .toList();
        invites.sort((a, b) {
          final ad = a.createdAt ?? DateTime(2000);
          final bd = b.createdAt ?? DateTime(2000);
          return bd.compareTo(ad);
        });
        return invites;
      });
    });
  }

  Stream<int> pendingInvitesCountStream() =>
      pendingInvitesStream().map((items) => items.length).distinct();

  /// Watches the single invitation created for a direct watch-party member.
  /// The document id is deterministic (`sessionId_uid`), so this does not need
  /// a Firestore query/index and the host receives accept/decline changes
  /// immediately.
  Stream<WatchPartyInvite?> watchInvite({
    required String sessionId,
    required String toUid,
  }) {
    if (sessionId.trim().isEmpty || toUid.trim().isEmpty) {
      return Stream.value(null);
    }
    return _firestore
        .collection(_invitesCollection)
        .doc('${sessionId}_$toUid')
        .snapshots()
        .map((snap) {
      final data = snap.data();
      if (!snap.exists || data == null) return null;
      return WatchPartyInvite.fromJson(snap.id, data);
    });
  }

  /// Cancels a room that is still waiting for invitees. Invitations are
  /// deleted (the current Firestore rules already allow the sender to delete
  /// them), then the session is removed and the realtime room is marked ended.
  Future<void> cancelPendingSession(WatchPartySession session) async {
    final uid = _requiredUser.uid;
    if (session.hostUid != uid) {
      throw const WatchPartyException('المضيف فقط يمكنه إلغاء الدعوة.');
    }

    final batch = _firestore.batch();
    for (final member in session.members) {
      if (member.uid.isEmpty || member.uid == uid) continue;
      batch.delete(
        _firestore
            .collection(_invitesCollection)
            .doc('${session.id}_${member.uid}'),
      );
    }
    batch.delete(_firestore.collection(_sessionsCollection).doc(session.id));
    await batch.commit();

    try {
      await _liveRoot(session.id).child('ended').set(true);
    } catch (_) {
      // Firestore cancellation is the source of truth. If realtime cleanup
      // fails, the stale room cannot be opened because its session was removed.
    }
  }

  Future<WatchPartySession> acceptInvite(WatchPartyInvite invite) async {
    final user = _requiredUser;
    if (invite.toUid != user.uid) {
      throw const WatchPartyException('هذه الدعوة مرتبطة بحساب آخر.');
    }
    if (invite.expired) {
      await _setInviteStatus(invite.id, 'expired');
      throw const WatchPartyException('انتهت صلاحية هذه الدعوة.');
    }
    final session = await loadSession(invite.sessionId);
    if (session == null || session.ended) {
      await _setInviteStatus(invite.id, 'ended');
      throw const WatchPartyException('انتهت جلسة المشاهدة هذه.');
    }
    if (!session.memberUids.contains(user.uid)) {
      throw const WatchPartyException('لم يعد حسابك ضمن أعضاء هذه الجلسة.');
    }
    await _setInviteStatus(invite.id, 'accepted');
    return session;
  }

  Future<void> declineInvite(WatchPartyInvite invite) async {
    final user = _requiredUser;
    if (invite.toUid != user.uid) return;
    await _setInviteStatus(invite.id, 'declined');
  }

  Future<void> _setInviteStatus(String inviteId, String status) async {
    await _firestore.collection(_invitesCollection).doc(inviteId).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<WatchPartySession?> loadSession(String sessionId) async {
    if (sessionId.trim().isEmpty) return null;
    final snap = await _firestore
        .collection(_sessionsCollection)
        .doc(sessionId)
        .get();
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return WatchPartySession.fromJson(snap.id, data);
  }

  Stream<WatchPartySession?> watchSession(String sessionId) {
    return _firestore
        .collection(_sessionsCollection)
        .doc(sessionId)
        .snapshots()
        .map((snap) {
      final data = snap.data();
      if (!snap.exists || data == null) return null;
      return WatchPartySession.fromJson(snap.id, data);
    });
  }

  Stream<WatchPartyPlaybackState?> watchPlayback(String sessionId) {
    return _liveRoot(sessionId).child('state').onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return null;
      return WatchPartyPlaybackState.fromJson(
        Map<String, dynamic>.from(value),
      );
    });
  }

  Stream<List<WatchPartyPresence>> watchPresence(String sessionId) {
    return _liveRoot(sessionId).child('presence').onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return const <WatchPartyPresence>[];
      final result = <WatchPartyPresence>[];
      for (final entry in value.entries) {
        if (entry.value is! Map) continue;
        result.add(
          WatchPartyPresence.fromJson(
            entry.key.toString(),
            Map<String, dynamic>.from(entry.value as Map),
          ),
        );
      }
      return result;
    });
  }

  Stream<bool> watchEnded(String sessionId) =>
      _liveRoot(sessionId).child('ended').onValue.map(
            (event) => event.snapshot.value == true,
          );

  Future<WatchPartyPresenceConnection> connectPresence({
    required WatchPartySession session,
    required WatchPartyMember member,
  }) async {
    final connection = WatchPartyPresenceConnection._(
      database: _database,
      root: _liveRoot(session.id),
      member: member,
    );
    await connection.start();
    return connection;
  }

  Future<void> publishPlayback({
    required String sessionId,
    required String action,
    required Duration position,
    required bool playing,
    required double playbackRate,
    MediaItem? media,
  }) async {
    final uid = _requiredUser.uid;
    final payload = <String, dynamic>{
      'eventId': _eventId(uid),
      'action': action,
      'sourceUid': uid,
      'positionMs': position.inMilliseconds,
      'playing': playing,
      'playbackRate': playbackRate,
      'updatedAt': ServerValue.timestamp,
      if (media != null) 'media': watchPartyMediaToJson(media),
    };
    await _liveRoot(sessionId).child('state').update(payload);
    if (media != null) {
      await _firestore.collection(_sessionsCollection).doc(sessionId).update({
        'media': watchPartyMediaToJson(media),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> publishHeartbeat({
    required String sessionId,
    required Duration position,
    required bool playing,
    required double playbackRate,
  }) =>
      publishPlayback(
        sessionId: sessionId,
        action: 'heartbeat',
        position: position,
        playing: playing,
        playbackRate: playbackRate,
      );

  Future<void> updatePermissions({
    required WatchPartySession session,
    required WatchPartyPermissions permissions,
  }) async {
    final uid = _requiredUser.uid;
    if (uid != session.hostUid) {
      throw const WatchPartyException('المضيف فقط يمكنه تعديل صلاحيات الروم.');
    }
    await Future.wait([
      _firestore.collection(_sessionsCollection).doc(session.id).update({
        'permissions': permissions.toJson(),
        'updatedAt': FieldValue.serverTimestamp(),
      }),
      _liveRoot(session.id).child('permissions').set(permissions.toJson()),
    ]);
  }

  Future<void> endSession(WatchPartySession session) async {
    final uid = _requiredUser.uid;
    if (uid != session.hostUid) return;
    try {
      await _firestore.collection(_sessionsCollection).doc(session.id).update({
        'status': 'ended',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
    try {
      await _liveRoot(session.id).child('ended').set(true);
    } catch (_) {}
  }

  bool canPlayPause(WatchPartySession session) =>
      currentUid == session.hostUid || session.permissions.everyoneCanPlayPause;

  bool canSeek(WatchPartySession session) =>
      currentUid == session.hostUid || session.permissions.everyoneCanSeek;

  bool canChangeEpisode(WatchPartySession session) =>
      currentUid == session.hostUid ||
      session.permissions.everyoneCanChangeEpisode;

  bool canChangeSpeed(WatchPartySession session) =>
      currentUid == session.hostUid || session.permissions.everyoneCanChangeSpeed;

  static String _eventId(String uid) =>
      '${uid}_${DateTime.now().microsecondsSinceEpoch}';
}

class WatchPartyPresenceConnection {
  WatchPartyPresenceConnection._({
    required FirebaseDatabase database,
    required DatabaseReference root,
    required WatchPartyMember member,
  })  : _database = database,
        _root = root,
        _member = member;

  final FirebaseDatabase _database;
  final DatabaseReference _root;
  final WatchPartyMember _member;
  StreamSubscription<DatabaseEvent>? _connectionSub;
  bool _closed = false;
  bool _buffering = false;

  DatabaseReference get _presence => _root.child('presence/${_member.uid}');

  Future<void> start() async {
    _connectionSub = _database.ref('.info/connected').onValue.listen((event) {
      if (_closed || event.snapshot.value != true) return;
      unawaited(_markConnected());
    });
    await _markConnected();
  }

  Future<void> _markConnected() async {
    if (_closed) return;
    try {
      await _presence.set({
        'displayName': _member.displayName,
        'state': 'active',
        'buffering': _buffering,
        'updatedAt': ServerValue.timestamp,
      });
      await _presence.onDisconnect().set({
        'displayName': _member.displayName,
        'state': 'left',
        'buffering': false,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (error) {
      debugPrint('[WatchParty] presence connect failed: $error');
    }
  }

  Future<void> setBuffering(bool value) async {
    if (_closed || _buffering == value) return;
    _buffering = value;
    try {
      await _presence.update({
        'state': 'active',
        'buffering': value,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (error) {
      debugPrint('[WatchParty] buffering presence failed: $error');
    }
  }

  Future<void> handoff() async {
    if (_closed) return;
    _closed = true;
    await _connectionSub?.cancel();
    try {
      await _presence.onDisconnect().cancel();
    } catch (_) {}
  }

  Future<void> leave() async {
    if (_closed) return;
    _closed = true;
    await _connectionSub?.cancel();
    try {
      await _presence.onDisconnect().cancel();
    } catch (_) {}
    try {
      await _presence.set({
        'displayName': _member.displayName,
        'state': 'left',
        'buffering': false,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (_) {}
  }
}
