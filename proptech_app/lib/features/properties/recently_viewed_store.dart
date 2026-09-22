import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'property.dart';

/// Tracks the ids of properties the user has opened, most-recently-viewed
/// first, persisted locally so the list survives an app restart.
///
/// Singleton so every screen (home, detail, etc.) shares the same state.
class RecentlyViewedStore {
  RecentlyViewedStore._();
  static final RecentlyViewedStore instance = RecentlyViewedStore._();

  static const _storageKey = 'recently_viewed_property_ids';
  static const _maxEntries = 15;
  final _storage = const FlutterSecureStorage();

  /// Ordered list of property ids, most recently viewed first.
  /// Screens can listen to this directly via ValueListenableBuilder.
  final ValueNotifier<List<String>> ids = ValueNotifier<List<String>>([]);

  bool _loaded = false;
  Future<void>? _loadFuture;

  /// Loads persisted ids from disk. Safe to call multiple times; only
  /// hits storage once.
  Future<void> load() {
    if (_loaded) return Future.value();
    return _loadFuture ??= _doLoad();
  }

  Future<void> _doLoad() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = (jsonDecode(raw) as List).cast<String>();
        ids.value = decoded;
      }
    } catch (_) {
      // Corrupt or missing data — start with an empty list rather than crash.
      ids.value = [];
    } finally {
      _loaded = true;
    }
  }

  /// Records that [propertyId] was just viewed: moves it to the front,
  /// dedupes, caps the list length, and persists it.
  Future<void> markViewed(String propertyId) async {
    await load();
    final updated = List<String>.of(ids.value)..remove(propertyId);
    updated.insert(0, propertyId);
    if (updated.length > _maxEntries) {
      updated.removeRange(_maxEntries, updated.length);
    }
    ids.value = updated;
    await _storage.write(key: _storageKey, value: jsonEncode(updated));
  }

  /// Clears the recently-viewed history entirely.
  Future<void> clear() async {
    ids.value = [];
    await _storage.delete(key: _storageKey);
  }

  /// Resolves stored ids into live [Property] objects (skipping ids that
  /// no longer exist, e.g. delisted properties), preserving
  /// most-recently-viewed-first order.
  static List<Property> resolve(List<String> ids, {int? limit}) {
    final result = <Property>[];
    for (final id in ids) {
      Property? match;
      for (final p in dummyProperties) {
        if (p.id == id) {
          match = p;
          break;
        }
      }
      if (match != null) result.add(match);
      if (limit != null && result.length >= limit) break;
    }
    return result;
  }
}