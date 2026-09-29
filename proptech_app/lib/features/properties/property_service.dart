import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/api/api_client.dart';
import 'property.dart';

/// Talks to /api/properties/*. Add Property and Home listing use this to
/// create/list real properties (with real UUIDs + owner_id) instead of
/// the local dummyProperties list.
class PropertyService {
  PropertyService._();
  static final PropertyService instance = PropertyService._();

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
      final response = await _dio.get('/api/properties');
      final list = response.data['properties'] as List<dynamic>? ?? [];
      return list.map((e) => Property.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// Properties listed by a specific owner (backs the "Listed" count on
  /// Owner Details, and the My Properties screen). Backend endpoint is
  /// /api/properties/my?owner_id=... (kept as "/my" for the logged-in
  /// owner's own dashboard; also usable to look up any owner by id).
  Future<List<Property>> getByOwner(String ownerId) async {
    try {
      final response = await _dio.get('/api/properties/my', queryParameters: {'owner_id': ownerId});
      final list = response.data['properties'] as List<dynamic>? ?? [];
      return list.map((e) => Property.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  Future<Property> create({
    required String ownerId,
    required String title,
    required String imageUrl,
    required double price,
    required String priceUnit,
    required String bhk,
    required String furnishing,
    required String location,
    required String category,
    required List<String> amenities,
  }) async {
    try {
      final response = await _dio.post('/api/properties', data: {
        'owner_id': ownerId,
        'title': title,
        'image_url': imageUrl,
        'price': price,
        'price_unit': priceUnit,
        'bhk': bhk,
        'furnishing': furnishing,
        'location': location,
        'category': category,
        'amenities': amenities,
      });
      return Property.fromJson(response.data['property'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// Uploads the actual picked photo's bytes for [propertyId] and returns
  /// the real image_url (serving those exact bytes back) so every screen
  /// — owner's own listing, buyer's browse/detail screens, home — shows
  /// the real photo instead of a placeholder.
  Future<String> uploadImage(String propertyId, XFile image) async {
    try {
      final bytes = await image.readAsBytes();
      final formData = FormData.fromMap({
        'image': MultipartFile.fromBytes(bytes, filename: image.name),
      });
      final response = await _dio.post('/api/properties/$propertyId/image', data: formData);
      return response.data['image_url'] as String;
    } on DioException catch (e) {
      throw _toException(e);
    }
  }
}