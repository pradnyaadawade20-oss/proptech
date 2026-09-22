import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../properties/property.dart';
import 'saved_search.dart';

/// Persists the user's saved searches and figures out which of them have
/// new matching properties ("naya property is criteria ka aaye to notify
/// karo"). There's no push backend here, so "notify" means: check the
/// current dummyProperties list against each saved search's criteria and
/// surface anything the user hasn't seen yet as an in-app alert/badge.
class SavedSearchStore {
  SavedSearchStore._();
  static final SavedSearchStore instance = SavedSearchStore._();

  static const _storageKey = 'saved_searches';
  final _storage = const FlutterSecureStorage();

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
        final decoded = (jsonDecode(raw) as List)
            .map((e) => SavedSearch.fromJson(e as Map<String, dynamic>))
            .toList();
        searches.value = decoded;
      }
    } catch (_) {
      searches.value = [];
    } finally {
      _loaded = true;
    }
  }

  Future<void> _persist() async {
    final encoded = jsonEncode(searches.value.map((s) => s.toJson()).toList());
    await _storage.write(key: _storageKey, value: encoded);
  }

  Future<void> add(SavedSearch search) async {
    await load();
    // Mark whatever already matches as "seen" so the alert only fires for
    // properties added after this search was saved, not the initial batch.
    final initialMatches = matchingProperties(search).map((p) => p.id).toList();
    final withSeen = search.copyWith(seenPropertyIds: initialMatches);
    searches.value = [withSeen, ...searches.value];
    await _persist();
  }

  Future<void> remove(String id) async {
    await load();
    searches.value = searches.value.where((s) => s.id != id).toList();
    await _persist();
  }

  /// All properties currently matching a saved search's criteria.
  List<Property> matchingProperties(SavedSearch search) {
    return filterProperties(
      dummyProperties,
      query: search.query,
      type: search.type,
      budgetStart: search.budgetStart,
      budgetEnd: search.budgetEnd,
    );
  }

  /// Properties matching a saved search that the user hasn't seen yet —
  /// these are the "new listing" alerts.
  List<Property> newMatches(SavedSearch search) {
    final matches = matchingProperties(search);
    return matches.where((p) => !search.seenPropertyIds.contains(p.id)).toList();
  }

  /// Total new-match count across every saved search — shown as a badge.
  int get totalNewMatches {
    var total = 0;
    for (final s in searches.value) {
      total += newMatches(s).length;
    }
    return total;
  }

  /// Marks every currently-matching property for [search] as seen, clearing
  /// its "new" alerts (call this once the user has viewed the results).
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