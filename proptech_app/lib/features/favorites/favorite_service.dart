import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/api/token_store.dart';
import '../properties/property.dart';

/// Talks to /api/favorites/*. The backend derives the logged-in user from
/// the JWT (ApiClient's interceptor already attaches it), so nothing here
/// needs to pass a user id.
class FavoriteService {
  FavoriteService._();
  static final FavoriteService instance = FavoriteService._();

  final Dio _dio = ApiClient.instance.dio;

  Exception _toException(DioException e) {
    final data = e.response?.data;
    final message = (data is Map && data['error'] != null)
        ? data['error'].toString()
        : (e.message ?? 'Something went wrong.');
    return Exception(message);
  }

  Future<List<Property>> getAll() async {
    try {
      final response = await _dio.get('/api/favorites');
      final list = response.data['properties'] as List<dynamic>? ?? [];
      return list.map((e) => Property.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// Ids of the logged-in user's favorite properties. PropertyStore.load()
  /// uses this to mark hearts. Throws when not logged in (caller handles it).
  Future<Set<String>> getFavoriteIds() async {
    final favorites = await getAll();
    return favorites.map((p) => p.id).toSet();
  }

  Future<void> add(String propertyId) async {
    try {
      await _dio.post('/api/favorites', data: {'property_id': propertyId});
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  Future<void> remove(String propertyId) async {
    try {
      await _dio.delete('/api/favorites', queryParameters: {'property_id': propertyId});
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// Toggles a favorite on the backend, then updates the shared
  /// property list (dummyProperties == PropertyStore.instance.all) so every
  /// screen (home, search, favorites) shows the new heart state immediately.
  /// Throws if the API call fails, so the caller can revert its optimistic
  /// UI update.
  Future<void> toggle(String propertyId, {required bool currentlyFavorite}) async {
    if (currentlyFavorite) {
      await remove(propertyId);
    } else {
      await add(propertyId);
    }
    final idx = dummyProperties.indexWhere((p) => p.id == propertyId);
    if (idx != -1) {
      dummyProperties[idx] = dummyProperties[idx].copyWith(isFavorite: !currentlyFavorite);
      notifyPropertiesChanged();
    }
  }

  /// Called once at app startup (after login) to mark which of the loaded
  /// properties are already favorited, so hearts show correctly without
  /// the user having to tap anything first.
  Future<void> syncFavoriteFlags() async {
    if (!await TokenStore.instance.isLoggedIn()) return;
    final favorites = await getAll();
    final favoriteIds = favorites.map((p) => p.id).toSet();
    for (var i = 0; i < dummyProperties.length; i++) {
      final shouldBeFavorite = favoriteIds.contains(dummyProperties[i].id);
      if (dummyProperties[i].isFavorite != shouldBeFavorite) {
        dummyProperties[i] = dummyProperties[i].copyWith(isFavorite: shouldBeFavorite);
      }
    }
    notifyPropertiesChanged();
  }
}