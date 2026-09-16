class ApiDiskCache {
  final Map<String, _Entry> _memory = <String, _Entry>{};

  Future<dynamic> get(String key, Duration ttl) async {
    final value = _memory[key];
    if (value == null) return null;
    if (DateTime.now().difference(value.createdAt) >= ttl) {
      _memory.remove(key);
      return null;
    }
    return value.value;
  }

  Future<void> put(String key, dynamic value) async {
    _memory[key] = _Entry(value, DateTime.now());
  }

  Future<void> clear() async => _memory.clear();
}

class _Entry {
  const _Entry(this.value, this.createdAt);
  final dynamic value;
  final DateTime createdAt;
}
