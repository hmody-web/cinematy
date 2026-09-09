import 'cinematy_user.dart';

enum FriendshipState {
  none,
  outgoingPending,
  incomingPending,
  friends,
  self,
}

class FriendshipStatus {
  const FriendshipStatus({
    required this.state,
    this.requestId,
  });

  final FriendshipState state;
  final int? requestId;

  bool get canSendRequest => state == FriendshipState.none;
  bool get isOutgoingPending => state == FriendshipState.outgoingPending;
  bool get isIncomingPending => state == FriendshipState.incomingPending;
  bool get areFriends => state == FriendshipState.friends;
  bool get isSelf => state == FriendshipState.self;

  factory FriendshipStatus.fromJson(Map<String, dynamic> json) {
    final raw = json['status']?.toString() ?? 'none';
    final state = switch (raw) {
      'outgoing_pending' => FriendshipState.outgoingPending,
      'incoming_pending' => FriendshipState.incomingPending,
      'friends' => FriendshipState.friends,
      'self' => FriendshipState.self,
      _ => FriendshipState.none,
    };
    return FriendshipStatus(
      state: state,
      requestId: int.tryParse(json['request_id']?.toString() ?? ''),
    );
  }
}

class FriendRequestItem {
  const FriendRequestItem({
    required this.id,
    required this.sender,
    this.createdAt,
  });

  final int id;
  final CinematyUserProfile sender;
  final DateTime? createdAt;

  factory FriendRequestItem.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true)
            .toLocal();
      }
      return DateTime.tryParse(value.toString())?.toLocal();
    }

    return FriendRequestItem(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      sender: CinematyUserProfile.fromJson(
        Map<String, dynamic>.from(json['sender'] as Map? ?? const {}),
      ),
      createdAt: parseDate(json['created_at']),
    );
  }
}
