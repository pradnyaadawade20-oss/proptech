import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../properties/property.dart';
import '../properties/property_store.dart';
import 'saved_search.dart';

/// Persists the user's saved searches and works out which of them have new
/// matching properties. There's no push backend here, so "notify" means:
/// check the current PropertyStore.instance.all list against each saved
/// search's criteria and surface anything the user hasn't seen yet as an
/// in-app alert/badge.
class SavedSearchStore {
  SavedSearchStore._();
  static final SavedSearchStore instance = SavedSearchStore._();

  static const _storageKey = 'saved_searches';
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final ValueNotifier<List<SavedSearch>> searches = ValueNotifier<List<SavedSearch>>([]);

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
        final list = jsonDecode(raw) as List;
        final decoded = <SavedSearch>[];
        for (final e in list) {
          // One bad entry must not wipe every saved search.
          try {
            decoded.add(SavedSearch.fromJson(Map<String, dynamic>.from(e as Map)));
          } catch (err) {
            debugPrint('SavedSearchStore: skipped unreadable entry: $err');
          }
        }
        searches.value = decoded;
      }
    } catch (err, st) {
      debugPrint('SavedSearchStore: load failed: $err\n$st');
    } finally {
      _loaded = true;
    }
  }

  Future<bool> _persist() async {
    try {
      final encoded = jsonEncode(searches.value.map((s) => s.toJson()).toList());
      await _storage.write(key: _storageKey, value: encoded);
      return true;
    } catch (err, st) {
      debugPrint('SavedSearchStore: persist failed: $err\n$st');
      return false;
    }
  }

  /// Returns false if the search could not be written to storage (it is still
  /// kept in memory for this session).
  Future<bool> add(SavedSearch search) async {
    await load();
    // Mark whatever already matches as "seen" so the alert only fires for
    // properties added after this search was saved, not the initial batch.
    var initialMatches = <String>[];
    try {
      initialMatches = matchingProperties(search).map((p) => p.id).toList();
    } catch (err, st) {
      debugPrint('SavedSearchStore: matching failed: $err\n$st');
    }
    final withSeen = search.copyWith(seenPropertyIds: initialMatches);
    searches.value = [withSeen, ...searches.value];
    return _persist();
  }

  Future<void> remove(String id) async {
    await load();
    searches.value = searches.value.where((s) => s.id != id).toList();
    await _persist();
  }

  /// All properties currently matching a saved search's criteria.
  List<Property> matchingProperties(SavedSearch search) {
    return search.criteria.apply(PropertyStore.instance.all);
  }

  /// Properties matching a saved search that the user hasn't seen yet.
  List<Property> newMatches(SavedSearch search) {
    final matches = matchingProperties(search);
    return matches.where((p) => !search.seenPropertyIds.contains(p.id)).toList();
  }

  /// Total new-match count across every saved search, shown as a badge.
  int get totalNewMatches {
    var total = 0;
    for (final s in searches.value) {
      try {
        total += newMatches(s).length;
      } catch (_) {}
    }
    return total;
  }

  /// Marks every currently-matching property for [search] as seen.
  Future<void> markSeen(SavedSearch search) async {
    await load();
    final allMatchIds = matchingProperties(search).map((p) => p.id).toList();
    final index = searches.value.indexWhere((s) => s.id == search.id);
    if (index == -1) return;
    final updated = List<SavedSearch>.of(searches.value);
    updated[index] = search.copyWith(seenPropertyIds: allMatchIds);
    searches.value = updated;
    await _persist();
  }
}