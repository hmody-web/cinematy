class CinematyUserProfile {
  const CinematyUserProfile({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.photoUrl,
    required this.handle,
    required this.favoritesCount,
    required this.canChangeHandle,
    this.nextHandleChangeAt,
    this.createdAt,
    this.updatedAt,
  });

  final String uid;
  final String displayName;
  final String email;
  final String photoUrl;
  final String? handle;
  final int favoritesCount;
  final bool canChangeHandle;
  final DateTime? nextHandleChangeAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasHandle => handle?.trim().isNotEmpty == true;

  factory CinematyUserProfile.fromJson(Map<String, dynamic> json) {
    DateTime? date(dynamic value) {
      if (value == null) return null;
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(
          value * 1000,
          isUtc: true,
        ).toLocal();
      }
      return DateTime.tryParse(value.toString())?.toLocal();
    }

    final rawHandle = json['handle']?.toString().trim() ?? '';

    return CinematyUserProfile(
      uid: json['uid']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      photoUrl: json['photo_url']?.toString() ?? '',
      handle: rawHandle.isEmpty ? null : rawHandle,
      favoritesCount:
          int.tryParse(json['favorites_count']?.toString() ?? '') ?? 0,
      canChangeHandle: json['can_change_handle'] == true ||
          json['can_change_handle']?.toString() == '1',
      nextHandleChangeAt: date(json['next_handle_change_at']),
      createdAt: date(json['created_at']),
      updatedAt: date(json['updated_at']),
    );
  }
}
