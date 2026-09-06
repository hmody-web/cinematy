import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

class ApiDiskCache {
  Directory? _directory;
  final Map<String, _MemoryEntry> _memory = {};

  Future<Directory> _dir() async {
    if (_directory != null) return _directory!;
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/cinematy_api_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    _directory = dir;
    return dir;
  }

  String _hash(String key) => sha1.convert(utf8.encode(key)).toString();

  Future<dynamic> get(String key, Duration ttl) async {
    final now = DateTime.now();
    final memory = _memory[key];
    if (memory != null && now.difference(memory.createdAt) < ttl) return memory.value;

    try {
      final dir = await _dir();
      final file = File('${dir.path}/${_hash(key)}.json');
      if (!await file.exists()) return null;
      final wrapper = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final createdAt = DateTime.tryParse(wrapper['createdAt']?.toString() ?? '');
      if (createdAt == null || now.difference(createdAt) >= ttl) {
        await file.delete();
        return null;
      }
      final value = wrapper['value'];
      _memory[key] = _MemoryEntry(value, createdAt);
      return value;
    } catch (_) {
      return null;
    }
  }

  Future<void> put(String key, dynamic value) async {
    final now = DateTime.now();
    _memory[key] = _MemoryEntry(value, now);
    try {
      final dir = await _dir();
      final file = File('${dir.path}/${_hash(key)}.json');
      await file.writeAsString(jsonEncode({'createdAt': now.toIso8601String(), 'value': value}), flush: false);
    } catch (_) {}
  }

  Future<void> clear() async {
    _memory.clear();
    try {
      final dir = await _dir();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
    } catch (_) {}
  }
}

class _MemoryEntry {
  const _MemoryEntry(this.value, this.createdAt);
  final dynamic value;
  final DateTime createdAt;
}
