import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Recent search-box queries, saved on the device so they survive a restart.
class RecentSearchStore {
  RecentSearchStore._();
  static final RecentSearchStore instance = RecentSearchStore._();

  static const _storageKey = 'recent_searches';
  static const _maxItems = 8;
  final _storage = const FlutterSecureStorage();

  final ValueNotifier<List<String>> searches = ValueNotifier<List<String>>([]);

  bool _loaded = false;
  Future<void>? _loadFuture;

  Future<void> load() {
    if (_loaded) return Future.value();
    return _loadFuture ??= _doLoad();
  }

  Future<void> _doLoad() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw != null && raw.isNotEmpty) {
        final loaded = (jsonDecode(raw) as List).map((e) => e.toString()).toList();
        // Keep anything added while loading.
        searches.value = [...searches.value, ...loaded.where((s) => !searches.value.contains(s))];
      }
    } catch (_) {
      // Ignore corrupt data.
    } finally {
      _loaded = true;
    }
  }

  Future<void> _persist() => _storage.write(key: _storageKey, value: jsonEncode(searches.value));

  Future<void> add(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final next = [q, ...searches.value.where((s) => s.toLowerCase() != q.toLowerCase())];
    searches.value = next.take(_maxItems).toList();
    await _persist();
  }

  Future<void> remove(String query) async {
    searches.value = searches.value.where((s) => s != query).toList();
    await _persist();
  }

  Future<void> clear() async {
    searches.value = [];
    await _persist();
  }
}