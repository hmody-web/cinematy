enum NetworkAccessKind {
  online,
  offline,
  outsideEarthlink,
}

class NetworkAccessState {
  const NetworkAccessState(this.kind, {this.details = ''});

  final NetworkAccessKind kind;
  final String details;

  bool get isOnline => kind == NetworkAccessKind.online;
  bool get isOffline => kind == NetworkAccessKind.offline;
  bool get isOutsideEarthlink => kind == NetworkAccessKind.outsideEarthlink;
}
