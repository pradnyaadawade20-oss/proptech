import 'package:flutter/widgets.dart';
import '../favorites/favorite_service.dart';
import 'property.dart';
import 'property_service.dart';

/// In-memory cache of the real properties returned by the backend
/// (GET /api/properties) plus the logged-in user's favorites. Replaces the
/// old hard-coded sample list — every screen reads from [all].
/// Order is newest first (same as the API).
class PropertyStore {
  PropertyStore._();
  static final PropertyStore instance = PropertyStore._();

  final List<Property> all = [];
  bool loading = false;
  bool loaded = false;
  String? error;

  /// Fetches properties + favorites. Safe to call repeatedly (pull-to-refresh,
  /// after adding a listing, after login).
  Future<void> load() async {
    if (loading) return;
    loading = true;
    error = null;
    notifyPropertiesChanged();
    try {
      final fetched = await PropertyService.instance.getAll();
      Set<String> favIds = {};
      try {
        favIds = await FavoriteService.instance.getFavoriteIds();
      } catch (_) {
        // Favorites need a logged-in user; browsing still works without them.
      }
      all
        ..clear()
        ..addAll(fetched.map((p) => p.copyWith(isFavorite: favIds.contains(p.id))));
      loaded = true;
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      loading = false;
      notifyPropertiesChanged();
    }
  }

  /// Clears the cache (call on logout so the next user doesn't see stale data).
  void clear() {
    all.clear();
    loaded = false;
    error = null;
    notifyPropertiesChanged();
  }

  Property? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Returns the cached property, or fetches it from the backend if it isn't
  /// cached yet (e.g. opened from a deep link / notification).
  Future<Property?> ensure(String id) async {
    final cached = byId(id);
    if (cached != null) return cached;
    try {
      final fetched = await PropertyService.instance.getById(id);
      all.add(fetched);
      notifyPropertiesChanged();
      return fetched;
    } catch (_) {
      return null;
    }
  }

  /// Newly listed property goes to the top (newest first).
  void add(Property property) {
    all.removeWhere((p) => p.id == property.id);
    all.insert(0, property);
    notifyPropertiesChanged();
  }

  void replace(Property property) {
    final i = all.indexWhere((p) => p.id == property.id);
    if (i != -1) {
      all[i] = property;
      notifyPropertiesChanged();
    }
  }

  /// Optimistic favorite toggle that is persisted on the backend; rolls back
  /// if the request fails. Returns true on success.
  Future<bool> toggleFavorite(String id) async {
    final i = all.indexWhere((p) => p.id == id);
    if (i == -1) return false;
    final original = all[i];
    final next = !original.isFavorite;
    all[i] = original.copyWith(isFavorite: next);
    notifyPropertiesChanged();
    try {
      if (next) {
        await FavoriteService.instance.add(id);
      } else {
        await FavoriteService.instance.remove(id);
      }
      return true;
    } catch (_) {
      final j = all.indexWhere((p) => p.id == id);
      if (j != -1) all[j] = original;
      notifyPropertiesChanged();
      return false;
    }
  }

  List<Property> get favorites => all.where((p) => p.isFavorite).toList();
}

/// Add to a screen's State (`with PropertyStoreListener<MyScreen>`) so it
/// rebuilds whenever the store loads, adds a listing or toggles a favorite.
mixin PropertyStoreListener<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    propertiesVersion.addListener(_onPropertyStoreChanged);
  }

  @override
  void dispose() {
    propertiesVersion.removeListener(_onPropertyStoreChanged);
    super.dispose();
  }

  void _onPropertyStoreChanged() {
    if (mounted) setState(() {});
  }
}