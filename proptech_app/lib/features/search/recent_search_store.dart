import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Last few search texts the user ran, saved on the device so they survive
/// an app restart. Shown as "Recent Searches" chips on the search screen.
class RecentSearchStore {
  RecentSearchStore._();
  static final RecentSearchStore instance = RecentSearchStore._();

  static const _storageKey = 'recent_searches';
  static const _maxItems = 8;
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

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
        searches.value = (jsonDecode(raw) as List).map((e) => e.toString()).toList();
      }
    } catch (err) {
      debugPrint('RecentSearchStore: load failed: $err');
    } finally {
      _loaded = true;
    }
  }

  Future<void> _persist() async {
    try {
      await _storage.write(key: _storageKey, value: jsonEncode(searches.value));
    } catch (err) {
      debugPrint('RecentSearchStore: persist failed: $err');
    }
  }

  Future<void> add(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    await load();
    final next = <String>[
      q,
      ...searches.value.where((s) => s.toLowerCase() != q.toLowerCase()),
    ];
    searches.value = next.take(_maxItems).toList();
    await _persist();
  }

  Future<void> remove(String query) async {
    await load();
    searches.value = searches.value.where((s) => s != query).toList();
    await _persist();
  }

  Future<void> clear() async {
    searches.value = [];
    await _persist();
  }
}